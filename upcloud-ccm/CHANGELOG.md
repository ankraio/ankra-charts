# upcloud-ccm changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-05-22

### Added

- **Observability**: opt-in `PrometheusRule` with recommended alerts
  (`UpCloudCCMDown`, `UpCloudCCMLeaderElectionFlapping`,
  `UpCloudCCMReconcileErrors`, `UpCloudCCMPodCrashLooping`),
  `PodMonitor` (alternative to ServiceMonitor for direct pod scraping),
  and a pre-canned Grafana dashboard ConfigMap discovered by the
  kube-prometheus-stack Grafana sidecar.
- **helm test hook**: a `kubectl rollout status` pod that validates the
  CCM Deployment after install/upgrade.
- **Pod-spec passthroughs**: `hostAliases`, `dnsConfig`,
  `runtimeClassName`, `schedulerName`, `fsGroupChangePolicy`
  (default `OnRootMismatch`), `terminationMessagePolicy`
  (default `FallbackToLogsOnError`).
- **New overlay**: [`values-examples/observability.yaml`](values-examples/observability.yaml)
  drops in the full kube-prometheus-stack observability bundle.
- **Chart metadata**: artifacthub.io `category`, `images`, `recommendations`,
  `screenshots`, and rich `changes` annotations.
- **helm-unittest suites** covering the new templates.

### Changed

- `.helmignore` anchors `tests/` / `values-examples/` / `CHANGELOG.md` to the
  chart root (leading `/`) so `templates/tests/test-connection.yaml` actually
  ships in the chart tarball.
- `values.schema.json` extended with `dashboard`, `tests`, pod-spec passthrough
  fields.

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
