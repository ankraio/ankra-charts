# Changelog

All notable changes to the `isms-builder` chart.

## 0.1.0 - 2026-08-31

### Added

- Initial release, wrapping upstream 1.40.2. Upstream publishes a multi-arch
  container image (`ghcr.io/coolstartnow/isms-builder`) but no Helm chart, so
  this chart provides the Kubernetes packaging.
- **Non-root runtime**: the image's entrypoint starts as root to chown a
  docker-compose bind mount; the chart bypasses it (`command: node
  server/index.js`) and runs as the image's fixed `isms` user (uid 100) with
  `fsGroup` ownership of the data volume, a read-only root filesystem and no
  capabilities - the defaults satisfy the PodSecurity `restricted` profile.
- **Persistence**: a PersistentVolumeClaim at `/app/data` holds the JSON
  stores, the sqlite database and every uploaded file; kept on uninstall by
  default (`persistence.retain`).
- **Storage backends**: `json` (default), `sqlite`, `postgres`, `mariadb`;
  the SQL backends refuse to render without `storage.database.host` and a
  `DB_PASS` source.
- **Managed secrets**: `JWT_SECRET` required at render time via
  `secrets.existingSecret`, an ExternalSecret, or a waived inline value;
  optional SMTP delivery with `SMTP_PASS` from the same Secret.
- **Hardening guardrails** (`hardening.*`): digest pinning, no inline
  secrets, no privileged runtime, NetworkPolicy required - each refusal
  carries a named waiver. `replicaCount` is fixed at 1 because uploads and
  the file backends are per-pod state on one ReadWriteOnce volume.
- **NetworkPolicy**: default same-namespace-only, in both directions, plus
  DNS; `egress.extra` opens SMTP or an out-of-namespace database
  deliberately.
