# charts

In-tree Helm charts maintained by the Ankra platform team.

| Chart | Description | Source of truth |
|---|---|---|
| [`upcloud-ccm`](upcloud-ccm/README.md) | UpCloud Cloud Controller Manager — provisions LoadBalancers, manages node labels, clears the `uninitialized` cloud-provider taint. | Hand-written from UpCloud docs; image `ghcr.io/upcloudltd/cloud-controller-manager`. |
| [`upcloud-csi`](upcloud-csi/README.md) | UpCloud CSI block-storage driver — controller StatefulSet, snapshot-controller, node DaemonSet, three StorageClasses. | Vendored from upstream [`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi); auto-bumped daily. |
| [`cloudflare-operator`](cloudflare-operator/README.md) | Cloudflare Tunnel operator (Tunnel / ClusterTunnel / TunnelBinding / AccessTunnel CRDs) — plus optional `ClusterOriginIssuer` for the cert-manager Origin CA external issuer. | Vendored from upstream [`adyanth/cloudflare-operator`](https://github.com/adyanth/cloudflare-operator); auto-bumped daily. |
| [`digitalocean-ccm`](digitalocean-ccm/README.md) | DigitalOcean Cloud Controller Manager - provisions DO Load Balancers, manages node lifecycle, clears the `uninitialized` cloud-provider taint. | Vendored from upstream [`digitalocean/digitalocean-cloud-controller-manager`](https://github.com/digitalocean/digitalocean-cloud-controller-manager) release manifests (no upstream chart exists); auto-bumped daily. |
| [`digitalocean-csi`](digitalocean-csi/README.md) | DigitalOcean CSI block-storage driver - controller StatefulSet, node DaemonSet, snapshot-controller, snapshot CRDs, four `do-block-storage*` StorageClasses. | Vendored from upstream [`digitalocean/csi-digitalocean`](https://github.com/digitalocean/csi-digitalocean) release manifests (no upstream chart exists); auto-bumped daily. |
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
| [`charts-publish.yml`](.github/workflows/charts-publish.yml) | Push to `main` (chart paths) + `workflow_dispatch` | `helm package` + `helm push` each chart to `oci://ghcr.io/ankraio/ankra-charts/<chart>:<version>`. |
| [`charts-pages.yml`](.github/workflows/charts-pages.yml) | Push to `main` (chart paths) + `workflow_dispatch` | `helm package` each chart and publish `index.yaml` + `.tgz` to the `gh-pages` branch (the `helm repo add` HTTP repo; auto-tracked by ArtifactHub). |
| [`secret-scan.yml`](.github/workflows/secret-scan.yml) | Every PR / push to `main` + weekly cron + `workflow_dispatch` | Scans the full git history and working tree for committed secrets with the pinned [`gitleaks`](https://github.com/gitleaks/gitleaks) binary. Config: [`.gitleaks.toml`](.gitleaks.toml); false positives: [`.gitleaksignore`](.gitleaksignore). |

### ArtifactHub (automated)

The `charts-pages` workflow discovers chart directories automatically and, when
these repository secrets are set, registers the GitHub Pages Helm repo on
ArtifactHub and keeps `artifacthub-repo.yml` in sync:

| Secret | Description |
|---|---|
| `ARTIFACTHUB_API_KEY_ID` | Authorization key ID from [ArtifactHub → Control Panel → Authorization keys](https://artifacthub.io/control-panel/authorization-keys) (create under your user account; org repos are managed via org permissions). |
| `ARTIFACTHUB_API_KEY_SECRET` | Matching secret shown once when the key is created. |

```bash
gh secret set ARTIFACTHUB_API_KEY_ID -R ankraio/ankra-charts
gh secret set ARTIFACTHUB_API_KEY_SECRET -R ankraio/ankra-charts
```

One ArtifactHub repository entry (`ankra/ankra-charts` → `https://ankraio.github.io/ankra-charts`) indexes every chart in the Helm repo. Adding a new top-level chart directory is picked up automatically - no manual ArtifactHub UI step per chart.

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

# Sync a chart to a specific upstream version.
./scripts/sync-upstream.sh csi v1.5.0
./scripts/sync-upstream.sh ccm v1.2.3
./scripts/sync-upstream.sh cloudflare v0.13.1
./scripts/sync-upstream.sh do-ccm v0.1.67
./scripts/sync-upstream.sh do-csi v4.17.0

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
├── upcloud-ccm/
├── upcloud-csi/
├── cloudflare-operator/
├── digitalocean-ccm/
├── digitalocean-csi/
└── psono/                           (hand-written, no upstream sync)
```

## License

Apache-2.0, matching the upstream projects.
