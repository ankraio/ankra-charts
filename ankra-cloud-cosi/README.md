# ankra-cloud-cosi

The Kubernetes [COSI](https://github.com/kubernetes-sigs/container-object-storage-interface) driver `cosi.ankra.cloud`
for [Ankra Cloud](https://cloud.ankra.app) object storage. A `BucketClaim` gets an S3 bucket in an Ankra Cloud zone; a
`BucketAccess` gets a Secret with the S3 endpoint and a key for it. The driver talks only to the public Ankra Cloud
API, with a customer API token, and to the zone's S3 endpoint.

The driver is in preview: COSI's API (`objectstorage.k8s.io/v1alpha1`) is alpha.

Source of truth: [github.com/ankraio/ankra-cloud-csi](https://github.com/ankraio/ankra-cloud-csi)
(`charts/ankra-cloud-cosi`). This directory is a copy made for each release; change the chart there, not here.

## Install

1. The COSI CRDs and controller, release v0.2.2 (the `v1alpha1` API the driver and its pinned sidecar speak):

   ```bash
   kubectl apply -k 'https://github.com/ankraio/ankra-cloud-csi//deploy/cosi-controller?ref=main'
   kubectl -n container-object-storage-system rollout status deployment/container-object-storage-controller
   ```

2. The driver, with an API token whose user can operate object storage (**Settings → API tokens** in the console).
   It reads the token the same way as the `ankra-cloud-csi` chart, so one Secret serves both:

   ```bash
   helm repo add ankra https://ankraio.github.io/ankra-charts
   helm repo update
   kubectl -n kube-system create secret generic ankra-cloud-csi-api --from-literal=token=<token>
   helm install ankra-cloud-cosi ankra/ankra-cloud-cosi -n kube-system \
     --set api.existingSecret=ankra-cloud-csi-api --set bucketClass.zone=<zone>
   ```

The chart is also published as an OCI artifact:

```bash
helm install ankra-cloud-cosi oci://share.ankra.cloud/charts/ankra-cloud-cosi --version 0.1.0 -n kube-system \
  --set api.existingSecret=ankra-cloud-csi-api --set bucketClass.zone=<zone>
```

It runs one Deployment: the driver and the upstream `objectstorage-sidecar` (pinned by digest), with the RBAC the
sidecar needs. With `bucketClass.zone` set it creates the `ankra-objects` BucketClass, and it creates the
`ankra-objects-key` BucketAccessClass; both only when the cluster serves the COSI API.

## Claim a bucket

```yaml
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketClaim
metadata:
  name: uploads
spec:
  bucketClassName: ankra-objects
  protocols: ["S3"]
---
apiVersion: objectstorage.k8s.io/v1alpha1
kind: BucketAccess
metadata:
  name: uploads
spec:
  bucketClaimName: uploads
  bucketAccessClassName: ankra-objects-key
  credentialsSecretName: uploads-s3
  protocol: S3
```

The Secret `uploads-s3` holds one key, `BucketInfo`: a JSON document whose `spec.secretS3` has `endpoint`, `region`
(`us-east-1`), `accessKeyID` and `accessSecretKey`, and whose `spec.bucketName` is the bucket's name. Use path-style
addressing.

## Values

| Value | Default | What it sets |
| --- | --- | --- |
| `api.url` | `https://cloud.ankra.app` | The Ankra Cloud API. |
| `api.existingSecret` / `api.existingSecretKey` | `""` / `token` | A Secret holding the API token. Preferred over `api.token`. |
| `api.token` | `""` | The API token, when the chart should create the Secret. |
| `bucketClass.zone` | `""` | The zone of the example BucketClass's buckets. The class is rendered only when set. |
| `bucketClass.bucketNamePrefix` | `""` | Starts every bucket name of the class. Optional. |
| `bucketClass.deletionPolicy` | `Delete` | `Delete` removes an empty bucket with its claim; the driver never deletes objects. |

`values.yaml` documents the rest (image, sidecar, resources, scheduling).

## Limitations

- **One key per account and zone.** Every BucketAccess in a zone gets the same key, and it opens all of the account's
  buckets there. Revoking an access does not revoke the key.
- **The bucket name in the Secret.** COSI writes the Kubernetes Bucket object's name into `spec.bucketName`. It
  differs from the real bucket name when the zone requires a bucket prefix, when `bucketNamePrefix` is set, or when the
  name is longer than 63 characters. Read the real name from the Bucket's `status.bucketID` (`<zone>/<bucket name>`).
- **Private certificate authorities.** COSI's credential format has no field for a CA. When the zone's endpoint uses
  one (`certificate_authority` of `GET /v1/object-storage`), the workload must trust it itself.
- **Quotas.** There are no per-bucket quotas, only the account's quota in the zone.
- **Deleting.** A bucket is deleted only when it is empty.
