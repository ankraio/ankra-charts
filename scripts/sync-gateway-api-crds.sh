#!/usr/bin/env bash
# sync-gateway-api-crds.sh - Vendor the Kubernetes Gateway API standard channel
# into gateway-api-crds/templates from an upstream release tag.
# Idempotent: re-running with the same tag produces no git diff.
#
# Usage:
#   ./scripts/sync-gateway-api-crds.sh v1.5.1
#
# Every vendored object gets the helm.sh/resource-policy: keep annotation, so
# uninstalling the release never deletes the CRDs and with them every route on
# the cluster. A file carrying Helm template syntax is refused rather than
# escaped: the files are rendered verbatim, and a silent rewrite of a CRD schema
# is not something to discover later.
#
# Tools required: bash 4+, curl, jq, python3.
set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <gateway-api release tag, e.g. v1.5.1>" >&2
  exit 1
fi

tag="$1"
repository="kubernetes-sigs/gateway-api"
source_path="config/crd/standard"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
target_directory="${repository_root}/gateway-api-crds/templates"

# GITHUB_TOKEN is optional; it spares CI the shared runner rate limit.
listing_arguments=(-fsSL)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  listing_arguments+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
listing="$(curl "${listing_arguments[@]}" "https://api.github.com/repos/${repository}/contents/${source_path}?ref=${tag}")"
mapfile -t file_names < <(jq -r '.[] | select(.type == "file") | select(.name | endswith(".yaml")) | .name' <<<"${listing}")
if [[ "${#file_names[@]}" -eq 0 ]]; then
  echo "no YAML files under ${source_path} at ${tag}" >&2
  exit 1
fi

mkdir -p "${target_directory}"
find "${target_directory}" -name 'gateway.networking.k8s.io_*.yaml' -delete

for file_name in "${file_names[@]}"; do
  target_file="${target_directory}/${file_name}"
  curl -fsSL "https://raw.githubusercontent.com/${repository}/${tag}/${source_path}/${file_name}" -o "${target_file}"
  if grep -q '{{' "${target_file}"; then
    echo "${file_name} carries Helm template syntax; refusing to vendor it verbatim" >&2
    exit 1
  fi
  python3 - "${target_file}" <<'EDIT'
import sys

path = sys.argv[1]
keep = "    helm.sh/resource-policy: keep\n"
output = []
in_metadata = False
for line in open(path, encoding="utf-8"):
    output.append(line)
    if line.rstrip("\n") == "metadata:":
        in_metadata = True
        continue
    if in_metadata and line.rstrip("\n") == "  annotations:":
        output.append(keep)
        in_metadata = False
        continue
    if in_metadata and line and not line.startswith(" "):
        in_metadata = False
with open(path, "w", encoding="utf-8") as handle:
    handle.writelines(output)
text = "".join(output)
documents = [part for part in text.split("\n---") if "kind:" in part]
missing = [part for part in documents if keep not in part]
if missing:
    raise SystemExit(f"{path}: {len(missing)} of {len(documents)} objects have no metadata.annotations to mark keep")
EDIT
done

echo "vendored ${#file_names[@]} files from ${repository}@${tag} into gateway-api-crds/templates"
