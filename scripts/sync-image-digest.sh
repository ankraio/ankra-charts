#!/usr/bin/env bash
#
# Resolve the container image digest a chart pins, and keep Chart.yaml in step.
#
# Charts in this repository pin `image.digest` so that a moved tag cannot change
# what runs. That pin has to be refreshed deliberately, which is what this does.
#
# Usage:
#   scripts/sync-image-digest.sh <chart> [tag|latest|check]
#
#   scripts/sync-image-digest.sh hermes-agent          # re-resolve the pinned tag
#   scripts/sync-image-digest.sh hermes-agent latest   # move to the newest tag
#   scripts/sync-image-digest.sh hermes-agent v2026.8.16
#   scripts/sync-image-digest.sh hermes-agent check    # report only, never write
#
# Exit codes:
#   0  no change, or the digest was refreshed for the same tag
#   1  error
#   2  the pinned tag changed - the appVersion moved, so review before merging
#
# Only anonymous pulls from Docker Hub and GHCR are supported; both are enough
# for the public images these charts reference.

set -euo pipefail

CHART="${1:-}"
TARGET="${2:-}"

if [[ -z "${CHART}" ]]; then
  echo "usage: $0 <chart> [tag|latest|check]" >&2
  exit 1
fi

REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHART_DIRECTORY="${REPOSITORY_ROOT}/${CHART}"
VALUES_FILE="${CHART_DIRECTORY}/values.yaml"
CHART_FILE="${CHART_DIRECTORY}/Chart.yaml"

for required_file in "${VALUES_FILE}" "${CHART_FILE}"; do
  if [[ ! -f "${required_file}" ]]; then
    echo "not a chart directory: ${CHART_DIRECTORY} (missing $(basename "${required_file}"))" >&2
    exit 1
  fi
done

for required_tool in curl jq yq; do
  if ! command -v "${required_tool}" >/dev/null 2>&1; then
    echo "missing required tool: ${required_tool}" >&2
    exit 1
  fi
done

REGISTRY="$(yq -r '.image.registry // "docker.io"' "${VALUES_FILE}")"
REPOSITORY="$(yq -r '.image.repository' "${VALUES_FILE}")"
CURRENT_TAG="$(yq -r '.image.tag // ""' "${VALUES_FILE}")"
CURRENT_DIGEST="$(yq -r '.image.digest // ""' "${VALUES_FILE}")"

if [[ -z "${REPOSITORY}" || "${REPOSITORY}" == "null" ]]; then
  echo "${CHART}: values.yaml has no image.repository" >&2
  exit 1
fi

