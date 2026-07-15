#!/usr/bin/env bash
set -euo pipefail

root="${1:-.}"

while IFS= read -r chart_directory; do
  printf '%s\n' "${chart_directory}"
done < <(
  find "${root}" -mindepth 2 -maxdepth 2 -name Chart.yaml -exec dirname {} \; \
    | sed "s|^${root%/}/||" \
    | sort
)
