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
helm install upcloud-ccm ./charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# 2. UpCloud CSI (reuses the CCM Secret by default)
helm install upcloud-csi ./charts/upcloud-csi -n kube-system \
  --set storageClasses.defaultClass=maxiops

# 3. Cloudflare operator (assumes cert-manager + cloudflare-secrets exist)
helm install cloudflare-operator ./charts/cloudflare-operator \
  -n cloudflare-operator-system --create-namespace \
  -f ./charts/cloudflare-operator/values-examples/minimal.yaml
```

## Automation

GitHub Actions workflows under `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| [`charts-upcloud-sync.yml`](../.github/workflows/charts-upcloud-sync.yml) | Daily `17 6 * * *` cron + `workflow_dispatch` | Runs `scripts/sync-upstream.sh` for both UpCloud charts and opens a rolling PR. |
| [`charts-upcloud-lint.yml`](../.github/workflows/charts-upcloud-lint.yml) | PR / push under `charts/upcloud-{ccm,csi}/**` | `helm lint`, `helm template`, `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31. |
| [`charts-cloudflare-operator-sync.yml`](../.github/workflows/charts-cloudflare-operator-sync.yml) | Daily `27 6 * * *` cron + `workflow_dispatch` | Re-vendors upstream `cloudflare-operator.{crds,}yaml`, re-splits CRDs, bumps `appVersion`, opens a rolling PR. |
| [`charts-cloudflare-operator-lint.yml`](../.github/workflows/charts-cloudflare-operator-lint.yml) | PR / push under `charts/cloudflare-operator/**` | `shellcheck`, `helm lint`, `helm template` (4 overlays), `kubeconform`, `helm-unittest`, `ct install` on Kind across K8s 1.27 / 1.29 / 1.31 (cert-manager pre-installed). |

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
./charts/scripts/sync-upstream.sh check

# Render charts.
helm template ccm ./charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=ci-test \
  --set credentials.username=u --set credentials.password=p
helm template csi ./charts/upcloud-csi -n kube-system
helm template cf ./charts/cloudflare-operator -n cloudflare-operator-system

# Run helm-unittest suites.
helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.2
helm unittest charts/upcloud-ccm
helm unittest charts/upcloud-csi
helm unittest charts/cloudflare-operator

# Sync a chart to a specific upstream version.
./charts/scripts/sync-upstream.sh csi v1.5.0
./charts/scripts/sync-upstream.sh ccm v1.2.3
./charts/scripts/sync-upstream.sh cloudflare v0.13.1

# Or simply `make` everything from the repo root.
make -C charts test
```

## Layout

```
charts/
├── README.md                      (this file)
├── Makefile                       (developer convenience)
├── scripts/
│   └── sync-upstream.sh           (idempotent sync + tag/digest extraction)
├── upcloud-ccm/
│   ├── Chart.yaml                 (apiVersion v2, kubeVersion >=1.27)
│   ├── values.yaml                (Bitnami-pattern image overrides)
│   ├── values.schema.json
│   ├── README.md, CHANGELOG.md
│   ├── templates/                 (Deployment, ConfigMap, Secret, SA, CRB, PDB, …)
│   ├── tests/                     (helm-unittest)
│   └── values-examples/{minimal,production,air-gapped}.yaml
├── upcloud-csi/
│   ├── Chart.yaml                 (apiVersion v2, appVersion v1.4.0)
│   ├── values.yaml                (per-image overrides for every sidecar)
│   ├── values.schema.json
│   ├── README.md, CHANGELOG.md
│   ├── crds/                      (Helm 3 install-once; resource-policy: keep)
│   ├── templates/                 (CSIDriver, controller STS, snapshot-controller, node DS, SCs, …)
│   ├── tests/                     (helm-unittest)
│   ├── vendor/                    (raw upstream YAML kept for diffing; not packaged)
│   └── values-examples/{minimal,production,air-gapped}.yaml
└── cloudflare-operator/
    ├── Chart.yaml                 (apiVersion v2, appVersion 0.13.1, kubeVersion >=1.27)
    ├── values.yaml                (Bitnami-pattern, credentials reuse, sample CRs)
    ├── values.schema.json
    ├── README.md, CHANGELOG.md
    ├── templates/                 (CRDs, Deployment, RBAC, webhook cert/Service, metrics, NetworkPolicy, sample CRs)
    ├── tests/                     (helm-unittest)
    ├── vendor/                    (raw upstream YAML — install + CRDs — kept for diffing; not packaged)
    └── values-examples/{minimal,production,air-gapped}.yaml
```

## License

Apache-2.0, matching the upstream projects.
