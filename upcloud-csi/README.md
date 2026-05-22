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
helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# 2. Install the CSI driver — defaults reuse the CCM's Secret.
helm install upcloud-csi ./upcloud-charts/upcloud-csi -n kube-system \
  --set storageClasses.defaultClass=maxiops
```

Or, if installing CSI standalone with its own credentials:

```bash
helm install upcloud-csi ./upcloud-charts/upcloud-csi -n kube-system \
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
| `StorageClass` × 3 | upstream | `upcloud-block-storage-maxiops`, `…-standard`, `…-hdd`. Per-class enable flag + default-class annotation toggle. |
| `VolumeSnapshotClass/upcloud-csi-snapshotclass` | upstream | `deletionPolicy: Delete`. |
| RBAC | upstream | ServiceAccounts, ClusterRoles, ClusterRoleBindings, leader-election Role. |
| `Job` (post-install hook) | new | Patches the chosen UpCloud SC as cluster default and clears K3s' `local-path` default. |
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
helm install upcloud-csi ./upcloud-charts/upcloud-csi -n kube-system \
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
2. `helm upgrade upcloud-csi ./upcloud-charts/upcloud-csi --set snapshotWebhook.enabled=true`.

## Upgrade story

### Bumping the bundled UpCloud CSI version

The chart vendors a pinned upstream snapshot. To bump:

```bash
# Local
./upcloud-charts/scripts/sync-upstream.sh csi v1.5.0
helm lint upcloud-charts/upcloud-csi
git diff upcloud-charts/upcloud-csi/
```

The daily `.github/workflows/upcloud-charts-sync.yml` workflow does this
automatically and opens a PR.

### Upgrading the chart

```bash
helm upgrade upcloud-csi ./upcloud-charts/upcloud-csi -n kube-system -f my-values.yaml
```

CRDs under `crds/` are installed only on the first `helm install` and never
deleted (per Helm 3 semantics + `helm.sh/resource-policy: keep`). To pick
up upstream CRD changes, run:

```bash
kubectl replace -f upcloud-charts/upcloud-csi/crds/
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
| `storageClasses.maxiops.enabled` | `true` | Render the maxiops SC. |
| `storageClasses.standard.enabled` | `true` | Render the standard SC. |
| `storageClasses.hdd.enabled` | `true` | Render the hdd SC. |
| `controller.replicaCount` | `1` | Bump to 2+ for HA (leader election preserved). |
| `node.kubeletDir` | `/var/lib/kubelet` | Override for non-default kubelet roots. |
| `snapshotController.enabled` | `true` | Bundle the external snapshot-controller. |
| `snapshotWebhook.enabled` | `false` | Opt-in validation webhook (requires TLS cert). |
| `networkPolicy.enabled` | `false` | Opt-in NetworkPolicy. |
| `global.imageRegistry` | `""` | Override every image registry (air-gapped). |
<!-- helm-docs-values-table-end -->

## See also

- [upcloud-ccm](../upcloud-ccm/README.md) — install this first for shared credentials.
- Upstream: <https://github.com/UpCloudLtd/upcloud-csi>.
