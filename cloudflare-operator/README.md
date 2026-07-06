# cloudflare-operator

Helm chart for the community
[**adyanth/cloudflare-operator**](https://github.com/adyanth/cloudflare-operator),
which reconciles Cloudflare Tunnel resources (`Tunnel`, `ClusterTunnel`,
`TunnelBinding`, `AccessTunnel`) against the Cloudflare API.

It optionally renders the cluster-scoped `ClusterOriginIssuer` custom
resource consumed by the official
[**cloudflare/origin-ca-issuer**](https://github.com/cloudflare/origin-ca-issuer)
cert-manager external issuer (this chart does **not** install that issuer; use
its upstream Helm chart at
`oci://ghcr.io/cloudflare/origin-ca-issuer-charts/origin-ca-issuer`).

This chart is a Helm-packaged replacement for the raw YAML manifests
previously shipped under
`ankra-production-values/clusters/.../Cloudflare-Stack/manifests/`.

## TL;DR

```bash
helm install cloudflare-operator ./charts/cloudflare-operator \
  -n cloudflare-operator-system --create-namespace \
  -f charts/cloudflare-operator/values-examples/minimal.yaml
```

Then create your tunnels:

```bash
kubectl apply -f - <<'EOF'
apiVersion: networking.cfargotunnel.com/v1alpha2
kind: ClusterTunnel
metadata:
  name: prod-tunnel
spec:
  newTunnel:
    name: prod-tunnel
  cloudflare:
    email: admin@example.com
    domain: example.com
    secret: cloudflare-secrets
    accountId: <your-cloudflare-account-id>
EOF
```

## Requirements

| Component | Version | Notes |
| --- | --- | --- |
| Kubernetes | `>=1.27` | enforced by `Chart.yaml`; `1.27` / `1.29` / `1.31` exercised in CI. |
| Helm | `>=3.12` | required for the `lookup`-less templates and `helm.sh/resource-policy: keep`. |
| cert-manager | any recent | required by default to issue the conversion-webhook serving cert. Disable with `webhook.certManager.enabled=false` + `webhook.existingSecretName`. |
| Cloudflare account | any plan | needs an API token with `Account.Cloudflare Tunnel:Edit` scope. |
| Cloudflare Origin CA issuer chart | any | required **only** if you set `originIssuer.enabled=true`. |

## What gets installed

| Resource | Purpose |
| --- | --- |
| 4 × `CustomResourceDefinition` | `Tunnel`, `ClusterTunnel`, `TunnelBinding`, `AccessTunnel` (`networking.cfargotunnel.com`). |
| `Deployment` | the operator (`/manager`), with leader-election + secure metrics + conversion webhook. |
| `ServiceAccount` + `ClusterRole`/`ClusterRoleBinding` | the operator's permissions. |
| `Role` + `RoleBinding` | leader-election lease in the install namespace. |
| 9 × aggregate `ClusterRole` | viewer / editor / admin per tunnel CRD (bind these to humans/teams). |
| `Service` (webhook) | exposes the conversion webhook on `443`. |
| `Service` (metrics, optional) | exposes secure metrics on `8443`. |
| cert-manager `Issuer` + `Certificate` | self-signed CA + serving cert for the conversion webhook (and metrics, optionally). |
| `Secret` (optional) | Cloudflare API token + account ID, or referenced via `credentials.existingSecret`. |
| `PodDisruptionBudget` (when `replicaCount > 1`) | one replica must remain. |
| `ServiceMonitor` (optional) | Prometheus-Operator scrape config. |
| `NetworkPolicy` (optional) | restricts ingress to webhook/metrics ports and egress to DNS + kube-apiserver + Cloudflare API. |
| `ClusterOriginIssuer` + Origin CA `Secret` (optional) | wires cert-manager to Cloudflare Origin CA. |
| `ClusterTunnel` sample (optional) | quickstart tunnel. |

## Production checklist

- [ ] **Use cert-manager.** It is the only well-supported path to give the
      conversion webhook a CA-bundled cert. Install
      `cert-manager` *before* this chart.
- [ ] **Pin images by digest.** Set `images.manager.digest` to the SHA-256
      of the upstream tag and rely on the digest, not the mutable tag.
- [ ] **Externally manage credentials.** Default reuses
      `credentials.existingSecret=cloudflare-secrets`; populate it with
      [External Secrets Operator](https://external-secrets.io/) or
      [sealed-secrets](https://sealed-secrets.netlify.app/) rather than
      letting Helm ship cleartext.
- [ ] **Enable observability.** Set `metrics.serviceMonitor.enabled=true`
      (requires the Prometheus Operator CRDs).
- [ ] **Run >= 2 replicas** on multi-AZ clusters so the rolling update never
      drops the reconciliation loop (`replicaCount: 2`, leader election is
      on by default).
- [ ] **Confirm the namespace matches CRD references.** The CRDs reference
      the conversion webhook in
      `<release-namespace>/<fullname>-webhook`; if you override
      `namespaceOverride` after install, run `helm upgrade` to re-render.

## Sharing the Cloudflare Secret with other workloads

The default reuses `cloudflare-secrets` - created/rotated outside this
release - so the same token can be referenced from `ClusterTunnel.spec` and
from any other workload in the same namespace (cluster-tunnel pods load it
via the `secret:` field).

If you want this chart to create the Secret instead, swap to:

```yaml
credentials:
  create: true
  existingSecret: ""
  apiToken: "<scoped-cloudflare-api-token>"
  accountId: "<your-cloudflare-account-id>"
```

…and `cloudflare-secrets` will be rendered into the release namespace.

## Origin CA Issuer integration

The Ankra production stack pairs the operator with Cloudflare's Origin CA
cert-manager external issuer. Install it once per cluster from upstream:

```bash
helm install origin-ca-issuer \
  oci://ghcr.io/cloudflare/origin-ca-issuer-charts/origin-ca-issuer \
  -n cert-manager
```

Then have this chart render the `ClusterOriginIssuer` CR + its Secret:

```yaml
originIssuer:
  enabled: true
  name: cloudflare-origin-issuer
  requestType: OriginECC
  secret:
    create: true
    namespace: cert-manager
    key: api-token
    token: "<origin-ca-api-token>"
```

…or reference an existing token Secret:

```yaml
originIssuer:
  enabled: true
  secret:
    create: false
    existingSecret: origin-ca-issuer-secret
    namespace: cert-manager
    key: api-token
```

## Air-gapped installs

Mirror two images into your registry:

| Image | Purpose |
| --- | --- |
| `docker.io/adyanth/cloudflare-operator:0.13.1` | the operator manager. |
| `docker.io/cloudflare/cloudflared:2025.4.0` | the per-tunnel data-plane (image is set by the operator into the rendered Deployment, *not* by this chart). |

Set:

```yaml
global:
  imageRegistry: harbor.internal/docker.io
  imagePullSecrets:
    - harbor-pull-secret
```

…and override individual `images.*.digest` when you have published the
digests into your mirror. See
[`values-examples/air-gapped.yaml`](./values-examples/air-gapped.yaml).

## Upgrade / uninstall

- **Upgrade** with `helm upgrade --install` - CRDs are templatized (with
  `helm.sh/resource-policy: keep`) so they are reconciled on every release,
  but **never deleted** by `helm uninstall`. Your `ClusterTunnel` / `Tunnel`
  CRs survive a `helm uninstall`.
- The chart bumps a `checksum/cloudflare-secret` pod annotation when the
  in-release Secret changes; this only rotates pods when `credentials.create`
  is true.
- Removing the chart **does not** delete tunnels in Cloudflare - clean those
  up via the Cloudflare dashboard or `cloudflared tunnel delete`.

## Configuration

The most useful knobs (see `values.yaml` for the full set):

| Key | Default | Description |
| --- | --- | --- |
| `replicaCount` | `1` | Number of manager replicas. Bump to `2+` for HA. |
| `images.manager.{registry,repository,tag,digest,pullPolicy}` | `docker.io / adyanth/cloudflare-operator / "" / "" / IfNotPresent` | Operator image. Empty `tag` falls back to `.Chart.AppVersion`. Set `digest` to pin. |
| `global.imageRegistry` | `""` | Override every image registry (air-gapped). |
| `crds.install` | `true` | Install the four `networking.cfargotunnel.com` CRDs. |
| `credentials.create` | `false` | Render the `cloudflare-secrets` Secret from `apiToken`/`accountId`. |
| `credentials.existingSecret` | `cloudflare-secrets` | Reuse an externally-managed Secret in the install namespace. |
| `serviceAccount.create` | `true` | Render the operator ServiceAccount. |
| `rbac.create` | `true` | Render the operator's RBAC. |
| `rbac.aggregateClusterRoles` | `true` | Render aggregate viewer/editor/admin ClusterRoles per tunnel CRD. |
| `webhook.certManager.enabled` | `true` | Use cert-manager to issue the webhook serving cert. |
| `webhook.certManager.createSelfSignedIssuer` | `true` | Spin up a self-signed `Issuer` (matches upstream). |
| `webhook.certManager.issuerRef.{name,kind,group}` | `""` / `Issuer` / `cert-manager.io` | External issuer (used when `createSelfSignedIssuer=false`). |
| `webhook.existingSecretName` | `""` | TLS Secret to mount when `certManager.enabled=false`. |
| `metrics.enabled` | `true` | Bind the secure metrics endpoint. |
| `metrics.service.enabled` | `false` | Render a metrics Service (auto-enabled by `serviceMonitor.enabled`). |
| `metrics.serviceMonitor.enabled` | `false` | Render a Prometheus-Operator `ServiceMonitor`. |
| `podDisruptionBudget.enabled` | `true` | Active only when `replicaCount > 1`. |
| `networkPolicy.enabled` | `false` | Render the opt-in NetworkPolicy. |
| `sampleClusterTunnel.enabled` | `false` | Render a sample `ClusterTunnel` (requires `cloudflareDomain` + `cloudflareEmail`). |
| `originIssuer.enabled` | `false` | Render a `ClusterOriginIssuer` (requires the upstream origin-ca-issuer chart). |
| `originIssuer.secret.create` | `false` | Render the Origin CA token Secret instead of referencing one. |

## Local development

```bash
make -C charts lint        # lint every chart including this one
make -C charts template    # render every chart to /tmp/rendered/
make -C charts test        # helm-unittest every chart
make -C charts sync-cloudflare-check
```

The `vendor/v0.13.1/` directory holds the pristine upstream manifests so
diffing the chart against upstream is `diff -ru vendor/v0.13.1
<(helm template ... | yq 'sort_by(.kind, .metadata.name)')`.

## Sync workflow

`.github/workflows/charts-cloudflare-operator-sync.yml` runs daily, checks
[adyanth/cloudflare-operator releases](https://github.com/adyanth/cloudflare-operator/releases)
for a new tag, re-vendors `cloudflare-operator.{crds,}yaml` into
`vendor/<new-version>/`, bumps `appVersion`, re-runs the CRD splitter, and
opens a pull request labelled `needs-review` for human approval.

## Notes on the four CRDs

| CRD | Group / Version | Scope |
| --- | --- | --- |
| `Tunnel` | `networking.cfargotunnel.com/v1alpha2` | Namespaced |
| `ClusterTunnel` | `networking.cfargotunnel.com/v1alpha2` | Cluster |
| `TunnelBinding` | `networking.cfargotunnel.com/v1alpha1` | Namespaced |
| `AccessTunnel` | `networking.cfargotunnel.com/v1alpha1` | Namespaced |

Only `ClusterTunnel` registers a conversion webhook (v1alpha1 to v1alpha2),
served by this chart at `<release-namespace>/<fullname>-webhook` with TLS
provided by cert-manager. The other CRDs are single-version or use the default
`None` conversion strategy. When `webhook.certManager.enabled=false` (bring your
own TLS), the `cert-manager.io/inject-ca-from` annotation is omitted from the
CRDs and you must populate `spec.conversion.webhook.clientConfig.caBundle`
yourself.
