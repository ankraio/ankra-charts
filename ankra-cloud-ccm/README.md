# ankra-cloud-ccm

The Kubernetes cloud controller manager for [Ankra Cloud](https://cloud.ankra.app): an out-of-tree
`k8s.io/cloud-provider` with the provider name `ankracloud`. It initialises nodes (providerID, addresses, instance
type, zone and region) and gives every Service of type LoadBalancer an Ankra Cloud load balancer. It talks only to the
public Ankra Cloud API, with an API token.

The controller is in preview. Full documentation: <https://cloud.ankra.app/docs/kubernetes-ccm>.

Source of truth: [github.com/ankraio/ankra-cloud-ccm](https://github.com/ankraio/ankra-cloud-ccm) (`charts/ankra-cloud-ccm`). This directory is
a copy made for each release; change the chart there, not here.

## Install

Every kubelet must run with `--cloud-provider=external` (on k3s: `--disable-cloud-controller` on the servers and
`--kubelet-arg=cloud-provider=external` on every node). New nodes keep the
`node.cloudprovider.kubernetes.io/uninitialized` taint until the controller has initialised them.

```bash
helm repo add ankra https://ankraio.github.io/ankra-charts
helm repo update
helm install ankra-cloud-ccm ankra/ankra-cloud-ccm -n kube-system --set api.token=<token>
```

`<token>` is an Ankra Cloud API token with operate permission (**Settings → API tokens** in the console). For
production, keep the token out of Helm values, name the cluster (it labels every load balancer and must be unique per
account), and put load balancers on your private network:

```bash
kubectl -n kube-system create secret generic ankra-cloud-ccm --from-literal=token=<token>
helm install ankra-cloud-ccm ankra/ankra-cloud-ccm -n kube-system \
  --set api.existingSecret=ankra-cloud-ccm --set clusterName=production --set loadBalancer.networkID=<network-id>
```

The chart is also published as an OCI artifact:

```bash
helm install ankra-cloud-ccm oci://share.ankra.cloud/charts/ankra-cloud-ccm --version 0.1.0 -n kube-system \
  --set api.existingSecret=ankra-cloud-ccm
```

Without Helm, create the Secret above and apply the rendered manifests:

```bash
kubectl apply -f https://raw.githubusercontent.com/ankraio/ankra-cloud-ccm/main/deploy/ankra-cloud-ccm.yaml
```

The chart runs a Deployment in `kube-system` with leader election (`--leader-elect`), the standard cloud controller
manager RBAC, host networking (the controller initialises nodes before any CNI is ready), and tolerations for the
uninitialized, control-plane and not-ready taints.

| Interface | Behaviour |
| --- | --- |
| InstancesV2 | Maps a node to a server by providerID `ankracloud://<zone>/<server-id>`, or by hostname (`list_servers?hostname=`) while the providerID is empty. |
| LoadBalancer | One Ankra load balancer per Service of type LoadBalancer, or the Service's members on a combined edge. |
| Routes, Zones, Clusters, Instances | Not implemented. The CNI routes pod traffic; InstancesV2 reports zone and region. |

## Values

| Value | Default | Description |
| --- | --- | --- |
| `api.url` | `https://cloud.ankra.app` | The Ankra Cloud API endpoint. |
| `api.existingSecret` | `""` | A Secret with the key `token` and optionally `ca.crt`. The chart creates one from `api.token` when empty. |
| `api.token` | `""` | Used only when `api.existingSecret` is empty. Prefer an existing Secret. |
| `api.caBundle` | `""` | PEM certificates to trust in addition to the system roots; used only when `api.existingSecret` is empty. |
| `api.existingSecretHasCABundle` | `false` | Set when `api.existingSecret` also holds `ca.crt`. |
| `clusterName` | `kubernetes` | Written on every load balancer as the `ccm.ankra.cloud/cluster` label; unique per account. |
| `loadBalancer.networkID` | `""` | Default private network for load balancers; the `load-balancer.ankra.cloud/network-id` annotation overrides it. |
| `loadBalancer.zone` | `""` | Default zone for load balancers; otherwise the nodes' zone. |
| `loadBalancer.highAvailability` | `auto` | `auto` asks the zone's capabilities; `true` or `false` forces it. |
| `image.repository` | `share.ankra.cloud/library/ankra-cloud-ccm` | The controller image (linux/amd64, linux/arm64). |
| `image.tag` | the chart's `appVersion` | An immutable tag: `v<semver>` or `sha-<commit>`. |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | |
| `replicas` | `1` | Two or more run as a leader-elected standby pair. |
| `extraArgs` | `[]` | Additional flags for the controller manager. |
| `logVerbosity` | `2` | klog verbosity. |
| `resources` | see `values.yaml` | |
| `hostNetwork` | `true` | The controller runs before any CNI is ready. |
| `priorityClassName` | `system-cluster-critical` | |
| `nodeSelector`, `affinity`, `tolerations` | see `values.yaml` | Prefers control-plane nodes and tolerates the uninitialized taint. |
| `podSecurityContext`, `securityContext` | non-root, read-only root file system | |

## Links

- Source and issues: <https://github.com/ankraio/ankra-cloud-ccm>
- Documentation: <https://cloud.ankra.app/docs/kubernetes-ccm>
- Changelog: [CHANGELOG.md](CHANGELOG.md)
