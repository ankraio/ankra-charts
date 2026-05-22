# upcloud-charts

Helm charts that bring [UpCloud](https://upcloud.com/) infrastructure to a
Kubernetes (typically K3s) cluster.

| Chart | Description | Source of truth |
|---|---|---|
| [`upcloud-ccm`](upcloud-ccm/README.md) | UpCloud Cloud Controller Manager — provisions LoadBalancers, manages node labels, clears the `uninitialized` cloud-provider taint. | Hand-written from UpCloud docs; image `ghcr.io/upcloudltd/cloud-controller-manager`. |
| [`upcloud-csi`](upcloud-csi/README.md) | UpCloud CSI block-storage driver — controller StatefulSet, snapshot-controller, node DaemonSet, three StorageClasses. | Vendored from upstream [`UpCloudLtd/upcloud-csi`](https://github.com/UpCloudLtd/upcloud-csi) v1.4.0 manifests; auto-bumped daily by the sync workflow. |

## Recommended install order

1. **`upcloud-ccm`** first — it creates the shared
   `<release>-credentials` Secret used by both charts.
2. **`upcloud-csi`** second — defaults to reusing the CCM-created Secret.

```bash
# 1. CCM
helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"

# 2. CSI (reuses the CCM Secret by default)
helm install upcloud-csi ./upcloud-charts/upcloud-csi -n kube-system \
  --set storageClasses.defaultClass=maxiops
```

## Automation

Two GitHub Actions workflows live under `.github/workflows/`:

| Workflow | Trigger | What it does |
|---|---|---|
| [`upcloud-charts-sync.yml`](../.github/workflows/upcloud-charts-sync.yml) | Daily cron `17 6 * * *` (+ manual `workflow_dispatch`) | Runs `scripts/sync-upstream.sh` for both charts, opens a rolling PR `chore/upcloud-charts-sync` whenever upstream releases something new. Labels the PR `needs-review` if a structural (non-tag) diff is detected. |
| [`upcloud-charts-lint.yml`](../.github/workflows/upcloud-charts-lint.yml) | PR / push to `main` under `upcloud-charts/**` | `helm lint`, `helm template`, `kubeconform --strict`, `helm-unittest`, plus `chart-testing install` on kind across K8s 1.27 / 1.29 / 1.31. |

The sync script (`scripts/sync-upstream.sh`) is idempotent — re-running it
with the same upstream version produces zero git diff. Exit codes:

| Code | Meaning |
|---|---|
| 0 | Success — tag-only diff (safe to auto-merge). |
| 1 | Error. |
| 2 | Success — structural change in vendored YAML; needs human review. |

## Local development

```bash
# Render both charts (CCM requires clusterID + credentials).
helm template ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=ci-test \
  --set credentials.username=u --set credentials.password=p

helm template csi ./upcloud-charts/upcloud-csi -n kube-system

# Run helm-unittest suites.
helm plugin install https://github.com/helm-unittest/helm-unittest --version v0.5.2
helm unittest upcloud-charts/upcloud-ccm
helm unittest upcloud-charts/upcloud-csi

# Sync to a specific upstream version.
./upcloud-charts/scripts/sync-upstream.sh csi v1.5.0
./upcloud-charts/scripts/sync-upstream.sh ccm v1.2.3

# Check what versions upstream has now.
./upcloud-charts/scripts/sync-upstream.sh check
```

## Layout

```
upcloud-charts/
├── README.md                  (this file)
├── scripts/
│   └── sync-upstream.sh       (idempotent sync + tag/digest extraction)
├── upcloud-ccm/
│   ├── Chart.yaml             (apiVersion v2, kubeVersion >=1.27)
│   ├── values.yaml            (Bitnami-pattern image overrides)
│   ├── values.schema.json     (schema enforces clusterID + credentials shape)
│   ├── README.md
│   ├── CHANGELOG.md
│   ├── templates/             (Deployment, ConfigMap, Secret, SA, CRB, PDB, …)
│   ├── tests/                 (helm-unittest suites)
│   └── values-examples/{minimal,production,air-gapped}.yaml
└── upcloud-csi/
    ├── Chart.yaml             (apiVersion v2, appVersion v1.4.0, kubeVersion >=1.27)
    ├── values.yaml            (per-image overrides for every sidecar)
    ├── values.schema.json     (schema enforces defaultClass enum, credentials shape)
    ├── README.md
    ├── CHANGELOG.md
    ├── crds/                  (Helm 3 install-once; resource-policy: keep)
    ├── templates/             (CSIDriver, controller STS, snapshot-controller, node DS, SCs, …)
    ├── tests/                 (helm-unittest suites)
    ├── vendor/                (raw upstream YAML kept for diffing; not packaged)
    └── values-examples/{minimal,production,air-gapped}.yaml
```

## License

Apache-2.0, matching the upstream UpCloud projects.
