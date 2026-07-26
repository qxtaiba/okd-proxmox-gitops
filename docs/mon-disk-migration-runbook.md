# Mon-disk migration runbook (live, gated)

Status: authored, NOT executed. Every step in "Live sequence" is run by the
operator under supervision. Supersedes the execution sketch in
[mon-disk-proposal.md](mon-disk-proposal.md) — the end-state is unchanged,
the sequencing is corrected for how MCO and rook actually behave (see
"Deviations from the proposal").

## End-state

- Each master has a dedicated 20 GiB Proxmox disk (`scsi2`, serial
  `MON-DATA`, xfs label `rookmon`) mounted at `/var/lib/rook` by the
  `99-master-rook-mon-disk` MachineConfig in this repo.
- The ceph mon stores (~130 MiB each today) live on that disk; nothing else
  can consume its space. `MON_DISK_LOW` cannot recur unless a mon store
  itself grows ~150x.
- The kubelet image-GC stopgaps (`master-image-gc`, `worker-image-gc`) are
  reverted in a follow-up PR (demolition step, per the proposal's DoD).
- No rook/CephCluster change is needed: `dataDirHostPath` stays
  `/var/lib/rook`, mons stay on hostpath. The helm values are untouched.

## Moving parts

| PR | Repo | Content | Merge timing |
|----|------|---------|--------------|
| okdctl #957 | qxtaiba/okdctl | opt-in `master_mon_disk_size_gb` → scsi2 MON-DATA disk | any time (default 0, changes nothing) |
| this PR | okd-proxmox-gitops | `99-master-rook-mon-disk` MC + this runbook | **Phase 3 only** — merging triggers the rollout via Flux+MCO |

Facts this runbook relies on (verified live 2026-07-26):

- mons: `d`→master1 (.23), `f`→master2 (.24), `g`→master0 (.22) — re-check
  at run time with `oc -n rook-ceph get pods -l app=rook-ceph-mon -o wide`;
  letters drift on failover.
- mon pods carry an `init-mon-fs` init container: on an empty
  `/var/lib/rook/mon-X`, it runs `ceph-mon --mkfs` and the mon resyncs its
  store from quorum peers. This is the migration mechanism — store files are
  never copied.
- udev names the disk `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2`
  (drive id, not the MON-DATA serial — same behavior as the existing
  CEPH-DATA/`drive-scsi1` disk the rook `devicePathFilter` matches).
- Live terraform state: bastion `~/okd-proxmox-cli/infrastructure/terraform/
  environments/production`, module address
  `module.okd_cluster.proxmox_virtual_environment_vm.master`. okdctl
  materializes terraform write-once, so the bastion workspace does NOT pick
  up okdctl #957 by itself — Phase 1 hand-applies the hunks.
- MCO master pool rolls with maxUnavailable=1 and gates only on node
  readiness, not ceph health. Rook's PDBs (osd blocked while PGs degraded,
  1 mon max down) add backpressure, but the explicit supervised gate is
  `oc patch mcp master --type merge -p '{"spec":{"paused":true}}'`.

## Health gates (used repeatedly below)

From the bastion (`ssh okdadmin@192.168.227.20`), all must hold before
proceeding past any gate marked **GATE**:

```sh
oc -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
#   -> mon: 3 daemons, quorum (3/3); all PGs active+clean (scrubbing ok)
oc get mcp master
#   -> UPDATED True, UPDATING False, DEGRADED False
oc get pods -n openshift-etcd -l app=etcd --no-headers | grep -c Running
#   -> 3
```

Abort/brake at any point with:

```sh
oc patch mcp master --type merge -p '{"spec":{"paused":true}}'   # brake
oc patch mcp master --type merge -p '{"spec":{"paused":false}}'  # resume
```

## Live sequence

### Phase 0 — preflight (read-only)

