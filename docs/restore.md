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

# 4. Once LatestImage is populated, grab the restored PVC name
oc -n $NS get replicationdestination <name> \
  -o jsonpath='{.status.latestImage.name}'

# 5. Point the app at the restored PVC (update the HelmRelease's
#    existingClaim or manually bind) and roll the pod
```

Volsync's restore flow is documented upstream at
https://volsync.readthedocs.io/en/stable/usage/restic/index.html#restoring-a-backup.

## Templates

Fields that vary per app: `metadata.name`, `spec.restic.repository`,
`spec.restic.destinationPVC` (the name of the new PVC to create), and
the volsync-mover SA namespace. All other fields match the
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
    destinationPVC: sonarr-config-restored
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
`plex`, `overseerr`. `repository: volsync-restic-<app>`,
`destinationPVC: <app>-config-restored`. Plex uses `cacheCapacity: 2Gi`.

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
    destinationPVC: grafana-pvc-restored
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
    destinationPVC: image-registry-storage-restored
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

- _(none yet)_
