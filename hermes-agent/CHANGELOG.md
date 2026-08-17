# Changelog

All notable changes to the `hermes-agent` chart.

## 0.1.0 - 2026-08-16

Initial release. Hermes Agent `v2026.8.16`.

### Added

- Deployment, PVC, ConfigMap bootstrap, Secret, ExternalSecret, ServiceAccount,
  RBAC, Service, Ingress, Istio VirtualService, PodDisruptionBudget and
  NetworkPolicy templates, plus operator-ready `HermesTenant` custom resources.
- Image pinned by digest (`sha256:f8f548d8...`) alongside the readable tag, with
  `image.registry` for mirrors.
- NetworkPolicy on by default: ingress denied unless a Service is exposed, egress
  limited to DNS and public HTTPS with RFC1918, CGNAT, loopback and the
  `169.254.0.0/16` cloud metadata range excluded.
- Render-time guardrails for mutable image tags, inline API keys, privileged
  runtime settings, mounted ServiceAccount tokens, wildcard RBAC, wildcard CORS
  and unrestricted egress - each with a named `hardening.*` waiver.
- `values.schema.json` rejecting unknown top-level keys and malformed digests.
- `tcpSocket` liveness, readiness and startup probes when the API server
  listener is enabled.
- Ephemeral-storage requests and limits, and resource requests and limits on the
  init containers.
- `enableServiceLinks: false` so the namespace's Services are not injected into
  the agent's environment, and optional `hostUsers` passthrough.
- Opt-in npm package installs with `--ignore-scripts` and a configurable
  registry.
- helm-unittest suites (78 tests) and `values-examples/` overlays for minimal,
  production, air-gapped, multi-tenant and operator deployments.

### Notes

- Secrets are never passed through `tpl`; values are written verbatim.
- `config.values.security.tirith_fail_open` defaults to `false` (fail closed).
- ExternalSecret resources use `external-secrets.io/v1`.
