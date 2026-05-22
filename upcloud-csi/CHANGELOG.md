# upcloud-csi changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

The chart's `appVersion` tracks upstream
[`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi)
releases. Daily sync via
[`upcloud-charts-sync.yml`](../../.github/workflows/upcloud-charts-sync.yml)
auto-bumps these.

## [Unreleased]

## [0.1.0] - 2026-05-22

### Added

- Initial release of the `upcloud-csi` Helm chart, vendoring UpCloud CSI
  v1.4.0 (CRDs, RBAC, controller StatefulSet, snapshot-controller Deployment,
  node DaemonSet, three StorageClasses, optional snapshot validation webhook).
- Sibling-chart credential sharing — defaults to reusing the Secret created
  by the [`upcloud-ccm`](../upcloud-ccm/README.md) chart.
- Post-install/post-upgrade Helm hook Job that patches the chosen UpCloud SC
  as the cluster default (and clears K3s' built-in `local-path` default).
- Hardened pod & container security contexts everywhere except the node
  DaemonSet driver container (privileged by design — required for mount
  syscalls).
- HA defaults for the snapshot-controller (2 replicas + leader election +
  PDB) and a tunable HA path for the controller StatefulSet.
- Bitnami-pattern image overrides + per-image digest pinning support.
- `values.schema.json` enforcing `defaultClass` enum and credentials shape.
- `helm-unittest` test suites covering gated paths.
- `helm.sh/resource-policy: keep` on all bundled CRDs (survive
  `helm uninstall`).
