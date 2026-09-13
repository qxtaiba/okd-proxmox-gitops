# grappleberry alerting design

Date: 2026-09-13
Status: implemented on branch `grappleberry-health-fixes`

## Problem

The cluster generates alerts and delivers none of them.
`AlertmanagerReceiversNotConfigured` had been firing since 2026-06-03: the OKD
default `alertmanager-main` defines routes for `Watchdog`, `Critical` and
`Default`, and every one of those receivers is empty, so alerts are evaluated,
grouped, inhibited — and discarded.

Three further gaps were found while verifying what coverage actually existed.

### What already worked

112 alerting rules evaluate in **Thanos Ruler** (not the UWM Prometheus —
OpenShift routes user-defined *alerting* rules there):

| Source | Rules |
|---|---|
| `rook-ceph/prometheus-ceph-rules` | 89 |
| `kube-system/kube-vip-rules` | 7 |
| `observability/smartctl-exporter-rules` | 6 |
| `cert-manager/cert-manager-rules` | 4 |
| `external-dns/external-dns-rules` | 3 |
| `flux-system/flux-instance-rules` | 3 |

Plus 245 platform rules in `prometheus-k8s`. UWM → Alertmanager delivery works:
`CephHealthWarning` was live in Alertmanager at time of writing.

### Gap 1 — Flux alerting could never fire

All three Flux rules matched `gotk_reconcile_condition`, which the Flux
controllers no longer export (**0 series**). The rules were syntactically
valid, had sensible `for:` clauses, and were permanently green. A broken
HelmRelease would have produced silence.

The live equivalent is `flux_resource_info` from flux-operator (108 series;
labels `kind`, `name`, `exported_namespace`, `ready`, `suspended`, `reason`).
Note `exported_namespace` — `namespace` is taken by the scrape target.

### Gap 2 — VolSync had no metrics at all

`volsync-metrics` scrape target was **down, 401 Unauthorized**. The chart
fronts `/metrics` with kube-rbac-proxy on :8443 but its own ServiceMonitor
ships no credentials. Nightly backups were effectively unmonitored.

### Gap 3 — nothing observes custom resource status

No `rook_*` and no `kube_customresource_*` metrics exist. On 2026-09-13 rook
sat in `Progressing`/"Configuring Ceph OSDs" for hours, unable to update any
OSD, while every `ceph_*` metric reported a healthy cluster and the
`rook-ceph-cluster` HelmRelease reported Ready. The failure was structurally
invisible.

## Constraints discovered

1. **`enforcedNamespaceLabel: namespace`** on both the UWM Prometheus and
   Thanos Ruler. Every user-defined rule gets a `namespace=` filter injected,
   so user rules cannot query node-exporter metrics (no `namespace` label). A
   custom node-disk rule would match nothing and look healthy — do not add
   one. Platform `NodeFilesystemAlmostOutOfSpace` already covers disk and now
   reaches Telegram.
2. **Alertmanager 0.29.0 has no `chat_id_file`.** `bot_token_file` and
   `url_file` exist; `chat_id_file` does not. Verified by `amtool`. The
   file-indirection trick therefore cannot keep every value out of Git.
3. **Alertmanager cannot read a Kubernetes Secret from its config**, so the
   config itself must be rendered with the values already in it.
4. **CMO seeds `alertmanager-main`.** Taking it over needs
   `creationPolicy: Merge`, never `Owner` — `Owner` would delete the Secret if
   the ExternalSecret is removed, leaving Alertmanager with no config.

## Design

### Delivery — Telegram

`ExternalSecret` `alertmanager-main` renders the whole `alertmanager.yaml`,
injecting `bot-token`, `chat-id` and `healthchecks-url` from 1Password item
`alertmanager-telegram` in the `Kubernetes` vault. Alertmanager's native
`telegram_configs` is used; no gateway workload, nothing to keep alive.

Templating is safe only because the config contains no Go template syntax of
its own. A custom Telegram `message:` must escape braces as `{{ ` + "`{{`" + ` }}`.

Signal was considered and rejected as the primary channel: Alertmanager has no
native Signal receiver, `signal-cli-rest-api` needs a dedicated phone number
and periodic re-registration, and — decisively — it would run *on the cluster
it monitors*, so it cannot report the one failure that matters most.

### Routing

| Match | Receiver | Interval |
|---|---|---|
| `alertname=Watchdog` | Watchdog (healthchecks.io) | repeat 5m |
| `InsightsDisabled\|UpdateAvailable\|KubeCPUOvercommit\|SystemMemoryExceedsReservation` | Drop | — |
| `severity=info` | Drop | — |
| `severity=critical` | Critical (Telegram) | repeat 1h |
| everything else | Default (Telegram) | repeat 12h |

The two OKD inhibit rules are kept: a firing critical mutes the matching
warning/info for the same alert, so one incident is one message.

Verified with `amtool config routes test` — all nine representative alerts
route as intended.

### Dead-man's switch

`Watchdog` fires continuously by design. Routing it to a healthchecks.io ping
URL every 5m, against a 10m period + 5m grace, means a dead cluster, dead
Prometheus or dead Alertmanager is detected in ~15 minutes. Nothing running
inside the cluster can report that the cluster is gone; this is the only
coverage for total failure.

### Custom resource status — `cr-state-metrics`

A second kube-state-metrics in `observability`, started with `--resources=`
(every built-in collector off, so no `kube_*` series are duplicated) and
`--custom-resource-state-only`, exporting `CephCluster` and `CephFilesystem`
`.status.phase` as StateSet gauges. Its metrics carry the CR's own namespace
label, so user rules can match them under `enforcedNamespaceLabel`.

New rules: `CephClusterNotReady` (30m, critical), `CephFilesystemNotReady`
(30m, critical), `CRStateMetricsAbsent` (30m, warning).

`FluxMetricsAbsent` and `CRStateMetricsAbsent` exist because a dead exporter
otherwise looks exactly like a healthy cluster — the same silent-green failure
that hid Gap 1 for months.

## Validation performed

- `kustomize build` on all 13 changed/new paths
- `amtool check-config` on the rendered config: SUCCESS, 4 receivers
- `amtool config routes test` on 9 representative alerts
- Every new PromQL expression executed against live Prometheus, each with an
  inverted control query proving the label selectors match real series

## Follow-ups not in this change

- 1Password item `grappleberry-xyz-tls` is at **version 34543**; PushSecret
  re-PUTs unconditionally on every refresh and 1Password now rejects updates
  with HTTP 400. Needs the item recreated and the push made conditional.
- MetalLB metrics are off: the chart hardcodes `bearerTokenFile`, which UWM
  rejects. Restoring them means hand-written ServiceMonitors using
  `authorization.credentials`.
