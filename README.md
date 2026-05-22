# charts

In-tree Helm charts maintained by the Ankra platform team.

| Chart | Description | Source of truth |
|---|---|---|
| [`upcloud-ccm`](upcloud-ccm/README.md) | UpCloud Cloud Controller Manager — provisions LoadBalancers, manages node labels, clears the `uninitialized` cloud-provider taint. | Hand-written from UpCloud docs; image `ghcr.io/upcloudltd/cloud-controller-manager`. |
| [`upcloud-csi`](upcloud-csi/README.md) | UpCloud CSI block-storage driver — controller StatefulSet, snapshot-controller, node DaemonSet, three StorageClasses. | Vendored from upstream [`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi); auto-bumped daily. |
| [`cloudflare-operator`](cloudflare-operator/README.md) | Cloudflare Tunnel operator (Tunnel / ClusterTunnel / TunnelBinding / AccessTunnel CRDs) — plus optional `ClusterOriginIssuer` for the cert-manager Origin CA external issuer. | Vendored from upstream [`adyanth/cloudflare-operator`](https://github.com/adyanth/cloudflare-operator); auto-bumped daily. |

## Recommended install order

1. **`upcloud-ccm`** first (on UpCloud-backed clusters) — it creates the
   shared `<release>-credentials` Secret used by both UpCloud charts.
2. **`upcloud-csi`** second — defaults to reusing the CCM-created Secret.
3. **`cloudflare-operator`** independently — requires only cert-manager and
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
```

## Automation

GitHub Actions workflows under `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| [`charts-upcloud-sync.yml`](.github/workflows/charts-upcloud-sync.yml) | Daily `17 6 * * *` cron + `workflow_dispatch` | Runs `scripts/sync-upstream.sh` for both UpCloud charts and opens a rolling PR. |
| [`charts-upcloud-lint.yml`](.github/workflows/charts-upcloud-lint.yml) | PR / push under `upcloud-{ccm,csi}/**` | `helm lint`, `helm template`, `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31. |
| [`charts-cloudflare-operator-sync.yml`](.github/workflows/charts-cloudflare-operator-sync.yml) | Daily `27 6 * * *` cron + `workflow_dispatch` | Re-vendors upstream `cloudflare-operator.{crds,}yaml`, re-splits CRDs, bumps `appVersion`, opens a rolling PR. |
| [`charts-cloudflare-operator-lint.yml`](.github/workflows/charts-cloudflare-operator-lint.yml) | PR / push under `cloudflare-operator/**` | `shellcheck`, `helm lint`, `helm template` (4 overlays), `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31 (cert-manager pre-installed). |

The sync script (`scripts/sync-upstream.sh`) is idempotent — re-running it
with the same upstream version produces zero git diff. Exit codes:

| Code | Meaning |
|---|---|
| 0 | Success — tag-only diff (safe to auto-merge). |
| 1 | Error. |
| 2 | Success — structural change in vendored YAML; needs human review. |

## Local development

```bash
# Quick status — what versions are upstream vs vendored?
./scripts/sync-upstream.sh check

# Render charts.
helm template ccm ./upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=ci-test \
  --set credentials.username=u --set credentials.password=p
helm template csi ./upcloud-csi -n kube-system
helm template cf ./cloudflare-operator -n cloudflare-operator-system

# Run helm-unittest suites.
helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.2
helm unittest upcloud-ccm
helm unittest upcloud-csi
helm unittest cloudflare-operator

# Sync a chart to a specific upstream version.
./scripts/sync-upstream.sh csi v1.5.0
./scripts/sync-upstream.sh ccm v1.2.3
./scripts/sync-upstream.sh cloudflare v0.13.1

# Or simply `make test` from this repo root.
make test
```

## Layout

```
ankra-charts/                        (this repo root)
├── README.md
├── Makefile
├── .github/workflows/               (GitHub Actions — must live here)
├── scripts/sync-upstream.sh
├── upcloud-ccm/
├── upcloud-csi/
└── cloudflare-operator/
```

## License

Apache-2.0, matching the upstream projects.
