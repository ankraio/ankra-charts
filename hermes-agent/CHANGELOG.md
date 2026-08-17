# Changelog

All notable changes to the `hermes-agent` chart.

## 0.1.1 - 2026-08-17

### Fixed

- **0.1.0 could not start.** The image runs s6-overlay as PID 1 and its stage2
  bootstrap refuses a pinned non-root UID outright ("container started with
  --user 1000 (an arbitrary, non-hermes UID) ... the baked /opt/hermes install
  tree is intentionally root-owned and non-writable"). The hardened
  `podSecurityContext` from 0.1.0 therefore produced a CrashLoopBackOff on every
  install. The pod now enters as root and drops to `env.HERMES_UID` /
  `env.HERMES_GID` (1000 by default), which is the model the image supports.
- The root filesystem stays read-only: s6-overlay only needs a writable `/run`,
  which is now an emptyDir, with `S6_READ_ONLY_ROOT=1` telling it to expect that.
- `capabilities.drop: [ALL]` alone left the agent dead but *reported healthy*:
  without CHOWN/DAC_OVERRIDE/SETGID/SETUID, s6-overlay cannot chown its service
  directories or setuid into the hermes user, so `main-hermes` starts and
  immediately stops (`s6-applyuidgid: fatal: unable to set supplementary group
  list: Operation not permitted`) while s6 keeps PID 1 alive and Kubernetes
  still reports Ready with zero restarts. Those four capabilities are now added
  back; verified minimal against the image, and all four are permitted by the
  PodSecurity `baseline` profile. The hardening guard now rejects anything
  *beyond* that set rather than requiring an empty list.
- Pinning `podSecurityContext.runAsUser` or `securityContext.runAsUser` is now
  refused at render time with the reason, instead of failing in the pod. Setting
  `podSecurityContext.runAsNonRoot: true` is refused for the same reason.
- The runtime guard that used to assert `runAsNonRoot` now asserts what is
  actually meaningful for this image: `env.HERMES_UID` must be non-zero, so the
  agent cannot be left running as root.

### Changed

- The chart's namespace needs PodSecurity `baseline`, not `restricted`, because
  the container enters as root. `values-examples/` and the README say so.

### Added

- A kind smoke test in CI that installs the chart against the real image and
  waits for the pod to become Ready. 0.1.0 shipped because CI only ran
  `helm install --dry-run=server`, which never executes the image.

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