1. Run all health gates above. **GATE.**
2. Confirm no other MCO change is queued (`oc get mc | tail`) and Flux is
   healthy (`flux get ks -A | grep -v True` empty).
3. Recent etcd backup exists (etcd-backup cronjob ran within its schedule).

### Phase 1 — attach the disks (bastion, non-disruptive, all 3 masters)

1. On the bastion, hand-apply the four hunks from okdctl #957 to the live
   workspace (module `main.tf` + `variables.tf`, production `main.tf` +
   `variables.tf` under `~/okd-proxmox-cli/infrastructure/terraform/`).
   They are small; copy them from the PR diff.
2. Validate the hunks are inert while the var defaults to 0:

   ```sh
   cd ~/okd-proxmox-cli && set -a && . ./openshitctl.env && set +a
   export PROXMOX_VE_ENDPOINT=https://192.168.227.195:8006/
   cd infrastructure/terraform/environments/production
   terraform validate && terraform plan -lock-timeout=120s
   #   -> "No changes." REQUIRED before continuing.
   ```

3. Opt in, durably (a `-var` flag would make the NEXT plain apply destroy
   the disks — the tfvars line is load-bearing forever):

   ```sh
   echo 'master_mon_disk_size_gb  = 20' >> terraform.tfvars
   ```

4. Targeted plan + apply:

   ```sh
   terraform plan -lock-timeout=120s \
     -target='module.okd_cluster.proxmox_virtual_environment_vm.master' \
     -out tfplan-mon-disk
   ```

   **GATE:** the plan must show exactly `3 to change, 0 to add, 0 to
   destroy` — three in-place updates each adding one scsi2/MON-DATA disk.
   Any replace/destroy → STOP (prevent_destroy should tripwire replaces,
   but do not rely on it).

   ```sh
   terraform apply -lock-timeout=120s tfplan-mon-disk
   ```

5. Verify hotplug on each master (from the bastion; Proxmox hotplugs scsi
   disks into running VMs):

   ```sh
   for ip in 22 23 24; do ssh core@192.168.227.$ip \
     'hostname; lsblk -d -o NAME,SIZE,SERIAL | grep MON-DATA; \
      ls /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2'; done
   ```

   If a device is missing, rescan on that node:
   `for h in /sys/class/scsi_host/host*; do echo '- - -' | sudo tee $h/scan; done`
   Last resort: one graceful reboot of that master (cordon, drain, reboot,
   uncordon) with the health gates run before and after.

### Phase 2 — format + prep (per master, non-disruptive)

For each master (.22, .23, .24), via `ssh core@<ip>` from the bastion:

```sh
DEV=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2
sudo blkid -p "$DEV" && { echo "SIGNATURE PRESENT - STOP"; } || true
#   -> must print nothing (exit 2 = blank disk). If a signature shows, STOP:
#      wrong device or leftover state; investigate before any mkfs.
sudo mkfs.xfs -L rookmon "$DEV"
sudo mount "$DEV" /mnt
sudo cp -a /var/lib/rook/rook-ceph /mnt/
sudo umount /mnt
```

Notes:

- `rook-ceph/` (config, keyring cache, logs, crash) is copied as cheap
  insurance; it is regenerable from operator secrets while quorum is alive.
- Mon dirs (`mon-d`/`mon-f`/`mon-g`) are deliberately NOT copied — the mon
  must resync a fresh store (never copy store files).
- Do all three masters. **GATE:** on every master,
  `lsblk -f | grep rookmon` shows the labeled xfs on the scsi2 disk.

### Phase 3 — merge the MC and supervise the rollout (point of no return)

1. Re-run all Phase 0 gates. **GATE.**
2. **Pause the master pool BEFORE the merge** — this removes the race where
   MCO starts draining node 1 before a post-merge pause can land:

   ```sh
   oc patch mcp master --type merge -p '{"spec":{"paused":true}}'
   oc get mcp master -o jsonpath='{.spec.paused}{"\n"}'   # must print: true
   ```

