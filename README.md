# charts

In-tree Helm charts maintained by the Ankra platform team.

| Chart | Description | Source of truth |
|---|---|---|
| [`upcloud-ccm`](upcloud-ccm/README.md) | UpCloud Cloud Controller Manager — provisions LoadBalancers, manages node labels, clears the `uninitialized` cloud-provider taint. | Hand-written from UpCloud docs; image `ghcr.io/upcloudltd/cloud-controller-manager`. |
| [`upcloud-csi`](upcloud-csi/README.md) | UpCloud CSI block-storage driver — controller StatefulSet, snapshot-controller, node DaemonSet, three StorageClasses. | Vendored from upstream [`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi); auto-bumped daily. |
| [`cloudflare-operator`](cloudflare-operator/README.md) | Cloudflare Tunnel operator (Tunnel / ClusterTunnel / TunnelBinding / AccessTunnel CRDs) — plus optional `ClusterOriginIssuer` for the cert-manager Origin CA external issuer. | Vendored from upstream [`adyanth/cloudflare-operator`](https://github.com/adyanth/cloudflare-operator); auto-bumped daily. |
| [`digitalocean-ccm`](digitalocean-ccm/README.md) | DigitalOcean Cloud Controller Manager - provisions DO Load Balancers, manages node lifecycle, clears the `uninitialized` cloud-provider taint. | Vendored from upstream [`digitalocean/digitalocean-cloud-controller-manager`](https://github.com/digitalocean/digitalocean-cloud-controller-manager) release manifests (no upstream chart exists); auto-bumped daily. |
| [`digitalocean-csi`](digitalocean-csi/README.md) | DigitalOcean CSI block-storage driver - controller StatefulSet, node DaemonSet, snapshot-controller, snapshot CRDs, four `do-block-storage*` StorageClasses. | Vendored from upstream [`digitalocean/csi-digitalocean`](https://github.com/digitalocean/csi-digitalocean) release manifests (no upstream chart exists); auto-bumped daily. |
| [`hermes-agent`](hermes-agent/README.md) | Nous Research [Hermes Agent](https://github.com/NousResearch/hermes-agent) - LLM agent gateway with an optional OpenAI-compatible API server. Digest-pinned, non-root, egress-restricted by default, with render-time hardening guardrails. | Ankra-maintained; image `docker.io/nousresearch/hermes-agent`, digest re-pinned daily. |
| [`psono`](psono/README.md) | Self-hosted [Psono](https://psono.com/) password manager — server, web client and optional admin client behind a single Ingress (Traefik by default). Bring your own PostgreSQL + Secrets. | Hand-written from Psono [server install docs](https://doc.psono.com/admin/installation/install-server-ce.html); images `psono/psono-{server,client,admin-client}`. |

## Install via `helm repo add` (recommended)

Charts are published as a classic HTTP Helm repository on GitHub Pages and
indexed on [ArtifactHub](https://artifacthub.io/packages/search?repo=ankra-charts).

```bash
helm repo add ankra https://ankraio.github.io/ankra-charts
helm repo update
helm search repo ankra

# UpCloud CCM
helm install upcloud-ccm ankra/upcloud-ccm --version 0.3.0 -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# UpCloud CSI
helm install upcloud-csi ankra/upcloud-csi --version 0.3.0 -n kube-system \
  --set storageClasses.defaultClass=maxiops

# Cloudflare operator
helm install cloudflare-operator ankra/cloudflare-operator --version 0.2.0 \
  -n cloudflare-operator-system --create-namespace \
  -f cloudflare-operator/values-examples/minimal.yaml

# DigitalOcean CCM
helm install digitalocean-ccm ankra/digitalocean-ccm --version 0.1.0 -n kube-system \
  --set credentials.token="$DIGITALOCEAN_ACCESS_TOKEN"

# DigitalOcean CSI
helm install digitalocean-csi ankra/digitalocean-csi --version 0.1.0 -n kube-system \
  --set credentials.create=false \
  --set credentials.existingSecret=digitalocean

# Hermes Agent - the API keys have to come from a Secret you already manage.
kubectl -n hermes create secret generic hermes-credentials \
  --from-literal=OPENROUTER_API_KEY="$OPENROUTER_API_KEY"
helm install hermes ankra/hermes-agent --version 0.1.0 -n hermes --create-namespace \
  --set secrets.existingSecret=hermes-credentials
```

## Install from GHCR (OCI)

Charts are also published to GitHub Container Registry on every merge to `main`
that touches a chart (or manually via **Actions → charts-publish → Run workflow**).

Registry namespace: `oci://ghcr.io/ankraio/ankra-charts`

```bash
# UpCloud CCM (0.2.0+ ships PrometheusRule, PodMonitor, Grafana dashboard, helm test hook)
helm install upcloud-ccm oci://ghcr.io/ankraio/ankra-charts/upcloud-ccm \
  --version 0.2.0 -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# UpCloud CSI (0.2.0+ ships VolumeSnapshotClass with Retain policy, periodic snapshot CronJob,
# allowedTopologies, PrometheusRule, PodMonitor, Grafana dashboard, helm test hook)
helm install upcloud-csi oci://ghcr.io/ankraio/ankra-charts/upcloud-csi \
  --version 0.2.0 -n kube-system \
  --set storageClasses.defaultClass=maxiops

# Cloudflare operator
helm install cloudflare-operator oci://ghcr.io/ankraio/ankra-charts/cloudflare-operator \
  --version 0.1.0 -n cloudflare-operator-system --create-namespace \
  -f cloudflare-operator/values-examples/minimal.yaml

# DigitalOcean CCM + CSI (share the conventional `digitalocean` Secret)
helm install digitalocean-ccm oci://ghcr.io/ankraio/ankra-charts/digitalocean-ccm \
  --version 0.1.0 -n kube-system \
  --set credentials.token="$DIGITALOCEAN_ACCESS_TOKEN"

helm install digitalocean-csi oci://ghcr.io/ankraio/ankra-charts/digitalocean-csi \
  --version 0.1.0 -n kube-system \
  --set credentials.create=false \
  --set credentials.existingSecret=digitalocean-ccm-credentials

# Hermes Agent (LLM agent gateway) — see hermes-agent/README.md for the
# Secret it expects and the guardrails it enforces.
helm install hermes oci://ghcr.io/ankraio/ankra-charts/hermes-agent \
  --version 0.1.0 -n hermes --create-namespace \
  --set secrets.existingSecret=hermes-credentials

# Psono (self-hosted password manager) — requires the BYO Secrets described
# in psono/README.md to already exist in the target namespace.
helm install psono oci://ghcr.io/ankraio/ankra-charts/psono \
  --version 1.1.0 -n psono --create-namespace \
  --set base_url=https://psono.example.com \
  --set domain=example.com \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true
```

### UpCloud - observability overlays

```bash
# Full kube-prometheus-stack integration for both charts (alerts + dashboard).
helm upgrade upcloud-ccm oci://ghcr.io/ankraio/ankra-charts/upcloud-ccm \
  --version 0.2.0 -n kube-system \
  -f upcloud-ccm/values-examples/observability.yaml \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

helm upgrade upcloud-csi oci://ghcr.io/ankraio/ankra-charts/upcloud-csi \
  --version 0.2.0 -n kube-system \
  -f upcloud-csi/values-examples/observability.yaml

# Periodic VolumeSnapshot CronJob (daily 02:00 UTC, 7-snapshot retention).
helm upgrade upcloud-csi oci://ghcr.io/ankraio/ankra-charts/upcloud-csi \
  --version 0.2.0 -n kube-system \
  -f upcloud-csi/values-examples/backup-cronjob.yaml

# Multi-zone topology constraints.
helm upgrade upcloud-csi oci://ghcr.io/ankraio/ankra-charts/upcloud-csi \
  --version 0.2.0 -n kube-system \
  -f upcloud-csi/values-examples/multi-zone.yaml
```

Private clusters need a registry login first:

```bash
helm registry login ghcr.io -u <github-user> -p <github-pat-with-read:packages>
```

## Verifying a published chart

Charts pushed to GHCR are signed with [cosign](https://docs.sigstore.dev/) using
keyless GitHub OIDC - there is no long-lived signing key to steal - and carry an
SPDX SBOM attestation. The identity in the certificate is the workflow that
published them.

```bash
cosign verify oci://ghcr.io/ankraio/ankra-charts/<chart>:<version> \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com

cosign verify-attestation --type spdxjson \
  oci://ghcr.io/ankraio/ankra-charts/<chart>:<version> \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

The GitHub Pages repo publishes a cosign bundle beside every package, so
`helm repo add` consumers can verify the same way:

```bash
curl -fsSLO https://ankraio.github.io/ankra-charts/<chart>-<version>.tgz
curl -fsSLO https://ankraio.github.io/ankra-charts/<chart>-<version>.tgz.cosign.bundle
cosign verify-blob <chart>-<version>.tgz \
  --bundle <chart>-<version>.tgz.cosign.bundle \
  --certificate-identity-regexp '^https://github\.com/ankraio/ankra-charts/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Install from source (local checkout)

1. **`upcloud-ccm`** first (on UpCloud-backed clusters) - it creates the
   shared `<release>-credentials` Secret used by both UpCloud charts.
2. **`upcloud-csi`** second - defaults to reusing the CCM-created Secret.
3. **`cloudflare-operator`** independently - requires only cert-manager and
   a `cloudflare-secrets` Secret in the install namespace.

```bash
# 1. UpCloud CCM
helm install upcloud-ccm ./upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# 2. UpCloud CSI (reuses the CCM Secret by default)
helm install upcloud-csi ./upcloud-csi -n kube-system \
  --set storageClasses.defaultClass=maxiops

# 3. Cloudflare operator (assumes cert-manager + cloudflare-secrets exist)
helm install cloudflare-operator ./cloudflare-operator \
  -n cloudflare-operator-system --create-namespace \
  -f ./cloudflare-operator/values-examples/minimal.yaml

# 4. Psono — independent of the above, assumes a PostgreSQL + psono-secret
#    / psono-database-secret Secret already exist in the namespace.
helm install psono ./psono -n psono --create-namespace \
  --set base_url=https://psono.example.com \
  --set domain=example.com \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true
```

## Automation

GitHub Actions workflows under `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| [`charts-upcloud-sync.yml`](.github/workflows/charts-upcloud-sync.yml) | Daily `17 6 * * *` cron + `workflow_dispatch` | Runs `scripts/sync-upstream.sh` for both UpCloud charts and opens a rolling PR. |
| [`charts-upcloud-lint.yml`](.github/workflows/charts-upcloud-lint.yml) | PR / push under `upcloud-{ccm,csi}/**` | `helm lint`, `helm template`, `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31. |
| [`charts-cloudflare-operator-sync.yml`](.github/workflows/charts-cloudflare-operator-sync.yml) | Daily `27 6 * * *` cron + `workflow_dispatch` | Re-vendors upstream `cloudflare-operator.{crds,}yaml`, re-splits CRDs, bumps `appVersion`, opens a rolling PR. |
| [`charts-cloudflare-operator-lint.yml`](.github/workflows/charts-cloudflare-operator-lint.yml) | PR / push under `cloudflare-operator/**` | `shellcheck`, `helm lint`, `helm template` (4 overlays), `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31 (cert-manager pre-installed). |
| [`charts-digitalocean-sync.yml`](.github/workflows/charts-digitalocean-sync.yml) | Daily `37 6 * * *` cron + `workflow_dispatch` | Runs `scripts/sync-upstream.sh do-ccm` / `do-csi` against the upstream DigitalOcean release feeds and opens a rolling PR. |
| [`charts-digitalocean-lint.yml`](.github/workflows/charts-digitalocean-lint.yml) | PR / push under `digitalocean-{ccm,csi}/**` | `shellcheck`, `helm lint`, `helm template`, `kubeconform`, `helm-unittest`, `helm install --dry-run=server` on Kind across K8s 1.27 / 1.29 / 1.31. |
| [`charts-hermes-lint.yml`](.github/workflows/charts-hermes-lint.yml) | PR / push under `hermes-agent/**` | `shellcheck`, `helm lint --strict` (every overlay), `helm template`, `kubeconform`, `helm-unittest`, a guardrails job that asserts weak configurations are still refused, `trivy config` (fails on HIGH/CRITICAL), a check that the pinned image digest still resolves, and `helm install --dry-run=server` on Kind across K8s 1.27 / 1.29 / 1.31. |
| [`charts-hermes-sync.yml`](.github/workflows/charts-hermes-sync.yml) | Daily `47 6 * * *` cron + `workflow_dispatch` | Runs `scripts/sync-image-digest.sh hermes-agent latest`, bumps the chart patch version and opens a rolling PR. Labels the PR `needs-review,security` when the pinned **tag moved** rather than a new release appearing. |
| [`charts-publish.yml`](.github/workflows/charts-publish.yml) | Push to `main` (chart paths) + `workflow_dispatch` | `helm package` + `helm push` each chart to `oci://ghcr.io/ankraio/ankra-charts/<chart>:<version>`, then sign it with cosign (keyless) and attach an SPDX SBOM attestation. |
| [`charts-pages.yml`](.github/workflows/charts-pages.yml) | Push to `main` (chart paths) + `workflow_dispatch` | `helm package` each chart and publish `index.yaml` + `.tgz` + a cosign bundle per package to the `gh-pages` branch (the `helm repo add` HTTP repo; auto-tracked by ArtifactHub). |
| [`charts-artifacthub-verify.yml`](.github/workflows/charts-artifacthub-verify.yml) | Hourly cron + after each `charts-pages` run + `workflow_dispatch` | Checks that the Helm repo is registered on Artifact Hub and that every version in the published `index.yaml` is actually listed there. Needs no credentials. |
| [`secret-scan.yml`](.github/workflows/secret-scan.yml) | Every PR / push to `main` + weekly cron + `workflow_dispatch` | Scans the full git history and working tree for committed secrets with the pinned [`gitleaks`](https://github.com/gitleaks/gitleaks) binary. Config: [`.gitleaks.toml`](.gitleaks.toml); false positives: [`.gitleaksignore`](.gitleaksignore). |

## Publishing to Artifact Hub

Publishing is pull-based. Artifact Hub is pointed at the GitHub Pages Helm repo
**once**, and from then on it re-reads `index.yaml` roughly every 30 minutes and
lists every new chart version by itself. `charts-pages` regenerates that
`index.yaml` on every chart change, so once the repository is registered there is
no per-chart and no per-release step: bump `version:` in a chart's `Chart.yaml`,
merge to `main`, and the new version appears on Artifact Hub on its own.

A new top-level chart directory is discovered automatically by
`scripts/discover-charts.sh` and needs no Artifact Hub UI step of its own.

### Registration (already done)

The single Artifact Hub repository entry covers every chart and **is already
registered** — there is nothing to do for a new chart or a new release:

| | |
|---|---|
| Organization | `ankra` |
| Name | `ankra-charts` |
| URL | `https://ankraio.github.io/ankra-charts` |
| Repository ID | `960356cc-6378-4f2d-a55f-429fbab4cc92` |

That ID is recorded in [`.github/artifacthub-repo.yml`](.github/artifacthub-repo.yml)
and served from `gh-pages` at
[`/artifacthub-repo.yml`](https://ankraio.github.io/ankra-charts/artifacthub-repo.yml),
which is what Artifact Hub reads to grant the Verified Publisher label. Keep it —
dropping it downgrades the listing.

The `ARTIFACTHUB_API_KEY_ID` / `ARTIFACTHUB_API_KEY_SECRET` secrets remain
**optional**. They only let `charts-pages` manage the repository entry over the
API (re-register it if deleted, re-claim ownership); publishing does not need
them. To set them up, create an authorization key under
[Artifact Hub → Control Panel → Authorization keys](https://artifacthub.io/control-panel/authorization-keys)
as a member of the `ankra` organization, then:

```bash
gh secret set ARTIFACTHUB_API_KEY_ID -R ankraio/ankra-charts
gh secret set ARTIFACTHUB_API_KEY_SECRET -R ankraio/ankra-charts
```

If the entry is ever deleted, re-add it at Artifact Hub → Control Panel →
Repositories → Add with the values in the table above. Until it exists, charts
still publish to the Pages Helm repo and to GHCR but are **not listed on
Artifact Hub**, and `charts-pages` says so in its job summary rather than
passing silently.

### Verification

Artifact Hub drops a version it dislikes (a malformed annotation is enough)
without failing anything on the publishing side, and then refuses to reprocess
it until the `index.yaml` digest changes — so a chart can stay unlisted
indefinitely while every workflow here is green.
[`charts-artifacthub-verify.yml`](.github/workflows/charts-artifacthub-verify.yml)
closes that loop: hourly, and after each `charts-pages` run, it checks that the
repository is registered and that every version in the published `index.yaml` is
actually live on Artifact Hub, failing loudly when one is missing. It needs no
credentials and can be run locally:

```bash
bash scripts/artifacthub-verify.sh
```

The sync script (`scripts/sync-upstream.sh`) is idempotent - re-running it
with the same upstream version produces zero git diff. Exit codes:

| Code | Meaning |
|---|---|
| 0 | Success - tag-only diff (safe to auto-merge). |
| 1 | Error. |
| 2 | Success - structural change in vendored YAML; needs human review. |

## Local development

```bash
# Quick status - what versions are upstream vs vendored?
./scripts/sync-upstream.sh check

# Render charts.
helm template ccm ./upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=ci-test \
  --set credentials.username=u --set credentials.password=p
helm template csi ./upcloud-csi -n kube-system
helm template cf ./cloudflare-operator -n cloudflare-operator-system
helm template psono ./psono -n psono \
  --set base_url=https://psono.example.com --set domain=example.com

# Run helm-unittest suites.
helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.2
helm unittest upcloud-ccm
helm unittest upcloud-csi
helm unittest cloudflare-operator
helm unittest digitalocean-ccm
helm unittest digitalocean-csi
helm unittest psono
helm unittest hermes-agent

# Sync a chart to a specific upstream version.
./scripts/sync-upstream.sh csi v1.5.0
./scripts/sync-upstream.sh ccm v1.2.3
./scripts/sync-upstream.sh cloudflare v0.13.1
./scripts/sync-upstream.sh do-ccm v0.1.67
./scripts/sync-upstream.sh do-csi v4.17.0

# Re-pin the hermes-agent image digest (check | <tag> | latest).
./scripts/sync-image-digest.sh hermes-agent check
./scripts/sync-image-digest.sh hermes-agent latest

# Or simply `make test` from this repo root.
make test

# Scan for committed secrets (needs gitleaks: https://github.com/gitleaks/gitleaks).
make secret-scan
```

## Layout

```
ankra-charts/                        (this repo root)
├── README.md
├── Makefile
├── .github/workflows/               (GitHub Actions - must live here)
├── scripts/sync-upstream.sh
├── scripts/sync-image-digest.sh
├── hermes-agent/                    (hand-written, image digest synced daily)
├── upcloud-ccm/
├── upcloud-csi/
├── cloudflare-operator/
├── digitalocean-ccm/
├── digitalocean-csi/
└── psono/                           (hand-written, no upstream sync)
```

## License

Apache-2.0, matching the upstream projects.
