#!/usr/bin/env bash
# Run one command with the pipeline toolchain on PATH (ci/env.sh), for a stage
# whose work is a single command rather than a script of its own.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

exec "$@"
