# upcloud-ccm

[![Helm chart](https://img.shields.io/badge/helm-chart-blue)](../README.md) ![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue)

UpCloud Cloud Controller Manager packaged as a Helm chart. Runs the upstream
`ghcr.io/upcloudltd/cloud-controller-manager` binary with leader election,
hardened pod security defaults, optional ServiceMonitor, and an opt-in
NetworkPolicy.

## TL;DR

```bash
# Generate a stable cluster ID once and pin it in your values file.
uuidgen

helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID="$(uuidgen)" \
  --set credentials.username="$UPCLOUD_USERNAME" \
  --set credentials.password="$UPCLOUD_PASSWORD"
```

Then annotate every node with its UpCloud VM and Private Network UUIDs (see
[NEXT STEPS](#next-steps) below). Without these annotations the CCM cannot
match Kubernetes nodes to UpCloud infrastructure.

## Requirements

| Requirement | Notes |
|---|---|
| Kubernetes | `>= 1.27` (enforced by `Chart.yaml`'s `kubeVersion`) |
| Cluster role | A `system:cloud-controller-manager` ClusterRole must exist. K3s ships it; vanilla Kubernetes does too. |
| Service account | K3s pre-creates `cloud-controller-manager` in `kube-system`. If you're not on K3s, set `serviceAccount.create=true` and `rbac.create=true`. |
| Credentials | UpCloud API username & password with Manage permission. |
| Cluster ID | A stable, unique string (UUID recommended). Required. |

## Install

### K3s (defaults work out of the box)

```bash
helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=<your-stable-uuid> \
  --set credentials.username=<upcloud-api-username> \
  --set credentials.password=<upcloud-api-password>
```

### Vanilla Kubernetes (create SA + RBAC yourself)

```bash
helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=<your-stable-uuid> \
  --set credentials.username=<upcloud-api-username> \
  --set credentials.password=<upcloud-api-password> \
  --set serviceAccount.create=true \
  --set rbac.create=true
```

### With an externally-managed Secret (e.g. External Secrets Operator)

```bash
helm install upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  --set ccmConfig.clusterID=<your-stable-uuid> \
  --set credentials.create=false \
  --set credentials.existingSecret=upcloud-api-credentials
```

## Next steps

1. **Annotate every node** with its UpCloud VM and Private Network UUID. The
   CCM uses these to match Kubernetes nodes to UpCloud infrastructure:

   ```bash
   kubectl annotate node <node-name> \
     infrastructure.cluster.x-k8s.io/upcloud-vm-uuid=<YOUR_UPCLOUD_VM_UUID>

   kubectl annotate node <node-name> \
     infrastructure.cluster.x-k8s.io/upcloud-vm-private-nw-uuid=<YOUR_UPCLOUD_PRIVATE_NETWORK_UUID>
   ```

   UUIDs are visible in the UpCloud Hub or via `upctl server list` /
   `upctl network list`.

2. **Verify** the deployment:

   ```bash
   kubectl -n kube-system rollout status deployment/upcloud-ccm
   kubectl -n kube-system logs -l app.kubernetes.io/name=upcloud-ccm --tail=50
   ```

3. **Test** by exposing a workload as `type: LoadBalancer`. The CCM will
   provision an UpCloud Managed Load Balancer (default plan: `development`)
   and surface its external IP back on the Service.

## Production checklist

The chart ships with sensible defaults for production, but verify these knobs
suit your environment:

- `replicaCount: 2` + `--leader-elect=true` for HA. Bump to 3 on large
  clusters and combine with the `production.yaml` example.
- `podDisruptionBudget.enabled: true` (`minAvailable: 1`).
- `topologySpreadConstraints` + soft pod anti-affinity spread replicas
  across nodes.
- Pod runs as nonroot (`runAsUser: 65532`), read-only root filesystem, all
  capabilities dropped, seccomp `RuntimeDefault`.
- `--profiling=false` and `--contention-profiling=false`.
- Liveness/readiness probes target the CCM secure `/healthz` over HTTPS.
- `metrics.serviceMonitor.enabled` exposes a Prometheus ServiceMonitor
  (requires the Prometheus Operator CRDs).
- `networkPolicy.enabled` (opt-in) restricts egress and ingress.

See [`values-examples/production.yaml`](values-examples/production.yaml) for
a complete production overlay.

## Air-gapped installs

Mirror the CCM image to your registry and override:

```yaml
global:
  imageRegistry: harbor.internal
images:
  ccm:
    repository: mirror/upcloudltd/cloud-controller-manager
    digest: sha256:<obtained via `crane digest ghcr.io/upcloudltd/cloud-controller-manager:<tag>`>
```

See [`values-examples/air-gapped.yaml`](values-examples/air-gapped.yaml).

## Sharing credentials with upcloud-csi

The companion [`upcloud-csi`](../upcloud-csi/README.md) chart needs the same
UpCloud API credentials. The cleanest pattern is:

1. Install `upcloud-ccm` first with `credentials.create=true`. It creates a
   Secret named `<release>-credentials`.
2. Install `upcloud-csi` with
   `credentials.existingSecret=<release>-credentials`.

## Uninstall

```bash
helm uninstall upcloud-ccm -n kube-system
```

Existing LoadBalancer Services will retain their UpCloud Managed Load
Balancers until the Service objects themselves are deleted.

## Upgrading

```bash
helm upgrade upcloud-ccm ./upcloud-charts/upcloud-ccm -n kube-system \
  -f my-values.yaml
```

Leader election + rolling update strategy (`maxUnavailable: 0`) keeps at
least one CCM replica serving throughout the upgrade.

## Configuration reference

A full table of values is below (kept in sync with `values.yaml` by
`helm-docs`).

<!-- helm-docs-values-table-start -->
See [`values.yaml`](values.yaml) for the full list of values. Key knobs:

| Key | Default | Description |
|---|---|---|
| `replicaCount` | `2` | Number of CCM replicas. |
| `ccmConfig.clusterID` | `""` (REQUIRED) | Stable cluster identifier. |
| `ccmConfig.clusterName` | `"my-k3s-cluster"` | Name surfaced in UpCloud Hub. |
| `ccmConfig.loadBalancerPlan` | `"development"` | Default plan for managed LBs. |
| `credentials.create` | `true` | Create a Secret from `username`/`password`. |
| `credentials.existingSecret` | `""` | Reference an externally-managed Secret. |
| `serviceAccount.create` | `false` | K3s ships its own SA. |
| `rbac.create` | `false` | K3s ships its own ClusterRoleBinding. |
| `images.ccm.registry` | `ghcr.io` | Overridden by `global.imageRegistry`. |
| `images.ccm.repository` | `upcloudltd/cloud-controller-manager` | |
| `images.ccm.tag` | `""` | Falls back to `.Chart.AppVersion`. |
| `images.ccm.digest` | `""` | sha256 digest; takes precedence over `tag`. |
| `metrics.serviceMonitor.enabled` | `false` | Opt-in Prometheus Operator integration. |
| `networkPolicy.enabled` | `false` | Opt-in NetworkPolicy. |
| `podDisruptionBudget.enabled` | `true` | Active when `replicaCount > 1`. |
<!-- helm-docs-values-table-end -->

## See also

- [upcloud-csi](../upcloud-csi/README.md) — block-storage CSI driver, installs alongside the CCM.
- UpCloud documentation: [Getting started with Kubernetes on UpCloud](https://upcloud.com/community/tutorials/getting-started-upcloud-kubernetes-services).
