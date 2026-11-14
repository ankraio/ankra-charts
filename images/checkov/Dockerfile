# bridgecrew/checkov without openssh-client and with fixed versions of the
# Python packages upstream ships with HIGH CVEs, for the Ankra Pipelines
# checkov scan step (ankra-w263pr). Every upstream tag, 3.4.5 included, still
# ships openssh-client 1:10.0p1-7+deb13u4 with the CISA KEV CVE-2026-123158,
# and Debian has no fixed version. Checkov never runs ssh, and git only
# Recommends openssh-client, so the purge leaves git, checkov and the shell
# tools in place. requirements.txt says which CVEs each upgrade closes; checkov
# itself stays at 3.4.5. Built, scanned and published by .ankra/pipeline.yaml
# to share.ankra.cloud/library/checkov.
#
# Checkov renders every Helm chart it finds with helm, so the scan step needs
# it. Upstream bundles helm 3.22.1 (go1.26.9, golang.org/x/net 0.60.0:
# CVE-2026-78661, CVE-2026-111943), the newest 3.x. helm 4.3.2 is built with
# go1.27.4 and x/net 0.62.0, and checkov 3.4.5's helm framework accepts v3 and
# v4. The sha256 is the one get.helm.sh and the GitHub release both publish.
#
# Checkov renders every kustomization with kustomize, too. Upstream bundles
# kustomize 5.8.3, the newest release, built with go1.27.1 (CVE-2026-111943,
# CVE-2026-78667, CVE-2026-78669, CVE-2026-97031). The kustomize stage builds
# the same v5.8.3 module, through the Go module proxy and checksum database,
# on go1.27.4.
ARG HELM_VERSION=v4.3.2
ARG HELM_SHA256=d1c0278d46beab79582d7e50f5b3dc206944ba8e577cde618513fd07daa53983
ARG KUSTOMIZE_VERSION=v5.8.3

FROM golang:1.27.4@sha256:5e8afd493a7124a8586e134d9b532731161d4b9becf9dee5a5956b107426f93d AS kustomize

ARG KUSTOMIZE_VERSION

RUN CGO_ENABLED=0 GOBIN=/out go install -trimpath -ldflags='-s -w' \
        "sigs.k8s.io/kustomize/kustomize/v5@${KUSTOMIZE_VERSION}" \
    && /out/kustomize version | grep -qx "${KUSTOMIZE_VERSION}"

FROM bridgecrew/checkov:3.4.5@sha256:122602cf32cc72286155d39f1f234b7b594818f7b8d7fdf490701620e521368b AS helm

ARG HELM_VERSION
ARG HELM_SHA256

ADD --checksum=sha256:${HELM_SHA256} https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz /tmp/helm.tar.gz
RUN echo "${HELM_SHA256}  /tmp/helm.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/helm.tar.gz -C /tmp linux-amd64/helm \
    && /tmp/linux-amd64/helm version --short | grep -q "^${HELM_VERSION}+"

FROM bridgecrew/checkov:3.4.5@sha256:122602cf32cc72286155d39f1f234b7b594818f7b8d7fdf490701620e521368b

ARG HELM_VERSION
ARG KUSTOMIZE_VERSION

COPY --from=helm --chown=root:root --chmod=0755 /tmp/linux-amd64/helm /usr/local/bin/helm
COPY --from=kustomize --chown=root:root --chmod=0755 /out/kustomize /usr/bin/kustomize
COPY requirements.txt /tmp/ankra-checkov-requirements.txt

RUN apt-get purge -y --auto-remove=no openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && ! command -v ssh \
    && pip install --no-cache-dir --disable-pip-version-check --require-hashes \
        --only-binary=:all: --no-deps -r /tmp/ankra-checkov-requirements.txt \
    && rm /tmp/ankra-checkov-requirements.txt \
    && helm version --short | grep -q "^${HELM_VERSION}+" \
    && kustomize version | grep -qx "${KUSTOMIZE_VERSION}" \
    && checkov --version | grep -qx '3.4.5'