3. Merge this PR into `develop`. Flux applies the MC and MCO renders
   `99-master-rook-mon-disk`, but the paused pool does NOT roll yet.
   Optionally speed Flux up: `flux reconcile ks rook-mon-disk --with-source`.
   Confirm the render landed and the pool is holding:
   `oc get mcp master` → UPDATED False, UPDATING False, DEGRADED False,
   `paused=true`.
4. Supervised one-at-a-time loop — unpause, let MCO roll exactly one node,
   pause again, re-gate, repeat (watch `oc get nodes -w` and
   `oc get mcp master -w`):
   - **unpause** to release a single node:
     `oc patch mcp master --type merge -p '{"spec":{"paused":false}}'`
   - **re-pause the instant that node goes `SchedulingDisabled`** so MCO
     finishes only this one node and will not start the next:
     `oc patch mcp master --type merge -p '{"spec":{"paused":true}}'`
     (`maxUnavailable=1` already forbids a second concurrent node, so this
     is a stop-after-one latch, not a race brake.)
   - the node drains (rook's osd PDB may hold the drain while PGs recover —
     expected backpressure, let it work), reboots, mounts the new disk over
     `/var/lib/rook`, kubelet starts, the mon pod's `init-mon-fs` rebuilds
     an empty store, and the mon resyncs (~130 MiB, seconds).
   - post-node checks, ALL required before releasing the next node (**GATE**):

     ```sh
     ssh core@<node-ip> 'findmnt /var/lib/rook'   # xfs, label rookmon, 20G
     oc -n rook-ceph exec deploy/rook-ceph-tools -- ceph -s
     #   -> 3/3 quorum, all PGs active+clean
     oc get pods -n openshift-etcd -l app=etcd --no-headers | grep -c Running  # 3
     oc -n rook-ceph exec deploy/rook-ceph-tools -- ceph health detail
     #   -> no MON_DISK_LOW for this node's mon
     ```

   - once the gate passes, loop back to unpause for the next node. After the
     third node passes, leave the pool unpaused (`paused=false`) as its
     steady state.
5. If a mon crash-loops >10 min after its node is otherwise healthy, rook's
   mon failover replaces it with a new letter automatically — acceptable
   outcome; verify quorum returns to 3/3 and placement stays on that node.

### Phase 4 — verify, reclaim, demolish

