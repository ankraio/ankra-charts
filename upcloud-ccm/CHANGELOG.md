# upcloud-ccm changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-08-30

### Fixed

- **`ccmConfig.nodeScopeSelector` was silently dropped**: the ConfigMap
  template rendered only `clusterName`, `clusterID`, `loadBalancerPlan` and
  `loadBalancerMaxBackendMembers`, so a `nodeScopeSelector` set in values never
  reached the controller. The CCM has always supported the key, and anything
  relying on it - restricting which nodes the CCM manages, and which nodes are
  enrolled as LoadBalancer backends - was quietly a no-op. It now renders, and
  the key is documented in `values.yaml` and the schema.

  This is behaviour-changing for anyone who set it: the selector starts being
  honoured, which is what they asked for but not what they were getting.

### Added

- **`ccmConfig.loadBalancerBackendAddressSource`**: selects where a
  LoadBalancer backend member's address comes from - `node-internal-ip`
  (default, unchanged behaviour) or `private-network`, the node's address on
  the SDN private network the load balancer is attached to.

  `private-network` is for clusters whose node InternalIP is not an address a
  load balancer can reach, which is the case when the cluster advertises an
  overlay address (a WireGuard mesh spanning zones, say) as the node IP. With
  the default, members are accepted by the API but never pass a health check,
  so the Service is assigned an `EXTERNAL-IP`, the CCM logs
  `EnsuredLoadBalancer`, and the load balancer then serves 503 or refuses
  connections.

  The key needs a CCM build carrying the backend-address-source patch
  (`images/upcloud-ccm` in this repository); the stock upstream image parses
  its config non-strictly and ignores the key.

## [0.3.2] - 2026-07-26

### Fixed

- **helm test image**: `registry.k8s.io/kubectl` is a distroless image with no
  shell, but the connection test runs a `/bin/sh` script, so `helm test`
  containers could never start. The test image now defaults to
  `docker.io/alpine/k8s:1.31.13` (kubectl + shell, amd64/arm64).

## [0.3.1] - 2026-07-19

### Fixed

- **Unschedulable on k3s**: control-plane pinning previously relied on an
  exact-match `nodeSelector: {node-role.kubernetes.io/control-plane: ""}`. That
  empty-string value is the kubeadm convention; k3s labels its server node
  `node-role.kubernetes.io/control-plane: "true"`, so the selector never matched
  and the CCM stayed `Pending` forever — which meant no `Service type:
  LoadBalancer` ever got an address. Pinning now uses
  `affinity.nodeAffinity` with `operator: Exists`, which matches the label
  regardless of value, and the default `nodeSelector` is empty (`{}`). Works on
  both kubeadm and k3s.

## [0.3.0] - 2026-06-28

### Fixed

- **PodMonitor scrape auth**: removed the invalid empty `bearerTokenSecret`
  (`name: ""`, `key: ""`) that broke HTTPS scrapes. The block is now opt-in via
  `metrics.podMonitor.bearerTokenSecret.{name,key}` and omitted by default.
- **helm test RBAC**: the test pod now runs under a dedicated
  `<release>-test` ServiceAccount bound to a namespaced Role granting only
  `get/list/watch` on `deployments` and `pods`, instead of reusing the
  cluster-privileged CCM ServiceAccount (which lacked those rights and made
  `helm test` fail).
- **`automountServiceAccountToken`**: the Deployment now honors
  `serviceAccount.automountServiceAccountToken` instead of hardcoding `true`.
- **Metrics bind address**: `--bind-address=0.0.0.0` is now forced when either
  `serviceMonitor.enabled` or `podMonitor.enabled` is set (previously only
  ServiceMonitor).

### Changed

- README requirements and the values reference now correctly document
  `serviceAccount.create` and `rbac.create` defaulting to `true` (external-CCM
  setup), matching `values.yaml`.
- Added a chart `icon` and a `helm repo add` link for ArtifactHub; removed the
  broken dashboard screenshot reference and the empty `signKey` annotation.

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
