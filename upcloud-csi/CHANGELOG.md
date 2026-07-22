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

## [0.3.1] - 2026-07-22

### Fixed

- **default-SC hook / snapshot CronJob image**: `registry.k8s.io/kubectl` is a
  distroless image with no shell, but both the default-StorageClass hook Job
  and the snapshot backup CronJob run `/bin/sh` scripts — the hook container
  could never start, the post-install hook failed, and with
  `--rollback-on-failure` every install of the chart was rolled back.
  Both now default to `docker.io/alpine/k8s:1.31.13` (kubectl + shell,
  amd64/arm64).

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
