# Volsync restore templates

Untested backups are not backups. These templates turn a Volsync restic
repository into a new PVC by creating a `ReplicationDestination`. Apply
them in the target namespace, let them reach `LatestImage`, then point
your app at the restored PVC.

## When to use

- **Disaster recovery**: original PVC is gone, app is down.
- **Drill**: quarterly verification that backups actually restore.
- **Rollback**: restore an old snapshot to a throwaway PVC and diff.

## Prerequisites

The restic repository secret (`volsync-restic-<app>`) must exist in the
target namespace. It's created by the ExternalSecrets under
`kubernetes/infrastructure/configs/volsync-config/app/external-secret.yaml`
on the initial apply, and survives because the Secret is what the
ExternalSecret populates, not what it owns.

## Operations

```bash
# 1. Choose a target namespace
NS=default

# 2. Apply the template (paste from below) as `replicationdestination.yaml`
oc -n $NS apply -f replicationdestination.yaml

# 3. Watch the restore
oc -n $NS get replicationdestination -w

# 4. Once LatestImage is populated, grab the restored VolumeSnapshot name
SNAP=$(oc -n $NS get replicationdestination <name> \
  -o jsonpath='{.status.latestImage.name}')

# 5. Create a PVC from that snapshot (same size/class as the original),
#    scale the app to 0, point it at the new PVC (or delete the old PVC
#    and recreate it under the original name with this dataSource), and
#    scale back up.
#      dataSource: {apiGroup: snapshot.storage.k8s.io,
#                   kind: VolumeSnapshot, name: $SNAP}
```

Do not set `destinationPVC` unless that PVC already exists: it means
"restore into this existing claim", and with a missing claim the restore
waits forever. The templates below let Volsync create the volume from
`capacity`/`storageClassName`/`accessModes` and hand back a snapshot.

Volsync's restore flow is documented upstream at
https://volsync.readthedocs.io/en/stable/usage/restic/index.html#restoring-a-backup.

## Fresh cluster (full rebuild)