1. Final state: `ceph health` → HEALTH_OK (archive stale crash reports with
   `ceph crash archive-all` if that's the only warning);
   `df -h /var/lib/rook` on each master shows the 20G disk a few % used;
   the `MON_DISK_LOW`-derived alerts are green in Grafana.
2. Optional root-disk reclaim, per master (the old mon store + rook dir are
   hidden under the mountpoint; the bind mount exposes them because bind
   mounts don't follow submounts):

   ```sh
   sudo mkdir -p /tmp/varroot
   sudo mount --bind /var /tmp/varroot
   ls /tmp/varroot/lib/rook/    # sanity: old mon-X + rook-ceph, NOT the new disk
   sudo rm -rf /tmp/varroot/lib/rook/*
   sudo umount /tmp/varroot && sudo rmdir /tmp/varroot
   ```

   Frees ~1 GiB/master. Only after that node's Phase 3 gates passed.
3. Demolition follow-up PR: revert `master-image-gc` and `worker-image-gc`
   kubeletconfigs. NOTE: reverting `master-image-gc` re-renders the master
   pool and triggers another rolling reboot — schedule it like any MCO
   change (the worker pool has 0 machines; that half is inert).

## Ongoing operations — new permanent failure mode

The migration adds a **hard, permanent boot dependency**: each master's
control plane now depends on its MON-DATA disk. Because the mount omits
`nofail` (deliberate — a mon must never silently regress to the root disk),
if that disk fails, detaches, or its xfs corrupts at any point in the
future:

- On the next boot, `var-lib-rook.mount` waits up to
  `x-systemd.device-timeout=30s` for `/dev/disk/by-label/rookmon`, then
  fails, and the node drops to **emergency.target**. That takes the node's
  **etcd member and mon down** until a human intervenes at the Proxmox
  console. This is by design, but it is a real, standing operational cost
  that did not exist before.
- Blast radius is capped at one master (quorum holds at 2/3 for both etcd
  and mon), so the cluster stays available — but that master will not
  self-heal across a reboot the way it did when `/var/lib/rook` lived on
  the root disk.

Recovery when a master is stuck in emergency.target on this mount:

```sh
# at the Proxmox console for the affected VM, root shell:
DEV=/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2
lsblk -f "$DEV"                 # is the disk present? does it still have the rookmon label?
# disk present but fs corrupt:
xfs_repair "$DEV" && systemctl default
# disk missing/detached: reattach it from Proxmox (or via terraform targeted
#   apply on the bastion), then: systemctl default
# disk unrecoverable: re-create it blank (terraform), boot — the
#   format-rookmon unit re-lays xfs, init-mon-fs rebuilds an empty store,
#   the mon resyncs from quorum. Same path as the original migration.
```

Detection: the smartctl_exporter alerts (#198) surface NVMe SMART
degradation on the underlying host disk before it becomes a hard failure;
`node-exporter` filesystem alerts and the mon's own liveness cover the
in-guest side. Keep the MON-DATA disks on the same healthy backing store as
the OSD disks and let SMART be the leading indicator.

## Rollback

- **Before Phase 3** (disks attached/formatted, MC unmerged): nothing
  cluster-visible has changed. To back out fully, remove the tfvars line
  and re-run the targeted plan/apply — the plan must show only the three
  scsi2 disks being removed. Leaving the disks attached is also harmless.
- **Mid-Phase 3**: pause the pool. A node stuck in emergency.target (mount
  failed: disk missing/unformatted) → Proxmox console → run the Phase 2
  format on the spot (or reattach the disk via terraform) → reboot. To
  abandon entirely: revert the MC commit on `develop`; MCO rolls the pool
  back, each node unmounts and the pre-migration store reappears on the
  root disk; a stale mon syncs the delta from quorum, or rook fails it
  over after 10 min. Quorum stays ≥2/3 throughout either path.
- **Disaster envelope**: one master at a time means worst case is 2/3 mons,
  2/3 etcd — degraded but available. If two mons are ever down
  simultaneously, STOP, unpause nothing, bring the healthy-node mon back
  first (rook mon quorum restore is the documented last resort).

## Deviations from the proposal (lead's calls)

1. **No operator scale-down, no mon-deployment deletion.** The proposal's
   manual dance is unnecessary: the mon pod's `init-mon-fs` container
   (verified on the live deployments) rebuilds an empty store and the mon
   resyncs. The MCO reboot itself is the migration.
2. **Per-master MC application isn't a thing.** The MC targets the whole
   master pool the moment Flux applies it, and MCO serially reboots all
   three. Hence: prep ALL disks first (Phases 1–2), and the PR merge is the
   explicit, gated point of no return — with `spec.paused` as the
   between-nodes supervision valve.
3. **Loud-fail mount confirmed, with its real cost stated.** No `nofail`
   means a missing/blank disk at boot drops the node to emergency.target —
   taking that master's etcd member with it until console intervention.
   Accepted: loud beats a silent regression to the root disk; the
   `format-rookmon` first-boot unit removes the "attached but blank" case,
   and the terraform only-ever-grow invariant plus the durable tfvars line
   guard the "absent" case.
4. **No rook/CephCluster change needed** — the proposal left this open;
   confirmed none is required since `dataDirHostPath` and hostpath mons are
   unchanged.
5. **20 GiB is ~150x the observed store** (132 MiB on master0), not "low
   single-digit GiB" — even more headroom than the proposal assumed.
