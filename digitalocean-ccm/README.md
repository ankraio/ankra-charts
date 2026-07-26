# digitalocean-ccm

DigitalOcean Cloud Controller Manager (CCM) packaged as a Helm chart.

Upstream ships raw release manifests only (no Helm chart); this chart vendors
[`digitalocean/digitalocean-cloud-controller-manager`](https://github.com/digitalocean/digitalocean-cloud-controller-manager)
release manifests under `vendor/` and templates them with the conventions used
across the ankra-charts repository.

The CCM:

- provisions DigitalOcean Load Balancers for `Service type=LoadBalancer`,
- keeps node addresses, provider IDs, and region/zone labels in sync,
- clears the `node.cloudprovider.kubernetes.io/uninitialized` taint that
  kubelets started with `--cloud-provider=external` apply.

## Requirements

- Kubernetes >= 1.27 running on DigitalOcean Droplets (K3s with
  `--disable-cloud-controller` or vanilla kubeadm with
  `--cloud-provider=external`).
- A DigitalOcean API token with read/write scope.

## Install

```bash
helm install digitalocean-ccm oci://ghcr.io/ankraio/ankra-charts/digitalocean-ccm \
  --version 0.1.0 -n kube-system \
  --set credentials.token="$DIGITALOCEAN_ACCESS_TOKEN"
```

Reusing an existing Secret (the upstream convention is a Secret named
`digitalocean` in `kube-system` with the token under the `access-token` key,
shared with the `digitalocean-csi` chart):

```bash
helm install digitalocean-ccm oci://ghcr.io/ankraio/ankra-charts/digitalocean-ccm \
  --version 0.1.0 -n kube-system \
  --set credentials.create=false \
  --set credentials.existingSecret=digitalocean
```

## Key values

| Value | Default | Description |
|---|---|---|
| `credentials.create` | `true` | Render a Secret from `credentials.token`. |
| `credentials.existingSecret` | `""` | Use an externally-managed Secret instead. |
| `credentials.tokenKey` | `access-token` | Secret key holding the API token. |
| `region` | `""` | Region slug exported as `REGION`; empty relies on the droplet metadata service. |
| `vpcID` | `""` | Cluster VPC UUID exported as `DO_CLUSTER_VPC_ID`; required for LoadBalancers on custom-VPC clusters. |
| `replicaCount` | `1` | Upstream default. Set `leaderElect=true` before raising. |
| `leaderElect` | `false` | Kubernetes leader election. |
| `nodeSelector` | `{}` | Exact-match pin. Prefer `affinity` with `node-role.kubernetes.io/control-plane` `Exists` so kubeadm (`""`) and k3s (`"true"`) both match. |
| `images.ccm.digest` | `""` | Optional digest pin, takes precedence over the tag. |

See [values.yaml](values.yaml) for the full surface.

## Upgrades

`./scripts/sync-upstream.sh do-ccm [version]` re-vendors the upstream release
manifest, bumps `appVersion`, and pins the image digest. The
`charts-digitalocean-sync` workflow runs it daily and opens a rolling PR.

## License

Apache-2.0, matching upstream.
