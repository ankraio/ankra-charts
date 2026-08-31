# ghcr.io/ankraio/images/upcloud-cloud-controller-manager
#
# UpCloud publishes ghcr.io/upcloudltd/cloud-controller-manager, and this
# build exists only to carry one patch until it lands upstream: a managed
# load balancer reaches its backends over the SDN private network it is
# attached to, but the controller builds backend members from the node's
# Kubernetes InternalIP. Those are the same address on an ordinary cluster
# and different on a meshed one, where kubelet advertises a WireGuard
# overlay address the load balancer is not a peer of. The result is silent:
# the service gets an EXTERNAL-IP, the controller logs EnsuredLoadBalancer,
# and the load balancer then serves 503 or refuses connections.
#
# patches/0001-loadbalancer-backend-address-source.patch adds
# `loadBalancerBackendAddressSource` to the CCM config. It defaults to
# node-internal-ip, so this image behaves exactly like upstream unless a
# cluster opts in to `private-network`.
#
# Drop this image (and the patch) once the change is released upstream, and
# point images.ccm back at ghcr.io/upcloudltd/cloud-controller-manager.
#
# Upstream is Apache-2.0 with a NOTICE file. Both are carried into the
# runtime layer below, and MODIFICATIONS records that this build is not
# stock upstream - Apache-2.0 section 4 asks for the licence, the NOTICE,
# and a statement of the changes made.

# --platform=$BUILDPLATFORM pins this stage to the builder's own
# architecture and the binary is cross-compiled for $TARGETARCH below.
# Building it natively per-architecture instead means the arm64 half runs
# the Go compiler and the test suite under QEMU, which took over 26 minutes
# per build; cross-compiling is a few minutes and produces the same binary.
FROM --platform=$BUILDPLATFORM golang:1.25-alpine AS build

ARG TARGETOS
ARG TARGETARCH
ARG UPSTREAM_REPOSITORY=https://github.com/UpCloudLtd/upcloud-cloud-controller-manager
# v1.2.3 - the commit is what gets fetched; keep it and the tag in step.
ARG UPSTREAM_COMMIT=d04f4e864875bf649128f7113f6d075e3f79be81
# image-revision: ankra.3
# Bump when the patch set changes but the upstream commit does not; the
# published tag is <upstream tag>-<image-revision>, so this image can never
# be confused with stock upstream v1.2.3.

RUN apk add --no-cache curl git

RUN mkdir /upstream \
    && curl -fsSL "${UPSTREAM_REPOSITORY}/archive/${UPSTREAM_COMMIT}.tar.gz" \
       | tar -xz --strip-components=1 -C /upstream

COPY patches/ /patches/

# --3way needs a git index; the archive is not a repository.
RUN cd /upstream \
    && git init -q . \
    && git apply --verbose /patches/*.patch

# The tests ship with the patch and are cheap, so the build runs them: an
# image that would silently mis-address every backend member is exactly the
# failure this patch exists to prevent. They run once, on the builder's
# native architecture - this code has no architecture-specific behaviour,
# so running them again under emulation would only cost time.
RUN cd /upstream && CGO_ENABLED=0 go test ./internal/...

RUN cd /upstream \
    && CGO_ENABLED=0 GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" \
       go build -trimpath -ldflags "-s -w" \
       -o /out/cloud-controller-manager \
       github.com/UpCloudLtd/upcloud-cloud-controller-manager/cmd/upcloud-cloud-controller-manager

FROM alpine:3.23

ARG UPSTREAM_COMMIT=d04f4e864875bf649128f7113f6d075e3f79be81
LABEL org.opencontainers.image.title="upcloud-cloud-controller-manager" \
      org.opencontainers.image.description="UpCloud cloud controller manager, built by Ankra from the pinned upstream release with the load balancer backend address source patch" \
      org.opencontainers.image.source="https://github.com/ankraio/ankra-charts" \
      org.opencontainers.image.url="https://github.com/ankraio/ankra-charts/tree/main/images/upcloud-ccm" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.revision="${UPSTREAM_COMMIT}" \
      org.opencontainers.image.vendor="Ankra AB"

RUN apk add --no-cache curl tini

COPY --from=build /upstream/LICENSE /usr/share/licenses/upcloud-cloud-controller-manager/LICENSE
COPY --from=build /upstream/NOTICE /usr/share/licenses/upcloud-cloud-controller-manager/NOTICE
COPY --from=build /patches/ /usr/share/licenses/upcloud-cloud-controller-manager/patches/
RUN printf '%s\n' \
      "This image is a modified build of UpCloud's cloud-controller-manager." \
      "Upstream: https://github.com/UpCloudLtd/upcloud-cloud-controller-manager" \
      "Built from commit ${UPSTREAM_COMMIT} with the patches in ./patches applied." \
      "The patches add ccmConfig.loadBalancerBackendAddressSource; they do not" \
      "change behaviour unless that option is set." \
      > /usr/share/licenses/upcloud-cloud-controller-manager/MODIFICATIONS

COPY --from=build /out/cloud-controller-manager /usr/local/bin/

ENTRYPOINT ["/sbin/tini", "--"]
CMD ["cloud-controller-manager"]
