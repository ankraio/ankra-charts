# isms-builder

[ISMS Builder](https://github.com/coolstartnow/isms-builder) on Kubernetes -
the open-source ISO 27001 / NIS2 ISMS template builder (AGPL-3.0). Upstream
publishes a multi-arch container image but no Helm chart, so this one wraps it:

- **Digest-pinned image** - upstream's own `ghcr.io/coolstartnow/isms-builder`,
  pinned by digest so a moved tag cannot change what runs.
- **Non-root, restricted-profile runtime** - the image's docker-compose
  entrypoint starts as root to chown a bind mount; the chart bypasses it and
  runs the server directly as the image's `isms` user (uid 100), read-only
  root filesystem, no capabilities, satisfying the PodSecurity `restricted`
  profile.
- **Persistent by default** - JSON stores, the sqlite database and every
  uploaded file live on a PersistentVolumeClaim at `/app/data`, kept on
  uninstall (`persistence.retain`).
- **Managed secrets** - `JWT_SECRET` (required), `DB_PASS` and `SMTP_PASS`
  come from a Secret you manage or an ExternalSecret; inline values are
  refused unless waived.
- **Network-restricted** - a default NetworkPolicy limits the pod to DNS and
  its own namespace in both directions; an ISMS holds your security records
  and has no business on the open internet.

## Quick start

```bash
kubectl create namespace isms
kubectl -n isms create secret generic isms-credentials \
  --from-literal=JWT_SECRET="$(openssl rand -base64 48)"

helm repo add ankra https://ankraio.github.io/ankra-charts
helm install isms ankra/isms-builder -n isms \
  --set secrets.existingSecret=isms-credentials
```

Then open the app (see the release notes for the URL) and log in.

**A fresh installation seeds the user `admin` with the password `adminpass` -
change it before anyone else can reach the Service.** Do not put an Ingress in
front of an installation that still has the seeded credential.

## Storage backends

| `storage.backend` | Records live in | Notes |
| --- | --- | --- |
| `json` (default) | JSON files on the data volume | Upstream's default; zero dependencies |
| `sqlite` | SQLite on the data volume | Single file, `data/isms.db` |
| `postgres` | PostgreSQL | Needs `storage.database.host` + `DB_PASS` in the Secret |
| `mariadb` | MariaDB | Needs `storage.database.host` + `DB_PASS` in the Secret |

Uploaded files (GDPR documents, guidance attachments, template files) stay on
the data volume with **every** backend, so persistence matters even with an
external database. That is also why `replicaCount` is fixed at 1 - a second
replica would hold a different ISMS; the render refuses it.

## Hardening guardrails

`helm template`/`install` fails with a named reason instead of shipping a
weaker Deployment. Each rule has its own waiver under `hardening.*`:

| Refused | Waiver |
| --- | --- |
| No `JWT_SECRET` source | none - it signs every login token |
| `image.tag` without `image.digest` | `allowMutableImageTag` |
| Inline `secrets.<KEY>` values | `allowInlineSecrets` |
| Root, writable rootfs, added capabilities, mounted SA token | `allowPrivilegedRuntime` |
| `networkPolicy.enabled=false` | `allowUnrestrictedNetwork` |
| `replicaCount != 1`, SQL backend without host/`DB_PASS` | none - they do not work |

## Secrets

Every key of the configured Secret lands in the container environment:

| Key | Required | Used for |
| --- | --- | --- |
| `JWT_SECRET` | always | signs login tokens; rotate to invalidate all sessions |
| `DB_PASS` | `postgres` / `mariadb` backends | database password |
| `SMTP_PASS` | when `smtp.user` is set | SMTP authentication |

Point `secrets.existingSecret` at a Secret you manage (SOPS, sealed-secrets,
Vault), or let the External Secrets Operator deliver it via
`externalSecret.*` - see `values-examples/production.yaml`.

## Reaching out: SMTP, external databases

The default NetworkPolicy allows egress only to DNS and the pod's own
namespace. An SMTP relay, an Ollama endpoint or a database in another
namespace needs an explicit `networkPolicy.egress.extra` rule - see the
commented example in `values-examples/postgres.yaml`.

## Values examples

| File | Shows |
| --- | --- |
| `values-examples/minimal.yaml` | smallest guardrail-satisfying install |
| `values-examples/postgres.yaml` | PostgreSQL backend next to the app |
| `values-examples/production.yaml` | ESO secrets, TLS Ingress, postgres, real client addresses |

## Verifying what you install

The chart is also published as an OCI artifact with keyless signatures:

```bash
helm pull oci://ghcr.io/ankraio/ankra-charts/isms-builder
```

See the [repository README](https://github.com/ankraio/ankra-charts#verifying-a-published-chart)
for signature verification.
