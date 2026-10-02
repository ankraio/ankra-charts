# ghcr.io/ankraio/images/external-dns-webhook-proxy
#
# A loopback-only reverse proxy that runs as a sidecar next to external-dns
# and holds the credential-bearing webhook provider URL, so external-dns is
# configured with http://127.0.0.1:8888 instead. external-dns v0.21.0-v0.23.0
# prints --webhook-provider-url unmasked in its INFO config dump on every
# start, before --log-level takes effect; see README.md.
#
# image-version: v0.1.0
# The published tag is read from the line above by the build workflow. Bump it
# with every change to this directory: consumers pin the tag AND the digest.

# --platform=$BUILDPLATFORM keeps the compiler and the tests on the builder's
# own architecture; the binary is cross-compiled for $TARGETARCH.
FROM --platform=$BUILDPLATFORM golang:1.26-alpine@sha256:8ac98ca534ac3f51e1f420a1dd2c15e74c75cfa0f23f3ad27eb5d7236c349a0c AS build

ARG TARGETOS
ARG TARGETARCH

WORKDIR /src
COPY go.mod ./
COPY *.go ./

# The tests are the contract that the credential never reaches a log line or
# a redirect, so an image that breaks it never ships.
RUN CGO_ENABLED=0 go vet ./... \
    && CGO_ENABLED=0 go test -count=1 ./...

RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /out/external-dns-webhook-proxy .

# distroless static: no shell, no package manager, CA certificates included,
# uid 65532. The rendered pod runs it as 65534 with a read-only root
# filesystem, which needs nothing from the image either.
FROM gcr.io/distroless/static-debian12:nonroot@sha256:afa5c872c891853ca7fcf1f12c3edb23f7eeef36189728842dd51042ff57f7ab

LABEL org.opencontainers.image.source="https://github.com/ankraio/ankra-charts" \
      org.opencontainers.image.description="Loopback reverse proxy that keeps a credential-bearing external-dns webhook URL out of external-dns's configuration and logs" \
      org.opencontainers.image.licenses="Apache-2.0"

COPY --from=build /out/external-dns-webhook-proxy /external-dns-webhook-proxy

USER 65532:65532
ENTRYPOINT ["/external-dns-webhook-proxy"]
