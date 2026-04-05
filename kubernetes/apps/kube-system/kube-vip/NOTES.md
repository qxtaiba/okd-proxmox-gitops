# kube-vip notes

## Role

kube-vip provides the **control-plane VIP** for this OKD cluster. It is
deployed as a DaemonSet on all master / control-plane nodes and announces a
single virtual IP via ARP, with leader election so only one node answers for
the VIP at a time.

## Configuration constraints

### Hardcoded VIP: `192.168.227.10`

The VIP is hardcoded in `app/daemonset.yaml` (see the `address` env var).

- **Why hardcoded**: no DHCP reservation mechanism is wired up for this IP.
- **Constraint**: `192.168.227.10` must remain unclaimed on the cluster
  subnet. Before rolling out this DaemonSet on a new cluster, verify no
  other device is already using `.10` (`arping 192.168.227.10` or check
  the router's DHCP leases).
- **Drift risk**: if the Proxmox network topology ever changes
  (different subnet), the VIP must be manually updated here and in any
  OKD `install-config.yaml` / apiserver cert SAN list.

### IPVS load balancing disabled (`lb_enable: "false"`)

kube-vip normally supports L4 load balancing across API servers via IPVS.
That mode is **deliberately disabled** here because OKD's API server TLS
certificates do not include per-node IPs in their SAN lists — kube-vip's
IPVS health checks probe node IPs directly and fail with TLS verification
errors.

With IPVS disabled, kube-vip still provides VIP failover via ARP mode
(`cp_enable: "true"`): whichever node holds the leader lease answers ARP
requests for the VIP. API traffic lands on that node and is served
directly by its local API server. Failover is ~15s (lease duration).

### Services disabled (`svc_enable: "false"`)

kube-vip can also advertise LoadBalancer service IPs, but that role is
handled by MetalLB in this cluster. kube-vip is control-plane-only; MetalLB
handles the `192.168.227.205-230` LoadBalancer pool.

## Bootstrap

The DaemonSet depends on a static pod configuration applied via
MachineConfig (`kubernetes/apps/openshift-machineconfig/kube-vip-bootstrap/`)
that runs kube-vip as a static pod during OKD install, before the real
DaemonSet can be scheduled. This is the chicken-and-egg workaround: the API
server VIP must exist before kubelet can reach the API to schedule the
DaemonSet.

## References

- kube-vip docs: https://kube-vip.io/docs/
- kube-vip ARP mode: https://kube-vip.io/docs/usage/cloud-provider/#arp-mode
- OKD API SAN limitation: OKD 4.x does not include node IPs in apiserver
  SANs by default. The `apiservers.config.openshift.io/cluster` CR can
  extend SANs but doing so across a running cluster requires care.
