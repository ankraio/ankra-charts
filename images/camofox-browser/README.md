# camofox-browser

Upstream [`jo-inc/camofox-browser`](https://github.com/jo-inc/camofox-browser)
(MIT) publishes **no container image** — its README tells you to build one
locally with `make up`. The `hermes-agent` chart runs it as a sidecar, and a
chart cannot depend on an image nobody publishes, so this repository builds and
publishes it as `ghcr.io/ankraio/images/camofox-browser`.

There is deliberately **no Dockerfile here**. Upstream's own Dockerfile already
downloads the pinned Camoufox bundle at build time and copies its server in, so
`.github/workflows/charts-camofox-image.yml` checks the upstream repository out
at a pinned tag and builds *that* Dockerfile. Copying it here would fork a build
we do not own and let it drift silently.

## What gets built

| | |
|---|---|
| Source | `jo-inc/camofox-browser` at the tag pinned in the workflow's `UPSTREAM_TAG` |
| Image | `ghcr.io/ankraio/images/camofox-browser:<tag>` |
| Platform | `linux/amd64` only — see below |
| Signature | cosign keyless OIDC, like every other image and chart here |

**amd64 only, on purpose.** Upstream's Dockerfile takes the Camoufox binary
architecture as a build argument (`ARG ARCH=x86_64`) and downloads a matching
release zip. A single multi-arch `buildx` invocation cannot vary that argument
per platform, so an arm64 image built the naive way would carry an x86_64
Firefox and fail at runtime in a way no image-level test would catch. If arm64
is ever needed, build the two architectures as separate jobs with
`ARCH=aarch64` and join them into a manifest list.

## Rolling the version

1. Bump `UPSTREAM_TAG` in `.github/workflows/charts-camofox-image.yml`.
2. Merge — the workflow builds, pushes and signs the new tag.
3. Re-pin the chart: `./scripts/sync-image-digest.sh camofox-browser`.
4. Bump `hermes-agent`'s chart version and open a PR.

The chart pins the image by digest, so a rebuild changes nothing on any cluster
until step 3 lands — which is the point: a browser that renders untrusted pages
inside the agent's pod should not change under anyone without a review.
