# Changelog

All notable changes to the `claude-code-openai-wrapper` chart.

## 0.2.0 - 2026-08-18

### Added

- **`auth.method: session`** - authenticate as a Claude Code **subscription**
  rather than a metered API key. Generate a token with `claude setup-token`
  and supply it as `CLAUDE_CODE_OAUTH_TOKEN` in the configured Secret; the
  chart sets upstream's `CLAUDE_AUTH_METHOD=cli`, which hands the whole
  question to the bundled Claude Code CLI. The render refuses the mode when no
  token is reachable, mirroring how `api-key` refuses without an
  `ANTHROPIC_API_KEY`, so a missing credential fails at install rather than on
  the first request.

## 0.1.0 - 2026-08-18

### Added

- Initial release, wrapping upstream v2.3.0.
- **Ankra-built image**: upstream publishes no container image and its own
  Dockerfile is a development setup (root, `--reload`). The chart pins
  `ghcr.io/ankraio/images/claude-code-openai-wrapper` by digest - multi-arch, non-root
  (uid 10001), dependencies from upstream's `poetry.lock` with hash
  verification, built in this repository from the pinned upstream tag.
- **Hardening guardrails** (`hardening.*`): digest pinning, no inline secrets,
  no privileged runtime, no wildcard CORS, NetworkPolicy required, metadata
  endpoint and cluster-internal egress excluded - each refusal carries a named
  waiver.
- **Ingress requires the wrapper's `API_KEY`** unless explicitly waived:
  `POST /v1/tools/config` can switch on Claude Code's Read/Write/Bash tools
  inside the pod, so an unauthenticated public endpoint is refused at render
  time.
- **Three Claude auth modes**: `api-key` (default), `bedrock` (including
  credential-less IRSA), `vertex`.
- Secrets via `secrets.existingSecret` or the External Secrets Operator;
  `/health` probes; default-deny NetworkPolicy with same-namespace ingress;
  strict `values.schema.json` (unknown keys are refused).
