# external-dns-webhook-proxy

A loopback-only reverse proxy that runs as a sidecar next to
[external-dns](https://github.com/kubernetes-sigs/external-dns) and holds a
webhook provider URL that carries a credential, so external-dns itself never
does. Published as `ghcr.io/ankraio/images/external-dns-webhook-proxy`.

## Why it exists

Some webhook providers authenticate with a token in the URL path, for example
Avura's `https://avura.work/api/external-dns/<token>`. external-dns prints its
whole resolved configuration at INFO on every start - **before** it applies
`--log-level` - and its config dump masks only fields tagged `secure:"yes"`.
`WebhookProviderURL` is not tagged (v0.21.0 through v0.23.0), so the token
lands in the pod log of every external-dns that starts, whatever log level the
pod asks for. Passing the URL through a Secret keeps it out of the pod spec but
not out of that log line.

With this proxy external-dns is configured with `http://127.0.0.1:8888`, which
is not a secret. The proxy forwards every webhook call to the real URL:

| external-dns asks the proxy for | the proxy calls |
|---|---|
| `GET /` (negotiation) | `GET <url>` |
| `GET` / `POST /records` | `GET` / `POST <url>/records` |
| `POST /adjustendpoints` | `POST <url>/adjustendpoints` |

Query strings are merged, the `Host` header is the upstream host, userinfo in
the URL becomes HTTP Basic auth, and a redirect that points back into the
upstream URL is rewritten into the proxy's own path space so external-dns never
sees the credential-bearing path. No provider-side change is needed.

## What it never does

- **Log the credential.** One startup line names the listen address and the
  upstream *origin* (scheme and host). A failed upstream call logs the method,
  the path external-dns asked for, and the transport error with the URL
  stripped; every log line additionally passes a redactor that scrubs the
  upstream path, its segments, the query and the userinfo. The tests fail the
  image build if a credential reaches a log line or a redirect.
- **Listen beyond loopback.** `LISTEN_ADDRESS` must be a loopback IP. The proxy
  adds the credential to every request it forwards, so anything able to reach
  it could write DNS as the credential's owner; on the pod IP that would be
  every workload in the cluster.
- **Add forwarding headers.** No `X-Forwarded-*` is set.

## Configuration

| Variable | Required | Default | Meaning |
|---|---|---|---|
| `WEBHOOK_PROVIDER_URL` | yes | - | The credential-bearing webhook URL. Inject it from a Secret. |
| `LISTEN_ADDRESS` | no | `127.0.0.1:8888` | Loopback address to listen on. |

The process exits non-zero when the URL is missing or not an absolute http(s)
URL; the error never echoes the value. It reads the URL once at start, so a
rotated Secret takes effect when the pod restarts - render a checksum of the
Secret onto the pod template so a rotation rolls it.

## Example sidecar

```yaml
containers:
  - name: external-dns
    image: registry.k8s.io/external-dns/external-dns:v0.21.0
    args:
      - --provider=webhook
      - --webhook-provider-url=http://127.0.0.1:8888
  - name: webhook-proxy
    image: ghcr.io/ankraio/images/external-dns-webhook-proxy:v0.1.0
    env:
      - name: WEBHOOK_PROVIDER_URL
        valueFrom:
          secretKeyRef: {name: external-dns-webhook, key: webhook-provider-url}
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities: {drop: [ALL]}
```

The Ankra platform renders exactly this wiring for every external-dns it
installs (cluster repo, `scheduler/go/internal/cloudprovstack`).

## Build

`.github/workflows/charts-external-dns-webhook-proxy-image.yml` builds on every
push to `main` that touches this directory: `go vet` and the tests run inside
the Dockerfile, the binary is cross-compiled for amd64 and arm64 onto
`gcr.io/distroless/static-debian12:nonroot`, and the image is pushed as
`:<image-version>` (read from the Dockerfile) and signed with cosign keyless
OIDC. Bump `image-version` with every change here; consumers pin tag and
digest.

Locally:

```bash
docker run --rm -v "$PWD":/src -w /src golang:1.26 go test ./...
docker buildx build --platform linux/amd64,linux/arm64 .
```
