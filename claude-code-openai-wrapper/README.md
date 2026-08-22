# claude-code-openai-wrapper

[Claude Code OpenAI API Wrapper](https://github.com/RichardAtCT/claude-code-openai-wrapper)
on Kubernetes: an OpenAI-compatible `/v1/chat/completions` (and Anthropic-native
`/v1/messages`) endpoint backed by the Claude Agent SDK, so any OpenAI client
library can talk to Claude.

This chart is written and maintained by [Ankra](https://ankra.io); it is not a
fork of an upstream chart (upstream ships none). Upstream also publishes **no
container image**, and its checked-in Dockerfile is a development setup (root,
`--reload`, Poetry at runtime) - so Ankra builds a production image from the
pinned upstream release instead: multi-arch (amd64/arm64), non-root (uid 10001),
dependencies locked by upstream's `poetry.lock` with hash verification, no build
tooling in the runtime layer. See
[`images/claude-code-openai-wrapper/`](../images/claude-code-openai-wrapper/)
in this repository. Upstream declares MIT in its `pyproject.toml`.

## Quick start

```bash
kubectl create namespace claude
kubectl -n claude create secret generic claude-credentials \
  --from-literal=ANTHROPIC_API_KEY="$ANTHROPIC_API_KEY"

helm repo add ankra https://ankraio.github.io/ankra-charts
helm install claude-wrapper ankra/claude-code-openai-wrapper \
  --namespace claude \
  --set secrets.existingSecret=claude-credentials
```

Then point any OpenAI client at it:

```python
from openai import OpenAI

client = OpenAI(
    base_url="http://claude-wrapper-claude-code-openai-wrapper.claude.svc:8000/v1",
    api_key="anything",  # or the wrapper's API_KEY when protection is on
)
print(client.chat.completions.create(
    model="claude-sonnet-4-6",
    messages=[{"role": "user", "content": "Hello"}],
).choices[0].message.content)
```

## Hardening guardrails

`hardening.enabled=true` (the default) makes the chart refuse to render weak
configurations. Each rule has a named waiver, so weakening the posture is a
reviewable line in values, never an accident:

| Refused by default | Waiver |
| --- | --- |
| `image.tag` without `image.digest` | `hardening.allowMutableImageTag` |
| API keys inline in values | `hardening.allowInlineSecrets` |
| Ingress without the wrapper's `API_KEY` bearer-token protection | `hardening.allowUnauthenticatedIngress` |
| `"*"` in `server.corsOrigins` | `hardening.allowWildcardCors` |
| Root user, writable root filesystem, added capabilities, privilege escalation, mounted ServiceAccount token | `hardening.allowPrivilegedRuntime` |
| `networkPolicy.enabled=false` | `hardening.allowUnrestrictedNetwork` |
| Egress to 169.254.0.0/16 (cloud metadata endpoint) | `hardening.allowMetadataEndpointEgress` |
| Egress to RFC1918 / CGNAT ranges | `hardening.allowClusterInternalEgress` |

Why the Ingress rule exists: the wrapper exposes `POST /v1/tools/config`, which
switches on Claude Code's Read/Write/Bash tools *inside the pod*. Anything that
can reach the API unauthenticated can turn the pod into a code-execution
endpoint. The default NetworkPolicy limits the blast radius (no cluster network,
no metadata endpoint), but an Ingress without `API_KEY` hands the API itself to
the internet, so the chart refuses it.

## Authentication to Claude

| `auth.method` | What the chart does | What you provide |
| --- | --- | --- |
| `api-key` (default) | Sets `CLAUDE_AUTH_METHOD=api_key` | `ANTHROPIC_API_KEY` in the configured Secret |
| `session` | Sets `CLAUDE_AUTH_METHOD=cli`, so the bundled Claude Code CLI authenticates as a subscription | `CLAUDE_CODE_OAUTH_TOKEN` in the configured Secret |
| `bedrock` | Sets `CLAUDE_CODE_USE_BEDROCK=1` and `AWS_REGION` from `auth.bedrock.region` | AWS credentials in the Secret, or none at all with IRSA/pod identity (`serviceAccount.annotations`) |
| `vertex` | Sets `CLAUDE_CODE_USE_VERTEX=1`, `ANTHROPIC_VERTEX_PROJECT_ID`, `CLOUD_ML_REGION` | GCP credentials via Workload Identity, or a mounted service-account key |

Secrets come from one of three places, in order of preference: a Secret you
already manage (`secrets.existingSecret`), the External Secrets Operator
(`externalSecret.enabled`), or - only with an explicit waiver - inline values.
Every key of the Secret lands in the container environment verbatim, so use the
wrapper's own variable names (`ANTHROPIC_API_KEY`, `API_KEY`,
`AWS_ACCESS_KEY_ID`, ...).

### Where the session token comes from

`auth.method: session` bills usage to a Claude subscription instead of a metered
API key, so what it needs is an OAuth token rather than an `sk-ant-api...` key.
Two kinds of token authenticate identically and behave very differently once
deployed:

| Source | Lifetime | Use it for |
| --- | --- | --- |
| `claude setup-token` | long-lived, independent of your local session | anything you leave running |
| an interactive Claude Code login | expires on its own schedule; **the pod cannot refresh it** | a demo you are watching |

The second one is the trap: it authenticates on day one and the deployment goes
quiet later with no config change to blame. Mint a setup-token instead.

If you keep several Claude Code logins on one machine with
[claude-swap](https://pypi.org/project/claude-swap/), the token is already on
disk, and `scripts/claude-session-token` in this repository reads it out of the
account you name:

```bash
# a Secret this chart's secrets.existingSecret can point at
claude-session-token --account mark@ankra.ai --format secret | kubectl apply -f -

# or straight into the Ankra stack profile, without the token touching a
# command line, the shell history, or ps output
export CLAUDE_CODE_OAUTH_TOKEN="$(claude-session-token --account 2)"
ankra stack-profiles apply claude-code-session \
  --set-env manifest.claude-credentials.stringData.CLAUDE_CODE_OAUTH_TOKEN=CLAUDE_CODE_OAUTH_TOKEN
```

It refuses an account holding a managed API key (that is `auth.method: api-key`,
a different Secret key) and prints the expiry on stderr when the account holds a
short-lived login token, so the trap above is visible before you deploy rather
than a week later. Register a setup-token as its own claude-swap account with
`claude-swap add-token`, and this reads that instead.

## Scaling and sessions

Plain chat completions are stateless and scale horizontally. Upstream's session
continuity (`session_id`, the `/v1/sessions` endpoints) lives in each pod's
memory: with more than one replica, set `service.sessionAffinity=ClientIP` so a
conversation keeps hitting the pod that holds it, and expect `/v1/sessions`
listings to show one pod's view. The chart renders a NOTES warning when
replicas > 1 without affinity.

## Values examples

- [`values-examples/minimal.yaml`](values-examples/minimal.yaml) - smallest
  install that satisfies the guardrails.
- [`values-examples/production.yaml`](values-examples/production.yaml) - ESO
  credentials, Ingress with TLS and streaming-friendly timeouts, two replicas
  with ClientIP affinity, ingress restricted to the controller namespace.
- [`values-examples/bedrock.yaml`](values-examples/bedrock.yaml) - AWS Bedrock
  via IRSA: no Anthropic key exists anywhere.

## Verifying what you install

Charts and the image are cosign-signed (keyless OIDC); see
[the repository README](https://github.com/ankraio/ankra-charts#verifying-a-published-chart).
The image is additionally pinned by digest in `values.yaml`, and CI proves on
every change that the pinned digest still resolves in the registry
(`scripts/sync-image-digest.sh claude-code-openai-wrapper check`).
