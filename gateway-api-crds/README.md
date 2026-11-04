# gateway-api-crds

The [Kubernetes Gateway API](https://gateway-api.sigs.k8s.io/) CRDs, standard channel, as a Helm chart. The chart version is the Gateway API release it carries.

Kubernetes ships none of these CRDs, and Gateway implementations expect them to be installed first. Ankra installs this chart ahead of Traefik on a cluster created with the Gateway API option.

## What it installs

| Object | Notes |
|---|---|
| `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `TLSRoute`, `ListenerSet`, `ReferenceGrant`, `BackendTLSPolicy` CRDs | Standard channel |
| `safe-upgrades.gateway.networking.k8s.io` ValidatingAdmissionPolicy and binding | Upstream's guard. It refuses experimental CRDs on top of standard ones, and any bundle older than v1.5.0 |

The files under `templates/` are upstream's `config/crd/standard` at the release tag, unchanged except for one added annotation. Upstream labels the admission policy `bundle-version: v1.5.0-dev` even at the v1.5.1 tag; that is kept as it is.

## Why not the `traefik-crds` chart

Helm stores the whole chart in its release Secret, including templates that values switch off. `traefik-crds` carries the Traefik, Traefik Hub, Knative and experimental Gateway API CRDs as well, and its release does not fit the 1 MiB Secret limit:

```
Secret "sh.helm.release.v1.gateway-api-crds.v1" is invalid: data: Too long: may not be more than 1048576 bytes
```

This chart's release Secret is about 540 KB. `charts-gateway-api-crds-lint` installs it on a real cluster and fails if the Secret grows past 900 KB.

## Install

```bash
helm install gateway-api-crds oci://ghcr.io/ankraio/ankra-charts/gateway-api-crds --version 1.5.1 -n gateway-system --create-namespace
```

## Uninstalling keeps the CRDs

Every object carries `helm.sh/resource-policy: keep`. Deleting a CRD deletes every resource of that kind, so `helm uninstall` leaves them in place, along with every Gateway and route. Delete them by hand only if you mean to remove those too.

## CRDs that already exist

An install fails closed if the CRDs are already on the cluster without Helm ownership, for example from a Traefik chart at 40.0.0 or older, which shipped Gateway API v1.4.0 in its own `crds/`. Helm reports the ownership conflict and changes nothing. The safe-upgrades policy would also refuse a later install of anything older than v1.5.0.

## Updating to a new Gateway API release

```bash
./scripts/sync-gateway-api-crds.sh v1.5.2
```

Then set `version` and `appVersion` in `Chart.yaml` to match and update `artifacthub.io/changes`. The script refuses a file that carries Helm template syntax rather than rewriting a CRD schema.
