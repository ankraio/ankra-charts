# Changelog

All notable changes to the `hermes-agent` chart.

## 0.3.0 - 2026-08-23

### Added

- **Several model endpoints at once.** `config.values.providers` declares named
  OpenAI-compatible endpoints, each with its own `key_env`; `model.provider`
  picks the main one by name, `/model` switches a session between them, and
  `config.values.fallback_providers` is the chain Hermes fails over to on
  429/5xx/401/404 without losing the conversation. Until now the chart modelled
  exactly one endpoint (`model.*` plus one `LM_BASE_URL`/`LM_API_KEY` pair), so
  holding a hosted API and an in-cluster gateway side by side meant editing
  `config.yaml` by hand on every switch. Both keys are typed in
  `values.schema.json`, documented in the README, and shown end to end in
  `values-examples/multi-provider.yaml` (Salad + the Claude Code wrapper).
  Hermes `v2026.8.16`, the pinned image, already reads both keys.

### Security

- An inline `api_key` on the main model, a named provider or a fallback entry is
  refused unless `hardening.allowInlineSecrets=true`, with the value path in
  the message - it would otherwise land in the rendered `config.yaml` as well as
  the release Secret.

### Fixed

- **A model endpoint the NetworkPolicy would drop is refused at render time.**
  `model.base_url`, a provider `api` or a fallback `base_url` on a `.svc`,
  `.cluster.local`, loopback or RFC1918 address now fails unless
  `networkPolicy.egress.extra` (or `tenantIsolation.additionalEgress`) carries
  a rule, the private ranges have been un-excluded, or the policy is off. The
  default egress excludes private networks, so such a deployment came up green
  and then had every model call dropped by its own policy - invisible on a CNI
  that does not enforce NetworkPolicy, fatal on one that does.
- A `key_env` that nothing in the release puts on the pod is refused when the
  Secret is chart-managed; a fallback entry missing `provider` or `model` is
  refused (Hermes silently skips it); `model.base_url` contradicting a named
  `model.provider` is refused.

## 0.2.0 - 2026-08-18

### Added

- **`camofox.enabled` runs the anti-detection browser as a sidecar.** Hermes
  routes every one of its browser tools through Camofox as soon as `CAMOFOX_URL`
  is set, in place of agent-browser and Browserbase, so this is the difference
  between a browser that announces itself as automation and one that does not.
  It runs as a second container rather than inside the agent because Camoufox
  needs GTK3, Mesa and Xvfb that the agent image does not ship - same pod, so the
  agent reaches it on loopback with no NetworkPolicy rule and no Service. Point
  `camofox.url` at an external Camofox to use one you already run.

### Security

- The sidecar image must be digest-pinned: it renders every page the agent
  visits, so a moved tag is a code-execution change. Waiver:
  `hardening.allowMutableImageTag=true`.
- `camofox.securityContext` deliberately omits `runAsUser`, `runAsNonRoot` and
  `readOnlyRootFilesystem`. Upstream bakes the Camoufox bundle into
  `/root/.cache/camoufox` and sets no `USER`, and Firefox wants a writable
  profile directory, so pinning them unverified would ship a CrashLoopBackOff.
  They are left visible in values for whoever has exercised the image.

### Note

- `ghcr.io/ankraio/images/camofox-browser` is built by this repository from
  upstream's pinned tag (upstream publishes no image) and is **amd64 only** -
  the Camoufox binary architecture is a build argument there.

## 0.1.4 - 2026-08-18

### Added

- **A browser the agent can actually drive.** The image enables a `browser`
  toolset that attaches to a Chromium over the DevTools Protocol at
  `http://127.0.0.1:9222`, but ships no browser binary, so out of the box the
  toolset is enabled with nothing behind it. `browser.cdp.enabled=true` puts a
  digest-pinned headless Chromium in the pod on exactly that address - same
  network namespace, loopback only, unprivileged, non-root, read-only root,
  all capabilities dropped. Off by default: it is a second image and the widest
  attack surface an agent can be handed.
- **Declarative MCP servers.** `mcp.servers` renders `mcp.json` into the agent
  home through the same bootstrap path as `config.yaml` and `SOUL.md`, so a
  server is live on start instead of needing `hermes mcp add` inside the pod.
  The document is written in the exact shape the agent validates (`$schema`
  plus `mcpServers`, nothing else). This is the lane for browsers the built-in
  toolset cannot drive - Camoufox speaks Playwright rather than CDP, so it
  arrives as an MCP server; `values-examples/browser-stealth.yaml` wires both
  halves.

## 0.1.3 - 2026-08-17

### Added

- The data volume now ships `helm.sh/resource-policy: keep`, so `helm uninstall`
  leaves it behind instead of deleting the agent's memory, sessions and platform
  pairings. Set `persistence.keepOnUninstall=false` to go back to the old
  behaviour. Helm reads this annotation from the **stored release manifest**, so
  annotating a live PVC after the fact does nothing - it has to ship with the
  chart, which is how a real uninstall took a volume with it.

## 0.1.2 - 2026-08-17

### Fixed

- **The agent could not write its own state on a PersistentVolume.** 0.1.1 started
  and reported Ready, then failed with
  `PermissionError: [Errno 13] Permission denied: '/opt/data/gateway_state.json'`
  followed by `no such gateway 'default'`. Two causes, both only visible against
  a real PVC:
  - `HERMES_UID` silently does nothing when `readOnlyRootFilesystem: true`.
    Remapping the user means rewriting `/etc/passwd`, which the read-only root
    forbids, so the agent keeps the image's native uid/gid **10000** while
    `fsGroup: 1000` owned the volume. The chart now asks for 10000, making the
    remap a deliberate no-op rather than an accidental one, and keeps `fsGroup`
    in agreement.
  - `fsGroup` sets a volume's group but never its owner, and the image only
    chowns paths it creates, so a pre-existing volume root stays root-owned. The
    bootstrap init container now runs `chown -R "$HERMES_UID:$HERMES_GID"` on the
    data volume. It runs as root and does not go through the image entrypoint,
    so it is the right place for it.

Verified on a real cluster: pod Running, 0 restarts, gateway up, Telegram adapter
connected and command menu registered.

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
