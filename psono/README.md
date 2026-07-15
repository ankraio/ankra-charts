# psono

[![Helm chart](https://img.shields.io/badge/helm-chart-blue)](../README.md) ![Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue)

[Psono](https://psono.com/) — self-hosted password manager — packaged as a
Helm chart. Bundles the server, web client and (optional) admin client
behind a single Ingress (Traefik by default).

This chart is **bring-your-own**:

- PostgreSQL — you provide a Secret with the connection details.
- Psono secret keys — you provide a Secret with the Django + Psono crypto
  material.
- SMTP — optional, you provide a Secret if you want outbound mail.

## TL;DR

```bash
# 1. Make sure your Psono PostgreSQL Secret and secret-keys Secret already
#    exist in the target namespace (see "Required Secrets" below).

# 2. Install the chart from GHCR.
helm install psono oci://ghcr.io/ankraio/ankra-charts/psono \
  --version 1.2.0 \
  -n psono --create-namespace \
  --set base_url=https://psono.example.com \
  --set domain=example.com \
  --set ingress.enabled=true \
  --set ingress.tls.enabled=true
```

## Requirements

| Requirement | Notes |
|---|---|
| Kubernetes | `>= 1.20` (enforced by `Chart.yaml`'s `kubeVersion`). Ingress renders `networking.k8s.io/v1`. |
| PostgreSQL | Externally managed (e.g. CloudNativePG, Zalando, Crunchy, RDS). The chart only consumes a Secret. |
| Ingress controller | Traefik by default (`ingress.ingressClassName: traefik`). The chart renders a Traefik `StripPrefix` Middleware that strips `/server` before it reaches the Psono server. Other controllers work — override the class and add controller-specific annotations via `ingress.annotations` (the server expects the `/server` prefix to be stripped). |
| cert-manager | Optional. If `ingress.tls.enabled=true`, the chart references a TLS Secret named after `base_url`'s host (override with `ingress.tls.secretName`). |

## Required Secrets (Bring Your Own)

Names are configurable via `server.secret_keys_secret_name`,
`server.database_secret_name` and `server.email_secret_name`.

### `psono-secret` — server crypto material

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: psono-secret
type: Opaque
stringData:
  secret_key: "<django SECRET_KEY>"
  activation_link_secret: "<random 32+ char string>"
  db_secret: "<random 32+ char string>"
  email_secret_salt: "<random 32+ char string>"
  public_key: "<nacl public key hex>"
  private_key: "<nacl private key hex>"
```

The `public_key` / `private_key` pair is generated once during initial
Psono setup — see the upstream
[server install docs](https://doc.psono.com/admin/installation/install-server-ce.html#installation-with-docker).

### `psono-database-secret` — PostgreSQL connection

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: psono-database-secret
type: Opaque
stringData:
  name: psono
  username: psono
  password: "<db password>"
  host: psono-postgresql.psono.svc.cluster.local
  port: "5432"
  engine: django.db.backends.postgresql
```

### `psono-email-secret` — SMTP (optional)

SMTP env vars are commented out in `templates/server_deployment.yaml`.
Uncomment the block (or use `server.extraSecretEnvironmentVars`) to wire
this in:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: psono-email-secret
type: Opaque
stringData:
  from: noreply@example.com
  host: smtp.example.com
  port: "587"
  use_tls: "True"
  use_ssl: "False"
  user: psono
  password: "<smtp password>"
  backend: django.core.mail.backends.smtp.EmailBackend
```

## Install

### From GHCR (OCI)

```bash
helm install psono oci://ghcr.io/ankraio/ankra-charts/psono \
  --version 1.2.0 \
  -n psono --create-namespace \
  -f my-values.yaml
```

Private clusters need a registry login first:

```bash
helm registry login ghcr.io -u <github-user> -p <github-pat-with-read:packages>
```

### From source (local checkout)

```bash
helm install psono ./psono -n psono --create-namespace -f my-values.yaml
```

## Components

| Component | Default image | Toggle | Service port |
|---|---|---|---|
| Server | `psono/psono-server:5.0.0` | `server.enabled=true` | `10100` |
| Web client | `psono/psono-client:3.6.2` | `webclient.enabled=true` | `10101` |
| Admin client | `psono/psono-admin-client:1.7.12` | `adminClient.enabled=false` | `10102` |

When `ingress.enabled=true`, a single Ingress fronts all three under one
host (`base_url`), all with `pathType: Prefix`:

- `/server` → server (the `/server` prefix is stripped by a Traefik
  Middleware before the request reaches the server)
- `/portal` → admin client (when enabled)
- `/` → web client (catch-all, registered last)

ConfigMap changes roll the web client / admin client Deployments
automatically via a `checksum/config` pod annotation. The server ships
liveness/readiness probes against Psono's `/healthcheck/` endpoint
(`server.livenessProbe` / `server.readinessProbe`, set to `null` to
disable).

## Configuration reference

See [`values.yaml`](values.yaml) for the full list. Key knobs:

| Key | Default | Description |
|---|---|---|
| `base_url` | `""` (REQUIRED) | Public URL, e.g. `https://psono.example.com`. Used in env vars, Ingress host and TLS secret name. |
| `domain` | `""` | Default user domain, surfaced to the web/admin clients. |
| `imagePullSecrets` | `[]` | Pull secrets for all components (override per component with e.g. `server.imagePullSecrets`). |
| `ingress.enabled` | `false` | Render the shared Ingress object. |
| `ingress.ingressClassName` | `"traefik"` | IngressClass to bind. With `traefik`, a StripPrefix Middleware for `/server` is rendered and attached automatically. |
| `ingress.tls.enabled` | `false` | Add a `tls:` block keyed off `base_url`'s host. |
| `ingress.tls.secretName` | `""` | TLS secret name; defaults to the host derived from `base_url`. |
| `server.enabled` | `true` | Render the server Deployment/SA/Service. |
| `server.replicas` | `1` | Server replica count. |
| `server.image.tag` | `5.0.0` | Server image tag. |
| `server.livenessProbe` / `server.readinessProbe` | `/healthcheck/` httpGet | Server probes; set to `null` to disable. |
| `server.allowed_domains` | `[]` | List of allowed domains, rendered comma-separated into `PSONO_ALLOWED_DOMAINS`. |
| `server.allow_registration` | `false` | Allow new-user self-registration on the server. |
| `server.multifactor_enabled` | `true` | Enable MFA on the server. |
| `server.allowed_second_factors` | `"google_authenticator"` | Comma list of allowed second factors. |
| `server.secret_keys_secret_name` | `psono-secret` | Secret with `secret_key`, `activation_link_secret`, `db_secret`, `email_secret_salt`, `public_key`, `private_key`. |
| `server.database_secret_name` | `psono-database-secret` | Secret with `name`, `username`, `password`, `host`, `port`, `engine`. |
| `server.email_secret_name` | `psono-email-secret` | Secret with SMTP config (only wired in if you uncomment the block in `templates/server_deployment.yaml`). |
| `server.env` | `{}` | Arbitrary extra env vars (e.g. `PSONO_*`) as key/value pairs. |
| `server.extraSecretEnvironmentVars` | `[]` | Project arbitrary `PSONO_*` env vars from existing Secrets. |
| `webclient.enabled` | `true` | Render the web client Deployment/SA/Service/ConfigMap. |
| `webclient.replicas` | `1` | Web client replica count. |
| `webclient.image.tag` | `3.6.2` | Web client image tag. |
| `webclient.title` | `"Password Manager"` | Backend server title shown in the clients. |
| `webclient.allow_custom_server` | `true` | Surface the "custom server" picker in the web UI. |
| `webclient.allow_registration` | `false` | Allow registration in the web client UI. |
| `webclient.allow_lost_password` | `true` | Allow lost-password recovery in the web client UI. |
| `webclient.disable_download_bar` | `false` | Hide the download bar in the web client UI. |
| `webclient.authentication_methods` | `["AUTHKEY"]` | Auth methods exposed in the web client config. |
| `adminClient.enabled` | `false` | Render the admin client Deployment/SA/Service/ConfigMap. |
| `adminClient.replicas` | `1` | Admin client replica count. |
| `adminClient.image.tag` | `1.7.12` | Admin client image tag. |

Both client ConfigMaps (web + admin portal) are rendered from the same
`webclient.*` options.

## Uninstall

```bash
helm uninstall psono -n psono
```

The bring-your-own PostgreSQL and Secrets are not touched.

## See also

- Upstream Psono [server install docs](https://doc.psono.com/admin/installation/install-server-ce.html).
- Sibling charts in this repo: [`upcloud-ccm`](../upcloud-ccm/README.md),
  [`upcloud-csi`](../upcloud-csi/README.md),
  [`cloudflare-operator`](../cloudflare-operator/README.md).
