# ghcr.io/ankraio/images/trivy
#
# Aqua Security publishes aquasec/trivy, and this build exists only to carry
# one Alpine package fix until an upstream Trivy release does: the 0.76.1
# image (built 2026-10-21 on Alpine 3.24.2) ships brotli-libs 1.2.0-r1, which
# carries CVE-2026-111497 (out-of-bounds write in the Brotli decoder, CRITICAL,
# on the CISA known-exploited list since 2026-10-27). Alpine published the fix,
# brotli-libs 1.2.1-r0, on the v3.24 branch the day after the image was cut,
# and no Trivy release has been made since. trivy-operator runs this image for
# every scan job and for its built-in Trivy server, so every cluster with the
# Ankra security baseline carries the finding.
#
# The build takes the upstream image as published, pinned by digest, and
# raises brotli-libs to 1.2.1-r0 or later. It changes nothing else: the Trivy
# binary, the templates under /contrib, the entrypoint and every other package
# are upstream's. Upstream's own Dockerfile carries a fix the same way
# (`apk add 'zlib>=1.3.2-r1'` for CVE-2026-85091).
#
# Drop this image (and .github/workflows/charts-trivy-image.yml) with the
# first upstream Trivy release whose image carries brotli-libs >= 1.2.1-r0,
# and point trivy.image back at mirror.gcr.io/aquasec/trivy in the Ankra
# security-baseline profile.
#
# Upstream is Apache-2.0 with a NOTICE file. Both are carried into the image
# below, and MODIFICATIONS records that this build is not stock upstream -
# Apache-2.0 section 4 asks for the licence, the NOTICE, and a statement of
# the changes made.
#
# image-revision: ankra.1
# The published tag is <upstream tag>-<image-revision>, the upstream tag read
# from UPSTREAM_IMAGE below, so this image can never be confused with stock
# upstream. Bump the revision when the package floor changes but the upstream
# image does not; reset it to ankra.1 when UPSTREAM_IMAGE moves.

# mirror.gcr.io serves the same index digest as docker.io/aquasec/trivy, is
# the registry the trivy-operator chart pulls from by default, and does not
# rate-limit anonymous pulls the way Docker Hub does. Keep the tag and the
# digest in step: the tag names the image, the digest is what gets pulled.
ARG UPSTREAM_IMAGE=mirror.gcr.io/aquasec/trivy:0.76.1@sha256:790fd66d1697395d8693d1acaa1ea702406a20f109b6fc7bac8db623eca6c06c

FROM ${UPSTREAM_IMAGE}

ARG UPSTREAM_IMAGE
# The Trivy commit the upstream release was cut from: the licence files are
# read at it, and it is the image's revision label.
ARG UPSTREAM_COMMIT=e713f67f7d54decdcd9b3132c9751833dcced698

LABEL org.opencontainers.image.title="trivy" \
      org.opencontainers.image.description="Trivy, built by Ankra from the pinned upstream image with brotli-libs raised to the Alpine release that fixes CVE-2026-111497" \
      org.opencontainers.image.source="https://github.com/ankraio/ankra-charts" \
      org.opencontainers.image.url="https://github.com/ankraio/ankra-charts/tree/main/images/trivy" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.revision="${UPSTREAM_COMMIT}" \
      org.opencontainers.image.vendor="Ankra AB"

# The version floor makes the build fail rather than ship the vulnerable
# package if the mirror ever serves an older index. Only brotli-libs moves:
# its one dependency is the musl soname, which the base already has.
RUN apk add --no-cache 'brotli-libs>=1.2.1-r0'

# MODIFICATIONS is written first so the directory exists, mode 0755, before
# the licence files land in it: an ADD --chmod would otherwise create the
# missing directories with the files' mode, which a non-root user cannot
# enter.
RUN mkdir -p /usr/share/licenses/trivy \
    && printf '%s\n' \
      "This image is a modified build of Aqua Security's Trivy image." \
      "Upstream: https://github.com/aquasecurity/trivy" \
      "Built from ${UPSTREAM_IMAGE}" \
      "(Trivy commit ${UPSTREAM_COMMIT})." \
      "The only change is the Alpine package brotli-libs, raised from 1.2.0-r1" \
      "to 1.2.1-r0 or later for CVE-2026-111497. The Trivy binary and every" \
      "other file are upstream's." \
      > /usr/share/licenses/trivy/MODIFICATIONS

# The checksums make the build fail if either file changes under that ref;
# a remote ADD is written 0600 unless told otherwise.
ADD --chmod=644 --checksum=sha256:c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4 \
    https://raw.githubusercontent.com/aquasecurity/trivy/${UPSTREAM_COMMIT}/LICENSE \
    /usr/share/licenses/trivy/LICENSE
ADD --chmod=644 --checksum=sha256:aed9bc6dab87c6f6567d20bf0f5c0433a8ccd3ad7873322cf79b9244eb720a1f \
    https://raw.githubusercontent.com/aquasecurity/trivy/${UPSTREAM_COMMIT}/NOTICE \
    /usr/share/licenses/trivy/NOTICE
