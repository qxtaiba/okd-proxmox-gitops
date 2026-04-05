# Terraform state migration: in-cluster Secret → Ceph RGW S3

## Current state

Each `Terraform` CR in `devopsarr/app/terraform-*.yaml` stores its
`tfstate` in a Kubernetes Secret in the `default` namespace by default
(tofu-controller behavior). The `default` namespace is not covered by
Volsync, so losing the namespace or accidentally deleting the Secrets
means losing Terraform state — which means re-entering all indexer
config, quality profiles, custom formats manually.

The footgun for `destroyResourcesOnDeletion: true` is already fixed:
all three CRs now set it to `false`, so deleting a Terraform CR no
longer tears down the managed *arr resources.

## Target state

Terraform state moves to a dedicated Ceph RGW bucket provisioned via
`tofu-state-bucket.yaml` (OBC). The bucket survives cluster rebuilds
as long as Ceph itself survives, and it can be volsync-backed later
if desired.

## Step-by-step migration (manual, run once)

1. **Verify the bucket is provisioned**:

   ```bash
   oc -n default get obc tofu-state-bucket
   oc -n default get cm tofu-state-bucket -o jsonpath='{.data}'
   oc -n default get secret tofu-state-bucket -o jsonpath='{.data}' | base64 -d
   ```

   You should see `BUCKET_NAME`, `BUCKET_HOST`, `BUCKET_PORT` in the
   ConfigMap and `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` in the
   Secret.

2. **For each Terraform CR** (prowlarr, sonarr, radarr), add a
   `backendConfig` block. Example for prowlarr:

   ```yaml
   spec:
     backendConfig:
       customConfiguration: |
         terraform {
           backend "s3" {
             bucket                      = "<BUCKET_NAME from OBC>"
             key                         = "devopsarr-prowlarr.tfstate"
             endpoint                    = "http://rook-ceph-rgw-okd-ceph-objectstore.rook-ceph.svc.cluster.local"
             force_path_style            = true
             region                      = "us-east-1"
             skip_credentials_validation = true
             skip_metadata_api_check     = true
             skip_region_validation      = true
             skip_requesting_account_id  = true
           }
         }
     backendConfigsFrom:
       - kind: Secret
         name: tofu-state-bucket
         keys:
           - AWS_ACCESS_KEY_ID
           - AWS_SECRET_ACCESS_KEY
   ```

3. **Export existing state from the in-cluster Secret** before
   applying the backend change (otherwise tofu-controller will try to
   reconcile from empty state and fail on "resource already exists"):

   ```bash
   # Find the state secret
   oc -n default get secrets -l tfstate.infra.contrib.fluxcd.io/name=devopsarr-prowlarr
   # Extract tfstate
   oc -n default get secret tfstate-default-devopsarr-prowlarr -o jsonpath='{.data.tfstate}' | base64 -d > prowlarr.tfstate.bak
   ```

4. **Manually seed the S3 bucket with the extracted state** using an
   ephemeral pod with awscli or the `mc` mirror client, targeting the
   new bucket path. Object key: `devopsarr-prowlarr.tfstate`.

5. **Commit the backend config change** to git. Flux will reconcile
   and tofu-controller will re-init with the new backend. It should
   find the seeded state and match resources without recreating them.

6. **Verify** no unexpected changes:

   ```bash
   oc -n default get terraform devopsarr-prowlarr -o jsonpath='{.status}'
   ```

7. **Repeat** for devopsarr-sonarr and devopsarr-radarr.

8. **Clean up** the old in-cluster state Secrets (optional, they are
   harmless but stale):

   ```bash
   oc -n default delete secret tfstate-default-devopsarr-prowlarr
   # ... etc
   ```

## Rollback

If the migration fails mid-step, revert the `backendConfig` block in
git, re-apply from git, and tofu-controller will return to using the
in-cluster Secret state. The Secret is never deleted during migration
so rollback is safe as long as you don't delete it prematurely.
