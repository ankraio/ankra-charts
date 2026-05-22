# upcloud-ccm changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-05-22

### Added

- Initial release of the `upcloud-ccm` Helm chart packaging
  `ghcr.io/upcloudltd/cloud-controller-manager`.
- HA defaults: `replicaCount=2` + `--leader-elect=true`, rolling update with
  `maxUnavailable: 0`, PodDisruptionBudget, topology spread, soft pod
  anti-affinity.
- Hardened pod & container security contexts (`runAsNonRoot`, read-only root
  fs, dropped capabilities, `seccompProfile: RuntimeDefault`).
- Liveness/readiness probes targeting the CCM `/healthz` over HTTPS.
- Optional Prometheus Operator integration (`metrics.serviceMonitor.enabled`).
- Optional NetworkPolicy (`networkPolicy.enabled`).
- `values.schema.json` enforcing `ccmConfig.clusterID`, `loadBalancerPlan`
  enum, and credentials shape.
- Bitnami-pattern image overrides (`global.imageRegistry`, per-image
  `registry/repository/tag/digest`) for air-gapped installs.
- `helm-unittest` test suite under `tests/`.
