# smartctl_exporter host install (Proxmox, one-time)

Companion to #198, which shipped the cluster side (selectorless Service +
manual Endpoints → `192.168.227.195:9633`, ServiceMonitor, SMART/NVMe
PrometheusRules). Those rules have no data until the exporter runs **on the
Proxmox host itself** — the VMs only see `QEMU HARDDISK` virtio-scsi devices
with no SMART passthrough, and the `SmartctlExporterDown` alert deliberately
pages until this is done.

The bastion has no SSH path to the PVE host (only 8006 is reachable), so
this is a copy-paste session on the host's own shell (Proxmox web console →
node → Shell, or wherever root@pam lands you).

## 1. Install the binary (pinned + checksum-verified)

```sh
# smartctl itself (PVE usually ships it; idempotent either way)
apt-get install -y smartmontools

cd /root
VER=0.14.0
curl -sSLO "https://github.com/prometheus-community/smartctl_exporter/releases/download/v${VER}/smartctl_exporter-${VER}.linux-amd64.tar.gz"
echo "875983cd27affc5a682401930e5a8eea3f06c325fe6d6a7228c5547d882685b3  smartctl_exporter-${VER}.linux-amd64.tar.gz" | sha256sum -c
# -> must print OK; stop on mismatch
tar -xzf "smartctl_exporter-${VER}.linux-amd64.tar.gz"
install -m 0755 "smartctl_exporter-${VER}.linux-amd64/smartctl_exporter" /usr/local/bin/smartctl_exporter
/usr/local/bin/smartctl_exporter --version
```

## 2. Systemd unit

```sh
cat > /etc/systemd/system/smartctl_exporter.service <<'EOF'
[Unit]
Description=Prometheus smartctl exporter (NVMe/SMART health for the OKD cluster)
Documentation=https://github.com/prometheus-community/smartctl_exporter
After=network-online.target
Wants=network-online.target

[Service]
# root: smartctl needs raw /dev access for NVMe admin commands
ExecStart=/usr/local/bin/smartctl_exporter --web.listen-address=:9633
Restart=on-failure
RestartSec=10
ProtectSystem=strict
ProtectHome=true
PrivateTmp=true
NoNewPrivileges=true

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now smartctl_exporter
systemctl status --no-pager smartctl_exporter
curl -s localhost:9633/metrics | grep -c '^smartctl_'
# -> nonzero; specifically check:
curl -s localhost:9633/metrics | grep smartctl_device_smart_status
```

## 3. Open :9633 to the cluster subnet

Only 8006 is reachable from the cluster network today. If the PVE firewall
is doing that filtering:

```sh
pve-firewall status
# if "Status: enabled/running":
pvesh create /nodes/$(hostname)/firewall/rules \
  --type in --action ACCEPT --proto tcp --dport 9633 \
  --source 192.168.227.0/24 \
  --comment "smartctl_exporter scrape from okd (observability/smartctl-exporter)" \
  --enable 1
```

If `pve-firewall status` says disabled but step 4's bastion curl still
fails, the filter lives elsewhere (router/upstream ACL) — open
`tcp/9633 from 192.168.227.0/24 to .195` there instead.

## 4. Verify end-to-end

From the bastion (`ssh okdadmin@192.168.227.20`):

```sh
curl -s http://192.168.227.195:9633/metrics | grep smartctl_device_smart_status
# -> smartctl_device_smart_status{...} 1 per physical disk

oc -n observability get svc,endpoints smartctl-exporter
# -> Endpoints 192.168.227.195:9633 (shipped by #198; nothing to change)
```

Within ~2 scrape intervals (60s each) the UWM Prometheus target goes up;
within 30 minutes `SmartctlExporterDown` resolves. Sanity-check a value in
Grafana: `smartctl_device_available_spare` / `smartctl_device_percentage_used`
for the NVMe.

## Upgrades

Pinned to v0.14.0 by checksum. To bump: new tarball + new line from the
release's `sha256sums.txt`, repeat step 1, `systemctl restart
smartctl_exporter`. Nothing on the cluster side references the version.
