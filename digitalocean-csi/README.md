# digitalocean-csi

DigitalOcean CSI block-storage driver packaged as a Helm chart.

Upstream ships raw release manifests only (no Helm chart); this chart vendors
[`digitalocean/csi-digitalocean`](https://github.com/digitalocean/csi-digitalocean)
release manifests (`crds.yaml`, `driver.yaml`, `snapshot-controller.yaml`)
under `vendor/` and templates them with the conventions used across the
ankra-charts repository.

The chart ships:

- the controller StatefulSet (provisioner, attacher, snapshotter, resizer
  sidecars plus the DO plugin),
- the node DaemonSet (driver registrar + privileged plugin, with the
  automount-udev-rule deleter init container),
- the external snapshot-controller and the three
  `snapshot.storage.k8s.io` CRDs (under `crds/`, installed once by Helm),
- the four upstream `do-block-storage*` StorageClasses and the default
  VolumeSnapshotClass.

## Requirements

- Kubernetes >= 1.27 running on DigitalOcean Droplets.
- A DigitalOcean API token with read/write scope.

## Install

```bash
helm install digitalocean-csi oci://ghcr.io/ankraio/ankra-charts/digitalocean-csi \
  --version 0.1.0 -n kube-system \
  --set credentials.token="$DIGITALOCEAN_ACCESS_TOKEN"
```

Reusing an existing Secret (the upstream convention is a Secret named
`digitalocean` in `kube-system` with the token under the `access-token` key,
shared with the `digitalocean-ccm` chart):

```bash
helm install digitalocean-csi oci://ghcr.io/ankraio/ankra-charts/digitalocean-csi \
  --version 0.1.0 -n kube-system \
  --set credentials.create=false \
  --set credentials.existingSecret=digitalocean
```

## Key values

| Value | Default | Description |
|---|---|---|
| `credentials.create` | `true` | Render a Secret from `credentials.token`. |
| `credentials.existingSecret` | `""` | Use an externally-managed Secret instead. |
| `controller.nodeSelector` | `{}` | Exact-match pin. Prefer `controller.affinity` with control-plane label `Exists` for kubeadm+k3s. |
| `storageClasses.defaultClass` | `do-block-storage` | Which class carries the default-class annotation. |
| `snapshotController.enabled` | `true` | Disable when the cluster already runs an external snapshot-controller. |
| `node.kubeletDir` | `/var/lib/kubelet` | Kubelet data dir for non-standard distributions. |
| `images.csiDriver.digest` | `""` | Optional digest pin, takes precedence over the tag. |

See [values.yaml](values.yaml) for the full surface.

## Upgrades

`./scripts/sync-upstream.sh do-csi [version]` re-vendors the upstream release
manifests, bumps `appVersion`, re-splits the CRDs, and syncs the sidecar image
tags. The `charts-digitalocean-sync` workflow runs it daily and opens a
rolling PR.

## License

Apache-2.0, matching upstream.
