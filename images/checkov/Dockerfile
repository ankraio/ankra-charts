# bridgecrew/checkov without openssh-client and with fixed versions of the
# Python packages upstream ships with HIGH CVEs, for the Ankra Pipelines
# checkov scan step (ankra-w263pr). Every upstream tag, 3.4.5 included, still
# ships openssh-client 1:10.0p1-7+deb13u4 with the CISA KEV CVE-2026-123158,
# and Debian has no fixed version. Checkov never runs ssh, and git only
# Recommends openssh-client, so the purge leaves git, checkov and the shell
# tools in place. requirements.txt says which CVEs each upgrade closes; checkov
# itself stays at 3.4.5. Built, scanned and published by .ankra/pipeline.yaml
# to share.ankra.cloud/library/checkov.
FROM bridgecrew/checkov:3.4.5@sha256:122602cf32cc72286155d39f1f234b7b594818f7b8d7fdf490701620e521368b

COPY requirements.txt /tmp/ankra-checkov-requirements.txt

RUN apt-get purge -y --auto-remove=no openssh-client \
    && rm -rf /var/lib/apt/lists/* \
    && ! command -v ssh \
    && pip install --no-cache-dir --disable-pip-version-check --require-hashes \
        --only-binary=:all: --no-deps -r /tmp/ankra-checkov-requirements.txt \
    && rm /tmp/ankra-checkov-requirements.txt \
    && checkov --version | grep -qx '3.4.5'
