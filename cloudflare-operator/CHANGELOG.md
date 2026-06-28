# Changelog

All notable changes to this chart will be documented in this file.

This project adheres to [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)
and the chart version follows [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-06-28

### Fixed

- **Bring-your-own webhook TLS**: the `cert-manager.io/inject-ca-from`
  annotation is now only rendered on the CRDs when `webhook.certManager.enabled`
  is `true`. Previously, disabling cert-manager and supplying
  `webhook.existingSecretName` left the CRDs pointing at a Certificate that was
  never created, breaking the `ClusterTunnel` conversion webhook. The gating is
  applied in both the templates and `scripts/sync-upstream.sh` so it survives
  re-vendoring.
- **Sample ClusterTunnel `accountId`**: the optional sample now renders a real
  account ID via `sampleClusterTunnel.accountId` (falling back to
  `credentials.accountId`), and template validation fails fast when neither is
  set instead of rendering an empty `accountId`.
- **`automountServiceAccountToken`**: the Deployment now honors
  `serviceAccount.automountServiceAccountToken` instead of hardcoding `true`.

### Changed

- Added a chart `icon` and brought ArtifactHub metadata to parity with the
  sibling charts (`category`, `licenses`, `artifacthub.io/category`,
  `prerelease`, `containsSecurityUpdates`, `images`, `recommendations`,
  maintainer URL, `helm repo add` link).
- Corrected the README and `NOTES.txt`: only `ClusterTunnel` registers a
  conversion webhook, and the post-install check no longer references a
  non-existent APIService.

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
