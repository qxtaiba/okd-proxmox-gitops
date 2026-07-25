# Proposal: dedicated mon disk per master (retire MON_DISK_LOW structurally)

Status: proposal, not applied. No live changes in this PR.

## Problem

Ceph reports `MON_DISK_LOW` recurrently (mon.f at 18% avail, mon.g at 21% as
of 2026-07-26). The mon stores live under `/var/lib/rook` on each master's
root disk, which they share with the OS image store, container layers, logs,
and everything else kubelet does. Two commits have already lowered kubelet
image-GC thresholds to 70% to keep mon stores breathing — that is
symptom-tuning, and two commits deep is where a stopgap starts becoming
load-bearing. The mon store does not need much space; it needs space that
*nothing else can eat*.

## Proposal

Give each master a small dedicated virtual disk and mount it at
`/var/lib/rook`.

### 1. Disk (Terraform / okdctl, per master VM)

- Add a third SCSI disk per master in the Proxmox VM definition:
  `drive-scsi2`, 20 GiB (mon stores run low single-digit GiB; 20 GiB absorbs
  compaction spikes and recovery growth with room to spare).
- The device path is deterministic the same way the OSD disk already is:
  `/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2`
  (SCSI bus assignment is stable per Terraform disk-block order — same
  mechanism the rook `devicePathFilter` relies on for `drive-scsi1`).
- Live Terraform state is on the bastion; this pairs naturally with the
  okdctl node-resize/lifecycle work, which exists for exactly this kind of
  change.

### 2. Filesystem + mount (MachineConfig)

Ignition's `storage.disks`/`filesystems` sections only run on first boot, so
for the three *existing* masters the format step is manual (one-time, per
master):

    mkfs.xfs -L rookmon /dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_drive-scsi2

Delivery of the mount is declarative: a `99-master-rook-mon-disk` MC with a
systemd mount unit for `/var/lib/rook` (`What=/dev/disk/by-label/rookmon`,
`Before=kubelet.service`, `nofail` omitted deliberately — if the disk is
gone we want the mon pod failing loudly, not writing to the root disk
behind the mount point). New masters provisioned later get the full
disks/filesystems treatment in ignition via okdctl instead.

### 3. Migration (one master at a time, quorum-safe)

Do not copy mon stores. Mons rebuild their store from quorum peers, so the
clean sequence per master is:

1. Verify `ceph status`: 3/3 mons in quorum, all PGs `active+clean`.
2. Scale down the rook operator; delete the local mon deployment (e.g.
   `mon.d`) so the node's mon is down — quorum holds at 2/3.
3. Mount the new disk at `/var/lib/rook` (apply the MC / mount by hand for
   the pilot node). Preserve `/var/lib/rook/rook-ceph` cluster metadata by
   copying it onto the new disk first — it is tiny; only the mon store is
   heavyweight.
4. Scale the operator back up; it recreates the mon, which syncs a fresh
   store onto the empty disk.
5. Wait for 3/3 quorum and `active+clean`, then move to the next master.

Total exposure per master is one mon down for minutes — the same exposure
every MCO reboot already exercises weekly.

### Rejected alternatives

- **Keep tuning kubelet GC**: whack-a-mole; the mon still shares a device
  with an unbounded consumer, and the 70% threshold already trades image
  cache hit-rate for mon headroom.
- **Enlarge the root disks** (okdctl node-resize): buys time, not isolation;
  MON_DISK_LOW returns the day the image store grows into the new space.
  Acceptable fallback if adding disks proves annoying, but it re-arms the
  same alarm.
- **Move mons to PVCs (rook `volumeClaimTemplate`)**: mons on ceph-backed
  storage is a circular dependency; mons on `local-path` PVs is the same
  disk with extra steps. A raw dedicated disk is simpler and honest.

## Definition of done

- `MON_DISK_LOW` cannot recur without the mon store itself growing 10x.
- The two image-GC kubeletconfigs (`master-image-gc`, `worker-image-gc`)
  get reverted — the stopgap is demolished the same week the fix lands,
  per the standing rule that every migration includes its demolition step.
