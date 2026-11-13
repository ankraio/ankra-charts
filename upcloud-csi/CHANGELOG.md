# upcloud-csi changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

The chart's `appVersion` tracks upstream
[`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi)
releases. Daily sync via
[`charts-upcloud-sync.yml`](../../.github/workflows/charts-upcloud-sync.yml)
auto-bumps these.

## [Unreleased]

## [0.5.0] - 2026-11-13

### Security

- **Current kubernetes-csi sidecars.** The chart still defaulted to the 2022
  sidecars UpCloud's own manifests ship, which scan with dozens of critical
  and high CVEs, all fixed upstream:

  | Image | 0.4.x | 0.5.0 |
  | -- | -- | -- |
  | `csi-provisioner` | v3.1.0 | v6.4.0 |
  | `csi-attacher` | v3.4.0 | v4.13.0 |
  | `csi-resizer` | v1.4.0 | v2.3.0 |
  | `csi-snapshotter` | v4.2.1 | v8.7.0 |
  | `snapshot-controller` | v4.2.1 | v8.7.0 |
  | `csi-node-driver-registrar` | v2.5.0 | v2.18.0 |
  | `snapshot-validation-webhook` (opt-in) | v4.2.1 | v8.1.1 |
  | `upcloud-csi` driver | v1.4.0 | v1.5.1 (by digest) |
  | `alpine/k8s` (hook Job, snapshot CronJob) | 1.31.13 | 1.35.10 |

### Changed

- **Kubernetes 1.34 or newer** (`kubeVersion: ">=1.34.0-0"`), the minimum
  external-provisioner v6 supports.
- **Topology is on.** csi-provisioner v3 ran with its `Topology` feature gate
  off; from v5 it follows the driver, and the UpCloud driver advertises
  `VOLUME_ACCESSIBILITY_CONSTRAINTS` with the key `region` (set to the zone).
  New PersistentVolumes get a `region In [<zone>]` node affinity, so a pod is
  never scheduled where its volume cannot attach. Existing PersistentVolumes
  are untouched. Two consequences:
  - A StorageClass `allowedTopologies` must use the `region` key. A class
    keyed on `topology.kubernetes.io/zone` with `WaitForFirstConsumer` fails
    every new claim with `topology ... from selected node ... is not in
    requisite`. `values-examples/multi-zone.yaml` now uses `region`.
  - The driver creates volumes only in its controller's zone and rejects any
    other zone it is asked for, so a cluster whose CSI nodes span zones gets
    `ResourceExhausted` on new claims. Single-zone clusters are unaffected.
  `controller.sidecarExtraArgs.provisioner: ["--feature-gates=Topology=false"]`
  restores the old behaviour.
- **Snapshot CRDs from external-snapshotter v8.7.0**, which validate with CEL
  rules instead of the webhook and add `sourceVolumeMode`. Helm installs
  `crds/` only on a first install, so an upgrade keeps the CRDs a cluster
  already has. snapshot-controller v8 runs on the v4.2-era CRDs (production
  UpCloud clusters have run v8.6 on them since chart 0.4.1), so applying the
  new ones from `crds/` is optional. VolumeGroupSnapshot CRDs are not shipped (the UpCloud driver
  does not support group snapshots); snapshot-controller logs one warning
  about them at startup.
- **RBAC.** The provisioner role gains `volumeattachments` and
  `volumeattributesclasses` read access, matching external-provisioner v6.4.
  Every other rule the new sidecars need was added in 0.4.1.
- **Snapshot validation webhook (deprecated).** Upstream removed it in
  external-snapshotter v8.2; the chart runs its last image, v8.1.1, which
  validates only VolumeSnapshotClasses, and its ValidatingWebhookConfiguration
  now matches only `volumesnapshotclasses` over `v1`. Still off by default.
- `scripts/sync-upstream.sh csi` no longer copies the sidecar tags from
  UpCloud's `setup-upcloud-csi.yaml` when they are older than the chart's,
  which would have rolled them back to the 2022 releases on the next sync.

### Added

- `controller.sidecarExtraArgs.{provisioner,attacher,resizer,snapshotter}`
  appends arguments to each kubernetes-csi sidecar.

### Upgrading

- Leader election is unchanged: the same `--leader-election` flags and
  Lease names, so old and new controller pods hand over during the rollout.
- Stacks that override `images.<sidecar>.tag` keep those tags. Remove the
  overrides, or set them to the tags above, to get the new sidecars.

## [0.4.1] - 2026-09-29

### Fixed

- **VolumeSnapshots never became ReadyToUse with newer sidecars**: stacks
  that override `images.snapshotter.tag` / `images.snapshotController.tag`
  to the v8 line (and `images.provisioner.tag` to v6) ran into RBAC written
  for the pinned v4 sidecars. csi-snapshotter v8 records a finished snapshot
  by patching `volumesnapshotcontents/status`, which the role only allowed to
  `update`, so every snapshot was created at UpCloud but its content stayed
  unready: `cannot patch resource "volumesnapshotcontents/status"`. Velero
  waits 10 minutes per PVC for that and then fails the backup. The
  snapshotter, snapshot-controller, provisioner and resizer roles are now the
  union of the rules the pinned and the current kubernetes-csi sidecars need
  (including the `groupsnapshot.storage.k8s.io` rules and
  `volumeattributesclasses`). The change only adds permissions, so the
  default v4 sidecars are unaffected.

## [0.3.3] - 2026-08-07

### Fixed

- **default-SC hook Job could never run**: the hook's ServiceAccount /
  ClusterRole / ClusterRoleBinding were `pre-install,pre-upgrade` hooks with a
  `hook-succeeded` delete policy, while the patch Job itself is
  `post-install,post-upgrade`. Helm deletes succeeded pre-hooks at the end of
  the pre phase, so the post-install Job always failed pod creation with
  `serviceaccount "<release>-default-sc" not found`, hit
  `activeDeadlineSeconds`, and (with `--rollback-on-failure`) uninstalled the
  whole release: the chart was uninstallable whenever
  `storageClasses.defaultClass` was set. The SA/RBAC now ride the same
  `post-install,post-upgrade` event at a lower hook-weight than the Job, with
  delete policy `before-hook-creation` only; `hook-succeeded` stays on the Job
  (which also gains `before-hook-creation` so a lingering failed Job can't
  block the next upgrade).

## [0.3.2] - 2026-07-26

### Fixed

- **default-SC hook / snapshot CronJob image**: `registry.k8s.io/kubectl` is a
  distroless image with no shell, but both the default-StorageClass hook Job
  and the snapshot backup CronJob run `/bin/sh` scripts — the hook container
  could never start, the post-install hook failed, and with
  `--rollback-on-failure` every install of the chart was rolled back.
  Both now default to `docker.io/alpine/k8s:1.31.13` (kubectl + shell,
  amd64/arm64).

## [0.3.1] - 2026-07-19

### Fixed

- **Unschedulable on k3s**: the controller StatefulSet and snapshot-controller
  Deployment pinned to control-plane nodes via an exact-match
  `nodeSelector: {node-role.kubernetes.io/control-plane: ""}`. That empty-string
  value is the kubeadm convention; k3s labels its server node
  `node-role.kubernetes.io/control-plane: "true"`, so the selector never matched
  and both pods stayed `Pending` forever — meaning **no PersistentVolumeClaim
  could be dynamically provisioned**. Pinning now uses `affinity.nodeAffinity`
  with `operator: Exists` (matches the label regardless of value) and the
  default `nodeSelector` is empty (`{}`). The node DaemonSet was unaffected.
  Works on both kubeadm and k3s.

## [0.3.0] - 2026-06-28

### Fixed

- **Per-PVC snapshot retention**: the backup CronJob now rotates snapshots per
  source PVC (filtering on the `upcloud-csi.ankra.io/source-pvc` label) instead
  of namespace-wide. Previously `retentionCount` kept N snapshots across the
  whole namespace, so with multiple PVCs each volume could be pruned down to
  almost nothing.
- **PodMonitor metrics target**: enabling `metrics.podMonitor.enabled` now wires
  the csi-provisioner sidecar `--http-endpoint=:<metrics.port>` and a matching
  `metrics` container port on the controller pods, and scopes the PodMonitor to
  the controller. The UpCloud CSI driver exposes no metrics endpoint itself, so
  the previous PodMonitor scraped a port nothing served.
- **Snapshot webhook RBAC**: the snapshot-validation webhook ClusterRoleBinding
  now binds the controller ServiceAccount the Deployment actually runs as
  (previously bound the unused node ServiceAccount).

### Changed

- Added a chart `icon`, a `helm repo add` link, and the
  `snapshot-validation-webhook` / `kubectl` / `busybox` images to ArtifactHub
  metadata.

## [0.2.0] - 2026-05-22

### Added

- **Observability**: opt-in `PrometheusRule` with six recommended alerts
  (`UpCloudCSIControllerDown`, `UpCloudCSINodeMissing`,
  `UpCloudCSIPVCPending`, `UpCloudCSISnapshotControllerDown`,
  `UpCloudCSIVolumeNearFull`, `UpCloudCSIPodCrashLooping`),
  `PodMonitor` selecting controller + node CSI plugin pods, and a
  pre-canned Grafana dashboard ConfigMap.
- **Second VolumeSnapshotClass**: opt-in `upcloud-csi-snapshotclass-retain`
  with `deletionPolicy: Retain` for compliance / pre-migration archives.
- **Snapshot CronJob**: opt-in periodic `VolumeSnapshot` creation across
  every UpCloud-backed PVC, with namespace + PVC label selectors,
  configurable schedule / timezone, retention rotation, dry-run mode and
  least-privilege scoped RBAC.
- **StorageClass enrichments**: chart-wide and per-tier `allowedTopologies`,
  `mountOptions`, `annotations`, and `reclaimPolicy` / `volumeBindingMode`
  overrides.
- **helm test hook**: provisions a small PVC, mounts it on a busybox pod,
  writes and reads 4MiB of random data, then cleans up - exercises the
  full controller → UpCloud → node mount path.
- **Pod-spec passthroughs**: `hostAliases`, `dnsConfig`,
  `runtimeClassName`, `schedulerName`, `fsGroupChangePolicy`,
  `terminationMessagePolicy` across controller, node, snapshot-controller.
- **New overlays**:
  [`values-examples/observability.yaml`](values-examples/observability.yaml),
  [`values-examples/multi-zone.yaml`](values-examples/multi-zone.yaml),
  [`values-examples/backup-cronjob.yaml`](values-examples/backup-cronjob.yaml).
- **README runbooks** for snapshot/restore, multi-zone, observability and
  troubleshooting.
- **Chart metadata**: artifacthub.io `images`, `recommendations`,
  `category`, and rich `changes` annotations.
- **helm-unittest suites** for the new templates (snapshot classes,
  snapshot CronJob, storage-class topology, helm test hook,
  observability).

### Changed

- `.helmignore` anchors `tests/` / `values-examples/` / `vendor/` /
  `CHANGELOG.md` to the chart root (leading `/`) so
  `templates/tests/test-storage.yaml` actually ships in the chart tarball.
- `values.schema.json` extended with `snapshotClasses`, `snapshotCronJob`,
  `metrics`, `dashboard`, `tests`, pod-spec passthrough fields, and per-tier
  storage-class overrides.

## [0.1.0] - 2026-05-22

### Added

- Initial release of the `upcloud-csi` Helm chart, vendoring UpCloud CSI
  v1.4.0 (CRDs, RBAC, controller StatefulSet, snapshot-controller Deployment,
  node DaemonSet, three StorageClasses, optional snapshot validation webhook).
- Sibling-chart credential sharing - defaults to reusing the Secret created
  by the [`upcloud-ccm`](../upcloud-ccm/README.md) chart.
- Post-install/post-upgrade Helm hook Job that patches the chosen UpCloud SC
  as the cluster default (and clears K3s' built-in `local-path` default).
- Hardened pod & container security contexts everywhere except the node
  DaemonSet driver container (privileged by design - required for mount
  syscalls).
- HA defaults for the snapshot-controller (2 replicas + leader election +
  PDB) and a tunable HA path for the controller StatefulSet.
- Bitnami-pattern image overrides + per-image digest pinning support.
- `values.schema.json` enforcing `defaultClass` enum and credentials shape.
- `helm-unittest` test suites covering gated paths.
- `helm.sh/resource-policy: keep` on all bundled CRDs (survive
  `helm uninstall`).
