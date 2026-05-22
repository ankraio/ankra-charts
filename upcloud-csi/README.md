# upcloud-csi

[![Helm chart](https://img.shields.io/badge/helm-chart-blue)](../README.md) ![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue)

UpCloud CSI block-storage driver packaged as a Helm chart. Vendors the
upstream [UpCloud CSI](https://github.com/UpCloudLtd/upcloud-csi) v1.4.0
manifests (CRDs, RBAC, controller, node DaemonSet, snapshot controller,
StorageClasses, and the optional snapshot validation webhook) and exposes
them via a single `helm install`.

## TL;DR

```bash
# 1. Install the CCM first (it creates the shared UpCloud credentials Secret).
helm install upcloud-ccm ./charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# 2. Install the CSI driver — defaults reuse the CCM's Secret.
helm install upcloud-csi ./charts/upcloud-csi -n kube-system \
  --set storageClasses.defaultClass=maxiops
```

Or, if installing CSI standalone with its own credentials:

```bash
helm install upcloud-csi ./charts/upcloud-csi -n kube-system \
  --set credentials.create=true \
  --set credentials.existingSecret="" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD" \
  --set storageClasses.defaultClass=maxiops
```

## What's included

| Resource | Source | Notes |
|---|---|---|
| `CSIDriver/storage.csi.upcloud.com` | upstream | `attachRequired=true`, `podInfoOnMount=true`, `fsGroupPolicy=File`. |
| `StatefulSet/<release>-upcloud-csi-controller` | upstream | csi-provisioner + csi-attacher + csi-resizer + csi-snapshotter + csi-upcloud-plugin. Leader election on each sidecar. |
| `Deployment/<release>-upcloud-csi-snapshot-controller` | upstream | External snapshot-controller. Two replicas + PDB by default. |
| `DaemonSet/<release>-upcloud-csi-node` | upstream | csi-node-driver-registrar + csi-upcloud-plugin. Privileged plugin (required for mount syscalls). |
| `StorageClass` × 3 | upstream + extended | `upcloud-block-storage-maxiops`, `…-standard`, `…-hdd`. Per-class enable flag, default-class annotation toggle, `allowedTopologies`, `mountOptions`, per-tier `reclaimPolicy` / `volumeBindingMode`. |
| `VolumeSnapshotClass` × 1–2 | upstream + extended | Default `Delete` policy SC, optional `Retain` policy SC. |
| RBAC | upstream | ServiceAccounts, ClusterRoles, ClusterRoleBindings, leader-election Role. |
| `Job` (post-install hook) | chart | Patches the chosen UpCloud SC as cluster default and clears K3s' `local-path` default. |
| `CronJob` + scoped RBAC | chart | Opt-in periodic `VolumeSnapshot` creation with PVC/namespace label selectors and retention rotation (`snapshotCronJob.enabled`). |
| `PodMonitor` / `PrometheusRule` / Grafana dashboard ConfigMap | chart | Opt-in observability (`metrics.*` / `dashboard.*`). |
| `Pod` + `PVC` (`helm test`) | chart | End-to-end provision/mount/write test (`tests.enabled`). |
| `ValidatingWebhookConfiguration` + webhook Deployment | upstream | Opt-in (`snapshotWebhook.enabled=true`). |
| CRDs under `crds/` | upstream | `VolumeSnapshot`, `VolumeSnapshotClass`, `VolumeSnapshotContent`. Annotated `helm.sh/resource-policy: keep` (survive `helm uninstall`). |

## Requirements

| Requirement | Notes |
|---|---|
| Kubernetes | `>= 1.27` (enforced by `Chart.yaml`'s `kubeVersion`). |
| UpCloud CCM | Recommended (provides node UUID annotations the CSI driver relies on). Install [`upcloud-ccm`](../upcloud-ccm/README.md) first. |
| UpCloud API credentials | Reused from `upcloud-ccm`-created Secret by default; can be supplied directly. |
| Snapshot Controller external CRDs | Bundled in `crds/`. No external `snapshot-controller` install needed — the chart ships one. |

## Sharing credentials with `upcloud-ccm`

The chart defaults to reusing the Secret created by `helm install upcloud-ccm`:

```yaml
credentials:
  existingSecret: "upcloud-ccm-credentials"   # default
  create: false
```

If your CCM release is named differently, override the Secret name accordingly:

```bash
helm install upcloud-csi ./charts/upcloud-csi -n kube-system \
  --set credentials.existingSecret=ccm-prod-credentials \
  --set storageClasses.defaultClass=maxiops
```

## Default StorageClass

`storageClasses.defaultClass` accepts `""`, `"maxiops"`, `"standard"`, or
`"hdd"`. When set, the chart:

1. Stamps `storageclass.kubernetes.io/is-default-class: "true"` on the
   chosen StorageClass template.
2. Runs a **post-install / post-upgrade** Helm hook Job
   (`<release>-upcloud-csi-default-sc`) that:
   - Removes the default flag from K3s' built-in `local-path` SC (if
     present and `disableLocalPathDefault: true`, the default).
   - Marks the chosen UpCloud SC as the cluster default.

The hook has its own scoped RBAC (`storageclasses: get/list/patch`) that
is created `pre-install,pre-upgrade` and deleted on success.

## Air-gapped installs

Mirror every image into a private registry, then override:

```yaml
global:
  imageRegistry: harbor.internal

images:
  csiDriver:
    repository: mirror/upcloudltd/upcloud-csi
    digest: sha256:<via `crane digest`>
  provisioner:
    repository: mirror/sig-storage/csi-provisioner
    digest: sha256:...
  # …and so on for every image.

imagePullSecrets:
  - name: harbor-pull-secret
```

See [`values-examples/air-gapped.yaml`](values-examples/air-gapped.yaml).

## Snapshot validation webhook (optional)

Off by default because it requires a TLS cert. To enable:

1. Provision a TLS Secret named `snapshot-validation-secret` in the chart
   namespace (e.g. via cert-manager) with `cert.pem` / `key.pem` valid for
   the Service DNS names `snapshot-validation-service.<ns>.svc[.cluster.local]`.
2. `helm upgrade upcloud-csi ./charts/upcloud-csi --set snapshotWebhook.enabled=true`.

## Snapshots & backups

### Two VolumeSnapshotClasses

The chart can render two snapshot classes, controlled independently:

| Class | Toggle | `deletionPolicy` | Use case |
|---|---|---|---|
| `upcloud-csi-snapshotclass` | `snapshotClasses.delete.enabled` (default `true`) | `Delete` | Application-level snapshots, ephemeral test clones — UpCloud snapshot disappears when the K8s `VolumeSnapshot` is removed. |
| `upcloud-csi-snapshotclass-retain` | `snapshotClasses.retain.enabled` | `Retain` | Compliance / pre-migration archives — UpCloud snapshot survives even if the `VolumeSnapshot` object is deleted. |

Mark one as the cluster default with `snapshotClasses.<name>.isDefault: true`.

### Periodic backup CronJob

Enable the bundled `CronJob` to snapshot every UpCloud-backed PVC on a schedule:

```bash
helm upgrade upcloud-csi ./charts/upcloud-csi -n kube-system \
  -f values-examples/backup-cronjob.yaml
```

Key knobs (see [`values-examples/backup-cronjob.yaml`](values-examples/backup-cronjob.yaml)):

| Value | Default | Notes |
|---|---|---|
| `snapshotCronJob.enabled` | `false` | Master switch. |
| `snapshotCronJob.schedule` | `0 2 * * *` | Standard cron syntax. |
| `snapshotCronJob.timeZone` | `Etc/UTC` | Kubernetes 1.27+. |
| `snapshotCronJob.pvcLabelSelector` | `""` | E.g. `backup.ankra.io/enabled=true` to opt in PVCs explicitly. |
| `snapshotCronJob.namespaceLabelSelector` | `""` | Restrict to namespaces (e.g. `app.kubernetes.io/managed-by=Helm`). |
| `snapshotCronJob.snapshotClass` | `upcloud-csi-snapshotclass` | Switch to `…-retain` for archive-style backups. |
| `snapshotCronJob.retentionCount` | `7` | Keep N most recent snapshots per PVC. `0` disables rotation. |
| `snapshotCronJob.dryRun` | `false` | When `true`, only log what would happen. |

The CronJob's RBAC is locked down to: `pvc/namespace get,list` and
`volumesnapshot get,list,create,delete`.

### Restoring from a snapshot

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-restored-pvc
  namespace: default
spec:
  storageClassName: upcloud-block-storage-maxiops
  dataSource:
    name: <existing-volumesnapshot-name>
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 10Gi
```

## Multi-zone clusters

UpCloud block storage is **zone-bound** — a `fi-hel1` volume cannot be
attached to a `fi-hel2` VM. For clusters that span multiple zones, switch
to `WaitForFirstConsumer` + `allowedTopologies`:

```bash
helm upgrade upcloud-csi ./charts/upcloud-csi -n kube-system \
  -f values-examples/multi-zone.yaml
```

`values-examples/multi-zone.yaml` pins the `maxiops` SC to `fi-hel1` and the
`standard` SC to `fi-hel2`. The scheduler then places pods next to a
provisionable volume rather than failing the bind.

## Observability

| Resource | Toggle | Purpose |
|---|---|---|
| `PodMonitor` | `metrics.podMonitor.enabled` | Prometheus Operator scrapes the controller + node CSI plugin metrics. |
| `PrometheusRule` | `metrics.prometheusRule.enabled` | Recommended alerts (see below). |
| Grafana dashboard | `dashboard.enabled` | ConfigMap auto-discovered by the kube-prometheus-stack Grafana sidecar. |

### Bundled alerts

| Alert | Severity | Trigger |
|---|---|---|
| `UpCloudCSIControllerDown` | critical | StatefulSet Ready < expected replicas, sustained 5m. |
| `UpCloudCSINodeMissing` | warning | DaemonSet pod absent on one or more nodes for 10m. |
| `UpCloudCSIPVCPending` | warning | PVC bound against an `upcloud-block-storage-*` SC stays Pending >15m. |
| `UpCloudCSISnapshotControllerDown` | warning | Snapshot controller Deployment has 0 Available replicas for 10m. |
| `UpCloudCSIVolumeNearFull` | warning | `used/capacity > 0.85` (configurable) for >15m. |
| `UpCloudCSIPodCrashLooping` | critical | >3 restarts in 15m. |

See [`values-examples/observability.yaml`](values-examples/observability.yaml)
for a full kube-prometheus-stack-compatible overlay (alert label `release:
kube-prometheus-stack`, dashboard sidecar label `grafana_dashboard: "1"`).

## Troubleshooting

| Symptom | Cause | Resolution |
|---|---|---|
| PVC stuck `Pending` | UpCloud API quota / region mismatch / controller down | `kubectl describe pvc …` and `kubectl logs -n kube-system <controller-pod> -c csi-upcloud-plugin`. |
| Pod stuck `ContainerCreating: MountVolume.MountDevice failed` | Node DaemonSet not running on that node, or kubelet root mismatch | Verify `kubectl get pods -l app.kubernetes.io/component=node` covers every node; check `node.kubeletDir`. |
| `helm test upcloud-csi` fails | Provisioner/attacher cannot reach UpCloud (credentials/quota) | Inspect the test pod events; check Secret data. |
| Snapshots fail to create | Snapshot controller down / `VolumeSnapshotClass` missing | Verify CRDs installed and the `snapshot-controller` Deployment is Ready. |
| VolumeSnapshot stays `ReadyToUse=false` | UpCloud API rate-limit on snapshot create | Reduce concurrent snapshots in the CronJob, or wait — the snapshot eventually completes. |

## Helm test

After install, run:

```bash
helm test upcloud-csi -n kube-system
```

The test creates a small PVC (default `10Gi`) against the maxiops SC,
mounts it in a busybox pod, writes 4MiB of random data, reads it back, and
deletes the test resources. Set `tests.enabled=false` to skip rendering
the test pod entirely.

## Upgrade story

### Bumping the bundled UpCloud CSI version

The chart vendors a pinned upstream snapshot. To bump:

```bash
# Local
./charts/scripts/sync-upstream.sh csi v1.5.0
helm lint charts/upcloud-csi
git diff charts/upcloud-csi/
```

The daily `.github/workflows/charts-upcloud-sync.yml` workflow does this
automatically and opens a PR.

### Upgrading the chart

```bash
helm upgrade upcloud-csi ./charts/upcloud-csi -n kube-system -f my-values.yaml
```

CRDs under `crds/` are installed only on the first `helm install` and never
deleted (per Helm 3 semantics + `helm.sh/resource-policy: keep`). To pick
up upstream CRD changes, run:

```bash
kubectl replace -f charts/upcloud-csi/crds/
```

## Uninstall

```bash
helm uninstall upcloud-csi -n kube-system
```

The CRDs and any existing `VolumeSnapshot` / `VolumeSnapshotContent`
resources will **survive uninstall** by design. To remove them too:

```bash
kubectl delete crd volumesnapshots.snapshot.storage.k8s.io \
                  volumesnapshotclasses.snapshot.storage.k8s.io \
                  volumesnapshotcontents.snapshot.storage.k8s.io
```

## Configuration reference

A full table of values lives in [`values.yaml`](values.yaml). Key knobs:

<!-- helm-docs-values-table-start -->
| Key | Default | Description |
|---|---|---|
| `credentials.existingSecret` | `"upcloud-ccm-credentials"` | Reuse the CCM-created Secret by default. |
| `credentials.create` | `false` | Render a Secret from `username`/`password`. |
| `storageClasses.defaultClass` | `""` | One of `""`, `maxiops`, `standard`, `hdd`. |
| `storageClasses.disableLocalPathDefault` | `true` | Hook also clears the K3s local-path default. |
| `storageClasses.allowedTopologies` | `[]` | Chart-wide topology constraint; per-tier overrides allowed. |
| `storageClasses.maxiops.enabled` | `true` | Render the maxiops SC. |
| `storageClasses.maxiops.mountOptions` | `[]` | Mount options stamped on every PV. |
| `storageClasses.standard.enabled` | `true` | Render the standard SC. |
| `storageClasses.hdd.enabled` | `true` | Render the hdd SC. |
| `snapshotClasses.delete.enabled` | `true` | `deletionPolicy: Delete` snapshot class. |
| `snapshotClasses.retain.enabled` | `false` | `deletionPolicy: Retain` snapshot class. |
| `snapshotCronJob.enabled` | `false` | Periodic VolumeSnapshot CronJob. |
| `snapshotCronJob.schedule` | `0 2 * * *` | Cron schedule. |
| `snapshotCronJob.retentionCount` | `7` | Snapshots kept per PVC. |
| `controller.replicaCount` | `1` | Bump to 2+ for HA (leader election preserved). |
| `node.kubeletDir` | `/var/lib/kubelet` | Override for non-default kubelet roots. |
| `snapshotController.enabled` | `true` | Bundle the external snapshot-controller. |
| `snapshotWebhook.enabled` | `false` | Opt-in validation webhook (requires TLS cert). |
| `metrics.podMonitor.enabled` | `false` | Render a Prometheus PodMonitor. |
| `metrics.prometheusRule.enabled` | `false` | Render the recommended alert rules. |
| `dashboard.enabled` | `false` | Grafana dashboard ConfigMap (sidecar discovery). |
| `tests.enabled` | `true` | `helm test` provisions a PVC end-to-end. |
| `networkPolicy.enabled` | `false` | Opt-in NetworkPolicy. |
| `global.imageRegistry` | `""` | Override every image registry (air-gapped). |
| `hostAliases` / `dnsConfig` / `runtimeClassName` / `schedulerName` | `[]` / `{}` / `""` / `""` | Pod-spec passthroughs (apply to controller/node/snapshot-controller pods). |
| `fsGroupChangePolicy` | `OnRootMismatch` | Skip fsGroup chowns on large PVs. |
| `terminationMessagePolicy` | `FallbackToLogsOnError` | Surface logs on non-zero exits. |
<!-- helm-docs-values-table-end -->

## See also

- [upcloud-ccm](../upcloud-ccm/README.md) — install this first for shared credentials.
- Upstream: <https://github.com/UpCloudLtd/upcloud-csi>.
