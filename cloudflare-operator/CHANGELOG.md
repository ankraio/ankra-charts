# Changelog

All notable changes to this chart will be documented in this file.

This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the chart version follows [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-22

### Added

- Initial release packaging
  [`adyanth/cloudflare-operator`](https://github.com/adyanth/cloudflare-operator)
  v0.13.1 as a Helm chart.
- Four `networking.cfargotunnel.com` CRDs (`Tunnel`, `ClusterTunnel`,
  `TunnelBinding`, `AccessTunnel`) installed with
  `helm.sh/resource-policy: keep` and a `crds.install` opt-out toggle.
- Full RBAC: manager `ClusterRole` + binding, leader-election `Role` +
  binding, metrics auth/reader `ClusterRole`s, and aggregate viewer / editor
  / admin `ClusterRole`s for each tunnel CRD (`rbac.aggregateClusterRoles`).
- cert-manager-backed conversion-webhook serving certificate, with optional
  self-signed `Issuer` or an external `Issuer` / `ClusterIssuer` reference.
- Secondary cert-manager `Certificate` for the secure metrics endpoint.
- Optional chart-managed Cloudflare API `Secret` or reuse of an
  externally-managed one (default: reuse `cloudflare-secrets`).
- Optional `ClusterOriginIssuer` + Origin CA `Secret` templates for
  integration with the upstream
  [cloudflare/origin-ca-issuer](https://github.com/cloudflare/origin-ca-issuer)
  Helm chart (installed separately).
- Optional sample `ClusterTunnel` custom resource for quickstart.
- HA defaults: leader election, `PodDisruptionBudget`, topology spread
  constraints, soft pod anti-affinity, rolling update with `maxUnavailable: 0`.
- Hardened security context (non-root, read-only rootfs, drop all
  capabilities, `seccompProfile: RuntimeDefault`).
- Liveness, readiness and (opt-in) startup probes.
- Optional `Service` and `ServiceMonitor` for Prometheus Operator scraping.
- Optional `NetworkPolicy` template restricting ingress to the webhook /
  metrics ports and egress to DNS + kube-apiserver + Cloudflare API.
- `global.imageRegistry`, `imagePullSecrets`, and digest pinning for
  air-gapped supply-chain hardening.
- `values.schema.json` enforcing the credential / webhook / sample-CR
  invariants the helper templates depend on.
- `helm-unittest` suites under `tests/`.

[Unreleased]: https://github.com/ankra-io/platform/compare/cloudflare-operator-0.1.0...HEAD
[0.1.0]: https://github.com/ankra-io/platform/releases/tag/cloudflare-operator-0.1.0