Every backed-up PVC declares `dataSourceRef` to a `<pvc>-bootstrap`
ReplicationDestination (see each app's `pvc.yaml` / `volsync.yaml`). On a new
cluster the PVC stays Pending until Volsync restores the newest snapshot from
the NAS, so apps come up on their old data with no manual step. Covered:
overseerr, plex, prowlarr, qbittorrent, radarr, sabnzbd, sonarr, and the
image registry. Grafana is not (its PVC is created by grafana-operator);
dashboards are in git, so only users/preferences are lost — restore it
manually with the template below if they matter.

What is NOT in git or the restic backups, and must be carried across:

1. **1Password Connect bootstrap**: `external-secrets/onepassword-connect-credentials`
   (the `1password-credentials.json`) and `external-secrets/onepassword-connect-token`.
   Every other secret (25 ExternalSecrets, including the restic passwords)
   is pulled from 1Password through these two. Keep them in 1Password itself.
2. **Flux deploy key**: or bootstrap Flux with a new key.

Order:

1. Install the cluster; create the two 1Password Connect secrets by hand.
2. `flux bootstrap` against `develop`. External Secrets populates the restic
   secrets, Rook-Ceph and Volsync come up, PVCs restore themselves, apps
   start. Expect app pods to sit in Pending/ContainerCreating until their
   PVC binds — that is the restore running.
3. **Terraform state before tofu-controller applies.** The tofu-state bucket
   comes from an ObjectBucketClaim with a generated name, so the new bucket
   is empty. Suspend the tofu Terraform objects, copy the newest backup in,
   then resume — otherwise the first apply fails on "resource already
   exists":
   ```bash
   # newest dir under nas:/volume1/backups/tofu-state/<YYYYMMDD-HHMMSS>/
   # run from a pod with that NFS mount and the tofu-state-bucket env:
   aws s3 cp --recursive --endpoint-url "http://${BUCKET_HOST}:${BUCKET_PORT}" \
     /backup/<YYYYMMDD-HHMMSS>/ "s3://${BUCKET_NAME}/"
   ```
4. `media` is a static NFS PV (`Retain`) on the NAS and re-binds on its own.
   `downloads` (scratch) starts empty by design.

Not recoverable, by design: Prometheus/Loki/Alertmanager history, etcd
(a backup only restores into the same cluster).

## Templates

Fields that vary per app: `metadata.name`, `spec.restic.repository`,
`spec.restic.capacity` / `storageClassName` / `accessModes` (copied from
the app's `pvc.yaml`), and the volsync-mover SA namespace. All other fields match the
`volsync-restic-defaults` Kustomize component under
`kubernetes/components/volsync-restic-defaults/`.

### Sonarr config (default namespace)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: sonarr-config-restore
  namespace: default
spec:
  trigger:
    manual: restore-once
  restic:
    copyMethod: Snapshot
    volumeSnapshotClassName: csi-ceph-blockpool
    repository: volsync-restic-sonarr
    capacity: 5Gi
    storageClassName: ceph-block
    accessModes: [ReadWriteOnce]
    moverServiceAccount: volsync-mover
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
    cacheStorageClassName: ceph-block
    cacheAccessModes: [ReadWriteOnce]
    cacheCapacity: 1Gi
    moverVolumes:
      - mountPath: restic-repo
        volumeSource:
          nfs:
            server: nas.grappleberry.xyz
            path: /volume1/backups/volsync
```

### Other apps

Replace `sonarr` with any of: `radarr`, `prowlarr`, `sabnzbd`, `qbittorrent`,
`plex`, `overseerr`. `repository: volsync-restic-<app>`, and `capacity` from
the app's `pvc.yaml` (plex 50Gi, radarr/sonarr 5Gi, the rest 1Gi). Plex uses
`cacheCapacity: 2Gi`.

### Grafana (observability namespace)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: grafana-pvc-restore
  namespace: observability
spec:
  trigger:
    manual: restore-once
  restic:
    copyMethod: Snapshot
    volumeSnapshotClassName: csi-ceph-blockpool
    repository: volsync-restic-grafana
    capacity: 5Gi
    storageClassName: ceph-block
    accessModes: [ReadWriteOnce]
    moverServiceAccount: volsync-mover
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
    cacheStorageClassName: ceph-block
    cacheAccessModes: [ReadWriteOnce]
    cacheCapacity: 1Gi
    moverVolumes:
      - mountPath: restic-repo
        volumeSource:
          nfs:
            server: nas.grappleberry.xyz
            path: /volume1/backups/volsync
```

### OpenShift image registry (openshift-image-registry namespace)

```yaml
apiVersion: volsync.backube/v1alpha1
kind: ReplicationDestination
metadata:
  name: image-registry-restore
  namespace: openshift-image-registry
spec:
  trigger:
    manual: restore-once
  restic:
    copyMethod: Snapshot
    volumeSnapshotClassName: csi-ceph-filesystem
    repository: volsync-restic-image-registry
    capacity: 100Gi
    storageClassName: ceph-filesystem
    accessModes: [ReadWriteMany]
    moverServiceAccount: volsync-mover
    moverSecurityContext:
      runAsUser: 1000
      runAsGroup: 1000
      fsGroup: 1000
    cacheStorageClassName: ceph-block
    cacheAccessModes: [ReadWriteOnce]
    cacheCapacity: 2Gi
    moverVolumes:
      - mountPath: restic-repo
        volumeSource:
          nfs:
            server: nas.grappleberry.xyz
            path: /volume1/backups/volsync
```

## Fire drill cadence

Not currently scheduled. When you run one, restore the smallest PVC
(probably `recyclarr` or `overseerr-config`) into a throwaway namespace
and verify the data. Record the date in this file.

### Drill log

- 2026-10-04: overseerr-config, snapshot `0614ddd7` (taken 18:06Z the same
  day) restored in 2s into a scratch snapshot; db.sqlite3 / -shm / -wal
  byte-identical in size to live, ownership 1000:1000 intact. Found and
  fixed the `destinationPVC` template bug above. Same day: verified the
  restore-on-create path (PVC with `dataSourceRef` to a ReplicationDestination
  binds only after the restore, with the restored data).