case "${REGISTRY}" in
  docker.io|index.docker.io|registry-1.docker.io)
    REGISTRY_HOST="registry-1.docker.io"
    AUTH_URL="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPOSITORY}:pull"
    # Docker Hub official images live under library/.
    if [[ "${REPOSITORY}" != */* ]]; then
      REPOSITORY="library/${REPOSITORY}"
      AUTH_URL="https://auth.docker.io/token?service=registry.docker.io&scope=repository:${REPOSITORY}:pull"
    fi
    ;;
  ghcr.io)
    REGISTRY_HOST="ghcr.io"
    AUTH_URL="https://ghcr.io/token?service=ghcr.io&scope=repository:${REPOSITORY}:pull"
    ;;
  *)
    echo "unsupported registry: ${REGISTRY} (docker.io and ghcr.io only)" >&2
    exit 1
    ;;
esac

TOKEN="$(curl -fsSL "${AUTH_URL}" | jq -r '.token // .access_token')"
if [[ -z "${TOKEN}" || "${TOKEN}" == "null" ]]; then
  echo "could not obtain a pull token for ${REGISTRY}/${REPOSITORY}" >&2
  exit 1
fi

MANIFEST_ACCEPT='application/vnd.oci.image.index.v1+json,application/vnd.docker.distribution.manifest.list.v2+json,application/vnd.oci.image.manifest.v1+json,application/vnd.docker.distribution.manifest.v2+json'

resolve_digest() {
  local tag="$1"
  curl -fsSI \
    -H "Authorization: Bearer ${TOKEN}" \
    -H "Accept: ${MANIFEST_ACCEPT}" \
    "https://${REGISTRY_HOST}/v2/${REPOSITORY}/manifests/${tag}" \
    | tr -d '\r' \
    | awk 'tolower($1) == "docker-content-digest:" { print $2 }'
}

list_tags() {
  curl -fsSL \
    -H "Authorization: Bearer ${TOKEN}" \
    "https://${REGISTRY_HOST}/v2/${REPOSITORY}/tags/list?n=1000" \
    | jq -r '.tags[]?'
}

newest_tag() {
  # Version-like tags only: no latest, main, edge, or -rc builds.
  list_tags \
    | grep -E '^v?[0-9]+(\.[0-9]+)+$' \
    | sort -V \
    | tail -1
}

case "${TARGET}" in
  check)
    latest="$(newest_tag || true)"
    resolved="$(resolve_digest "${CURRENT_TAG}" || true)"
    printf 'chart:      %s\n' "${CHART}"
    printf 'image:      %s/%s\n' "${REGISTRY}" "${REPOSITORY}"
    printf 'pinned tag: %s\n' "${CURRENT_TAG}"
    printf 'pinned sha: %s\n' "${CURRENT_DIGEST:-<none>}"
    printf 'registry:   %s\n' "${resolved:-<tag not found>}"
    printf 'newest tag: %s\n' "${latest:-<none>}"
    if [[ -n "${resolved}" && "${resolved}" != "${CURRENT_DIGEST}" ]]; then
      printf 'status:     DIGEST DRIFT - the pinned tag now resolves elsewhere\n'
    elif [[ -n "${latest}" && "${latest}" != "${CURRENT_TAG}" ]]; then
      printf 'status:     BEHIND - %s is available\n' "${latest}"
    else
      printf 'status:     up to date\n'
    fi
    exit 0
    ;;
  latest)
    TARGET_TAG="$(newest_tag)"
    if [[ -z "${TARGET_TAG}" ]]; then
      echo "no version-like tags found for ${REGISTRY}/${REPOSITORY}" >&2
      exit 1
    fi
    ;;
  "")
    TARGET_TAG="${CURRENT_TAG}"
    ;;
  *)
    TARGET_TAG="${TARGET}"
    ;;
esac

if [[ -z "${TARGET_TAG}" ]]; then
  echo "${CHART}: no tag to resolve; pass one explicitly" >&2
  exit 1
fi

TARGET_DIGEST="$(resolve_digest "${TARGET_TAG}")"
if [[ -z "${TARGET_DIGEST}" ]]; then
  echo "${REGISTRY}/${REPOSITORY}:${TARGET_TAG} does not exist" >&2
  exit 1
fi

if [[ "${TARGET_TAG}" == "${CURRENT_TAG}" && "${TARGET_DIGEST}" == "${CURRENT_DIGEST}" ]]; then
  echo "${CHART}: already pinned to ${TARGET_TAG} (${TARGET_DIGEST})"
  exit 0
fi

# Rewrite the specific lines rather than round-tripping the YAML: yq would drop
# every blank line and comment layout in these hand-maintained files.
IMAGE_REFERENCE="${REGISTRY}/$(yq -r '.image.repository' "${VALUES_FILE}"):${TARGET_TAG}@${TARGET_DIGEST}"
python3 - "${VALUES_FILE}" "${CHART_FILE}" "${TARGET_TAG}" "${TARGET_DIGEST}" "${IMAGE_REFERENCE}" <<'PYTHON'
import re
import sys

values_file, chart_file, tag, digest, image_reference = sys.argv[1:6]


def rewrite(path, substitutions):
    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    for pattern, replacement in substitutions:
        content, count = re.subn(pattern, replacement, content, count=1)
        if not count:
            raise SystemExit(f"{path}: no line matched {pattern!r}")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(content)


# Only the tag/digest lines inside the top-level image: block.
image_block = re.compile(r"(?ms)^image:\n(?:[ \t].*\n|\n)*")
with open(values_file, encoding="utf-8") as handle:
    values_content = handle.read()
match = image_block.search(values_content)
if match is None:
    raise SystemExit(f"{values_file}: no top-level image: block")
block = match.group(0)
block = re.sub(r"(?m)^(\s+tag:\s*).*$", lambda m: m.group(1) + tag, block, count=1)
block = re.sub(r"(?m)^(\s+digest:\s*).*$", lambda m: m.group(1) + digest, block, count=1)
values_content = values_content[: match.start()] + block + values_content[match.end() :]
with open(values_file, "w", encoding="utf-8") as handle:
    handle.write(values_content)

rewrite(
    chart_file,
    [
        (r'(?m)^appVersion:\s*.*$', f'appVersion: "{tag}"'),
        (r"(?m)^(\s+image: )\S+$", lambda m: m.group(1) + image_reference),
    ],
)
PYTHON

echo "${CHART}: ${CURRENT_TAG:-<none>} (${CURRENT_DIGEST:-<none>}) -> ${TARGET_TAG} (${TARGET_DIGEST})"

if [[ "${TARGET_TAG}" != "${CURRENT_TAG}" ]]; then
  echo "appVersion moved to ${TARGET_TAG}; bump the chart version before publishing." >&2
  exit 2
fi
exit 0
