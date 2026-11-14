#!/usr/bin/env bash
# Scan the full git history for committed secrets with the pinned gitleaks
# binary. Config is .gitleaks.toml; confirmed false positives go in
# .gitleaksignore by fingerprint. Run locally with `make secret-scan`.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

# The pipeline checkout may be shallow; the scan has to see every commit.
if [[ "$(git rev-parse --is-shallow-repository)" == true ]]; then
  echo "the checkout is shallow; fetching the full history"
  git fetch --quiet --unshallow origin \
    || git fetch --quiet --unshallow "https://github.com/ankraio/ankra-charts.git"
fi
echo "scanning $(git rev-list --count HEAD) commits"

# --redact keeps any matched secret out of the step log.
gitleaks git . --redact --verbose --no-banner
