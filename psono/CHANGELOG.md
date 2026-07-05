# psono changelog

All notable changes to this chart will be documented in this file. Format
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the chart
uses [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.1.0] - 2026-07-05

### Fixed

- `server.env`, `webclient.env`, `adminClient.env` and
  `server.extraSecretEnvironmentVars` rendered over-indented list items,
  producing invalid YAML that broke `helm template`/`helm install` as soon
  as any of them were set.
- Web client and admin client Deployments read `replicas`, `podAnnotations`,
  `podSecurityContext` and `securityContext` from the top-level values scope
  instead of their own section, so `webclient.replicas` & co. were silently
  ignored.
- Server Deployment read `imagePullSecrets` from the undefined
  `server.imagePullSecrets`; all Deployments now use the top-level
  `imagePullSecrets`, overridable per component
  (`server.imagePullSecrets`, `webclient.imagePullSecrets`,
  `adminClient.imagePullSecrets`).
- `PSONO_ALLOWED_DOMAINS` rendered Go slice syntax
  (`[example.com example.org]`) instead of a comma-separated list.
- `values.yaml` documented the database secret key as `user` while the
  templates read `username`.
- `NOTES.txt` referenced a nonexistent `webclient.backend_servers` value and
  always claimed no backend servers were configured; rewritten around the
  actual values.

### Added

- Server liveness/readiness probes against Psono's `/healthcheck/` endpoint,
  configurable via `server.livenessProbe` / `server.readinessProbe` (set to
  `null` to disable).
- `checksum/config` pod annotations on the web client and admin client so
  ConfigMap changes roll the Deployments.
- `ingress.tls.secretName` to override the TLS secret name (still defaults
  to the host derived from `base_url`).
- Missing values keys that templates already referenced:
  `webclient.service.type`, `adminClient.service.type`, and `resources`,
  `nodeSelector`, `tolerations`, `affinity`, `podAnnotations`,
  `podSecurityContext`, `securityContext` for webclient and adminClient.
- Chart `icon`.
- helm-unittest suite under `tests/` (31 tests; run with `helm unittest psono`
  or `make unittest`).

### Changed

- Web client and admin client ConfigMap options (`allow_custom_server`,
  `allow_registration`, `allow_lost_password`, `disable_download_bar`,
  `authentication_methods`) are now wired to the `webclient.*` values
  instead of being hardcoded.
- Ingress always renders `networking.k8s.io/v1` (the chart already requires
  Kubernetes >= 1.20); dropped the dead `extensions/v1beta1` branch. The
  admin client path is now registered before the web client catch-all.
- Server Deployment no longer overrides the container `command` (it
  duplicated the image default); the admin client container is named
  `admin-client` instead of the chart name.
- `ingress.annotations` default is a map (`{}`) instead of a list.

### Removed

- Unused `server.envFiles` value (never consumed by any template).

## [1.0.1] - 2026-05-23

### Changed

- Chart relocated from `ankra-io/infra-psono` (`helm/` directory) into the
  `ankra-charts` monorepo as `psono/`.
- `Chart.yaml` metadata refreshed: ankra-charts `home`/`sources`, maintainer,
  keywords, and `artifacthub.io/*` annotations including the new OCI publish
  coordinates (`oci://ghcr.io/ankraio/ankra-charts/psono`).
- Templates and `values.yaml` are byte-identical to the last published
  `psono-1.0.1.tgz` from `infra-psono`.

## [1.0.0] - 2024-11-04

### Added

- Server (`psono/psono-server:5.0.0`) Deployment, ServiceAccount, Service,
  ingress wiring, and full `PSONO_*` env var pass-through (debug, hosts,
  domains, registration, files, multi-factor, second factors, user search,
  matching username/email).
- Web client (`psono/psono-client:3.6.2`) Deployment, ServiceAccount,
  Service, ConfigMap with `backend_servers`, base URL, custom-server toggle,
  registration / lost-password / download-bar toggles, and
  `authentication_methods`.
- Optional admin client (`psono/psono-admin-client:1.7.12`) Deployment,
  ServiceAccount, Service and ConfigMap; routed under `/portal*` when
  ingress is enabled.
- Single shared ingress (`nginx` by default) that fronts the server under
  `/server/*`, web client under `/*`, and (when enabled) admin client under
  `/portal*`. Optional TLS toggle that derives the secret name from
  `base_url`.
- Secret references (Bring Your Own) for:
  - `server.secret_keys_secret_name` (`secret_key`, `activation_link_secret`,
    `db_secret`, `email_secret_salt`, `public_key`, `private_key`).
  - `server.database_secret_name` (`name`, `username`, `password`, `host`,
    `port`, `engine`).
  - `server.email_secret_name` (commented-out by default; uncomment in
    `server_deployment.yaml` to wire SMTP from a Secret).

## [0.2.0] - 2024-11-03

### Added

- Initial chart layout split into server / webclient / adminClient roles
  with shared `psono.*` template helpers.
