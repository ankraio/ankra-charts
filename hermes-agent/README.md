# hermes-agent

Nous Research [Hermes Agent](https://github.com/NousResearch/hermes-agent) on
Kubernetes, packaged the way Ankra runs it: image pinned by digest, credentials
that have to come from a Secret you already manage, and a NetworkPolicy that
keeps the agent away from the cluster network and the cloud metadata endpoint.

Hermes is an agent that runs a shell and a browser. Treat it as untrusted
workload that happens to hold your model provider keys, and the defaults in this
chart make sense.

| | |
|---|---|
| Chart | `oci://ghcr.io/ankraio/ankra-charts/hermes-agent` |
| Helm repo | `helm repo add ankra https://ankraio.github.io/ankra-charts` |
| Image | `docker.io/nousresearch/hermes-agent`, digest-pinned in `values.yaml` |
| Upstream project | [NousResearch/hermes-agent](https://github.com/NousResearch/hermes-agent) |

## Install

Hermes needs at least one model provider key. The chart will not accept it as a
plain value, so create the Secret first:

```bash
kubectl create namespace hermes
kubectl -n hermes create secret generic hermes-credentials \
  --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY"

helm install hermes oci://ghcr.io/ankraio/ankra-charts/hermes-agent \
  --version 0.1.0 -n hermes \
  --set secrets.existingSecret=hermes-credentials
```

Any environment variable Hermes reads can live in that Secret - every key is
loaded with `envFrom`. The commonly used ones:

| Purpose | Keys |
|---|---|
| Model providers | `OPENROUTER_API_KEY`, `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `NOUS_API_KEY`, `HF_TOKEN` |
| Tools | `EXA_API_KEY`, `FIRECRAWL_API_KEY`, `FAL_KEY`, `BROWSERBASE_API_KEY`, `BROWSERBASE_PROJECT_ID`, `GITHUB_TOKEN` |
| Chat surfaces | `TELEGRAM_BOT_TOKEN`, `DISCORD_BOT_TOKEN`, `SLACK_BOT_TOKEN`, `SLACK_APP_TOKEN`, `SIGNAL_HTTP_URL` |
| API server | `API_SERVER_KEY` |

Overlays for the usual shapes live in [`values-examples/`](values-examples):
`minimal`, `production`, `air-gapped`, `multi-tenant`, `operator`.

## What the defaults enforce

Every rule below fails `helm template`/`helm install` with an explanation rather
than shipping a weaker manifest. Each has a named waiver under `hardening.*`, so
loosening one is a visible line in your values file.

| Rule | Waiver |
|---|---|
| The image is pinned by digest, not just by tag | `hardening.allowMutableImageTag` |
| API keys come from `secrets.existingSecret` or an ExternalSecret, never inline values | `hardening.allowInlineSecrets` |
| Non-root, `runAsNonRoot`, read-only root filesystem, `ALL` capabilities dropped, no privilege escalation, no added capabilities | `hardening.allowPrivilegedRuntime` |
| No ServiceAccount token mounted - Hermes never calls the Kubernetes API | `hardening.allowPrivilegedRuntime` |
| `rbac.rules` may not contain `*` | `hardening.allowWildcardRbac` |
| A NetworkPolicy is present | `hardening.allowUnrestrictedNetwork` |
| Egress excludes `169.254.0.0/16` (cloud instance metadata) | `hardening.allowMetadataEndpointEgress` |
| Egress excludes RFC1918 (`10/8`, `172.16/12`, `192.168/16`) | `hardening.allowClusterInternalEgress` |
| `apiServer.corsOrigins` is not `*` | none - list the origins |
| One replica and a `Recreate` rollout while persistence is on | none - `HERMES_HOME` is single-writer |
| npm packages install only when `npm.enabled=true`, and never run lifecycle scripts | `npm.ignoreScripts` |

`hardening.enabled=false` turns all of it off at once. It exists for local
experiments and is not a supported way to run this chart.

### The network default, concretely

```yaml
egress:
  - to: [{ namespaceSelector: { matchLabels: { kubernetes.io/metadata.name: kube-system } } }]
    ports: [{ protocol: UDP, port: 53 }, { protocol: TCP, port: 53 }]
  - to:
      - ipBlock:
          cidr: 0.0.0.0/0
          except: [10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 169.254.0.0/16, 100.64.0.0/10, 127.0.0.0/8]
    ports: [{ protocol: TCP, port: 443 }]
```

DNS, and HTTPS to public addresses. That is enough to reach OpenRouter,
Anthropic, OpenAI and the usual tool APIs, and not enough to reach your
in-cluster Postgres, another tenant's pods, or the instance metadata service
that hands out node IAM credentials.

Ingress is denied unless a Service is exposed, in which case only the release
namespace (plus `networkPolicy.ingress.allowedNamespaces`) reaches the exposed
ports.

Two things to know:

- **This is only real if your CNI enforces NetworkPolicy.** Cilium, Calico and
  Antrea do; some managed CNIs and plain flannel do not. On a CNI that ignores
  policies the manifest is decoration.
- **Egress to an in-cluster model gateway needs an explicit rule**, because
  RFC1918 is excluded. See `values-examples/air-gapped.yaml`.

## Configuration

`config.values` is rendered to `HERMES_HOME/config.yaml` by an init container,
`soul.text` to `SOUL.md`. `bootstrap.overwrite=true` (the default) makes Helm the
source of truth on every restart; set it to `false` to seed once and let the
agent own the file afterwards. `config.raw` takes a templated YAML string when
the structured form is not enough.

Two defaults differ from the Hermes sample configuration on purpose:

| Setting | Here | Why |
|---|---|---|
| `security.tirith_fail_open` | `false` | Upstream fails open: if the policy engine errors, the request proceeds unchecked. |
| `browser.allow_private_urls` | `false` | Second line of defence behind the NetworkPolicy - the browser tool should not fetch cluster-internal URLs. |

## Exposing the API server

```bash
helm upgrade hermes oci://ghcr.io/ankraio/ankra-charts/hermes-agent \
  -n hermes --version 0.1.0 \
  --set secrets.existingSecret=hermes-credentials \
  --set apiServer.enabled=true \
  --set service.enabled=true
```

`apiServer.enabled=true` requires an `API_SERVER_KEY` in the Secret - the
OpenAI-compatible endpoint is unauthenticated without it. The Service, the
container port and the NetworkPolicy ingress rule are all derived from the
enabled listeners, so there is nothing else to keep in step. Enabling it also
installs `tcpSocket` liveness/readiness/startup probes; set `probes.*` to
replace them.

`ingress.enabled=true` and `virtualService.enabled=true` (Istio) route to the
first exposed port unless you set `servicePortNumber`.

## Storage

`HERMES_HOME` (`/opt/data`) holds conversation state, the seeded config and any
npm packages, on a `ReadWriteOnce` PVC. That makes the workload single-writer:
the chart refuses `replicaCount > 1` and refuses `RollingUpdate` while
persistence is on. For more agents, install more releases - one per agent, or
one per tenant with `values-examples/multi-tenant.yaml`.

Set `persistence.enabled=false` for a stateless gateway; the volume becomes an
`emptyDir` and the single-writer rules no longer apply.

## Operator-ready mode

`operator.enabled=true` renders `HermesTenant` custom resources
(`hermes.ai/v1alpha1`) instead of a workload, for platforms that run their own
controller. **This chart does not ship a controller** - without one, the custom
resources sit there and nothing runs. The CRD lives in `crds/`, which Helm
installs but never upgrades or deletes; apply changes with
`kubectl apply --server-side -f hermes-agent/crds/`.

## Verifying a published chart

Every chart pushed to GHCR is signed with cosign (keyless, GitHub OIDC) and
carries an SPDX SBOM attestation:

```bash
cosign verify oci://ghcr.io/ankraio/ankra-charts/hermes-agent:0.1.0 \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify-attestation --type spdxjson \
  oci://ghcr.io/ankraio/ankra-charts/hermes-agent:0.1.0 \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The GitHub Pages repo publishes a cosign bundle next to each package, so HTTP
consumers can verify too:

```bash
curl -fsSLO https://ankraio.github.io/ankra-charts/hermes-agent-0.1.0.tgz
curl -fsSLO https://ankraio.github.io/ankra-charts/hermes-agent-0.1.0.tgz.cosign.bundle
cosign verify-blob hermes-agent-0.1.0.tgz \
  --bundle hermes-agent-0.1.0.tgz.cosign.bundle \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Relationship to the community chart

There is an unofficial community chart at
[`ultraworkers/hermes-agent-helm-chart`](https://github.com/ultraworkers/hermes-agent-helm-chart).
This is a separate implementation, not a fork: that repository publishes no Helm
index and carries no licence file, so Ankra maintains its own chart under
Apache-2.0 with the same feature surface and different defaults.

Behaviour worth knowing about if you are moving across:

| | Community chart | Here |
|---|---|---|
| Image | `nousresearch/hermes-agent:0.8.0` - **a tag that does not exist on Docker Hub**; the real tags are CalVer (`v2026.8.16`) | Real tag, pinned by digest |
| API keys | ~60 enumerated keys in `values.yaml`, meant to be filled in | Refused inline; `existingSecret` or ExternalSecret |
| Secret values | Passed through `tpl`, so a key containing `{{` is executed as a template | Written verbatim |
| ExternalSecret API | `external-secrets.io/v1beta1`, removed in ESO 0.17 | `external-secrets.io/v1`, configurable |
| NetworkPolicy | Off by default, raw rules only | On by default, metadata and RFC1918 excluded |
| Init containers | No resource requests or limits | Same requests and limits as the main container |
| npm installs | Runs lifecycle scripts from the public registry | Opt-in, `--ignore-scripts`, configurable registry |
| Values typos | Accepted silently | Rejected by `values.schema.json` |
| Guardrails | Docs | Render-time failures with named waivers |

## Values

See [`values.yaml`](values.yaml) for the annotated set and
[`values.schema.json`](values.schema.json) for the contract - unknown top-level
keys are rejected, so a typo fails the install instead of being ignored.

## Local development

```bash
helm lint hermes-agent
helm template hermes hermes-agent -n hermes -f hermes-agent/values-examples/production.yaml
helm unittest hermes-agent

# Re-resolve the pinned image digest from the registry.
./scripts/sync-image-digest.sh hermes-agent
```
