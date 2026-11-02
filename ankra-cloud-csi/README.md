# ankra-cloud-csi

The Kubernetes CSI driver `csi.ankra.cloud` for [Ankra Cloud](https://cloud.ankra.app) block storage. Clusters running
on Ankra Cloud servers get persistent volumes backed by Ankra Cloud storages: dynamic provisioning per storage tier,
hot-plug attach and detach, online expansion, snapshots, restore from a snapshot and clones. The driver talks only to
the public Ankra Cloud API, with a customer API token.

The driver is in preview. Full documentation: <https://cloud.ankra.app/docs/kubernetes-csi>.

Source of truth: [github.com/ankraio/ankra-cloud-csi](https://github.com/ankraio/ankra-cloud-csi) (`charts/ankra-cloud-csi`). This directory is
a copy made for each release; change the chart there, not here.

## Install

```bash
helm repo add ankra https://ankraio.github.io/ankra-charts
helm repo update
helm install ankra-cloud-csi ankra/ankra-cloud-csi -n kube-system --set api.token=<token>
```

`<token>` is an Ankra Cloud API token whose user can operate storages (**Settings → API tokens** in the console). For production,
keep the token out of Helm values and point the chart at a Secret you manage:

```bash
kubectl -n kube-system create secret generic ankra-cloud-csi-api --from-literal=token=<token>
helm install ankra-cloud-csi ankra/ankra-cloud-csi -n kube-system --set api.existingSecret=ankra-cloud-csi-api
```

The chart is also published as an OCI artifact:

```bash
helm install ankra-cloud-csi oci://share.ankra.cloud/charts/ankra-cloud-csi --version 0.3.0 -n kube-system \
  --set api.existingSecret=ankra-cloud-csi-api
```

Or apply the rendered manifests (create the Secret above first):

```bash
kubectl apply -f https://raw.githubusercontent.com/ankraio/ankra-cloud-csi/main/deploy/ankra-cloud-csi.yaml
# Needs the snapshot CRDs and snapshot-controller (github.com/kubernetes-csi/external-snapshotter):
kubectl apply -f https://raw.githubusercontent.com/ankraio/ankra-cloud-csi/main/deploy/volumesnapshotclass.yaml
```

Then claim a volume:

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: data
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ankra-default
  resources:
    requests:
      storage: 10Gi
```

## Storage capacity

With `capacity.enabled` (the default) the controller publishes a `CSIStorageCapacity` for every node and StorageClass,
and the scheduler binds a `WaitForFirstConsumer` claim only to a node whose capacity fits it. For `local-nvme` (and
`ankra-default` in a zone whose default tier is `local-nvme`) it is what the Ankra Local pool of the node's compute
node still takes, by the same rule that refuses a volume with `409 the node's Ankra Local pool takes no new volumes`.
Other tiers report the largest volume the API takes. Several servers can share one compute node's pool and each
reports the whole room, so a burst of claims can still overrun it; the API then refuses the extra volume and the claim
is retried. See the [source README](https://github.com/ankraio/ankra-cloud-csi#storage-capacity) for the details.

## Values

| Value | Default | Description |
| --- | --- | --- |
| `api.url` | `https://cloud.ankra.app` | The Ankra Cloud API's base URL. |
| `api.existingSecret` | `""` | A Secret holding the API token. The chart creates one from `api.token` when empty. |
| `api.existingSecretKey` | `token` | The key of the token in the Secret. |
| `api.token` | `""` | An API token. Prefer `api.existingSecret`. |
| `api.caBundle.existingSecret` | `""` | A Secret with a PEM CA bundle for a privately signed API certificate. |
| `api.caBundle.key` | `ca.crt` | The key of the bundle in that Secret. |
| `defaultZone` | `""` | Zone of volumes created without a topology; empty reads the controller's own zone. |
| `image.repository` | `share.ankra.cloud/library/ankra-cloud-csi` | The driver image (linux/amd64, linux/arm64). |
| `image.tag` | the chart's `appVersion` | An immutable tag: `v<semver>` or `sha-<commit>`. |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | |
| `sidecars.*.image` | pinned | The Kubernetes CSI sidecars. Upgrade them together with the chart. |
| `controller.replicas` | `1` | |
| `controller.operationTimeout` | `5m` | How long one CSI call waits for an API operation. |
| `controller.sidecarTimeout` | `6m` | The sidecars' per-call timeout; above `operationTimeout` so the driver answers first. |
| `controller.resources`, `.nodeSelector`, `.tolerations`, `.affinity`, `.priorityClassName` | see `values.yaml` | Scheduling of the controller. |
| `capacity.enabled` | `true` | Storage capacity tracking: the CSIDriver's `storageCapacity` and external-provisioner's `--enable-capacity`. |
| `capacity.pollInterval` | `30s` | How often external-provisioner asks the driver for every node's capacity again. |
| `capacity.cacheTTL` | `10s` | How long one API read of a node's capacity answers its StorageClasses; keep it below `pollInterval`. |
| `node.kubeletDir` | `/var/lib/kubelet` | The kubelet's root directory. |
| `node.maxVolumesPerNode` | `15` | Volumes one server can attach: 16 storage devices less its boot storage. |
| `node.resources`, `.nodeSelector`, `.tolerations`, `.priorityClassName` | see `values.yaml` | Scheduling of the node plugin. |
| `storageClasses` | `ankra-default` (zone default tier, default class) and the four tiers | `name`, `tier` and `default` per StorageClass. |
| `storageClassDefaults.reclaimPolicy` | `Delete` | |
| `storageClassDefaults.allowVolumeExpansion` | `true` | |
| `storageClassDefaults.fsType` | `ext4` | `ext4` or `xfs`. |
| `volumeSnapshotClass.enabled` | `true` | Rendered only when the snapshot API is served. |
| `volumeSnapshotClass.name` | `ankra-snapshots` | |
| `volumeSnapshotClass.default` | `true` | |
| `volumeSnapshotClass.deletionPolicy` | `Delete` | |

The binary reads these environment variables, which the chart sets:

| Variable | |
| --- | --- |
| `ANKRA_CLOUD_API_URL` | The API's base URL. Required. |
| `ANKRA_CLOUD_TOKEN` | An API token that may operate storages. Required. |
| `ANKRA_CLOUD_CA_BUNDLE` | A PEM file of extra roots. Optional. |
| `ANKRA_CLOUD_ZONE` | The controller's default zone (`--default-zone`). Optional. |
| `ANKRA_CLOUD_SERVER_ID` | Skips the metadata service on the node (`--server-id`). Optional. |

## Links

- Source and issues: <https://github.com/ankraio/ankra-cloud-csi>
- Documentation: <https://cloud.ankra.app/docs/kubernetes-csi>
- Changelog: [CHANGELOG.md](CHANGELOG.md)
