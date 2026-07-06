#!/usr/bin/env bash
set -euo pipefail

artifacthub_api_base="${ARTIFACTHUB_API_BASE:-https://artifacthub.io/api/v1}"
artifacthub_organization="${ARTIFACTHUB_ORG:?ARTIFACTHUB_ORG is required}"
artifacthub_api_key_id="${ARTIFACTHUB_API_KEY_ID:?ARTIFACTHUB_API_KEY_ID is required}"
artifacthub_api_key_secret="${ARTIFACTHUB_API_KEY_SECRET:?ARTIFACTHUB_API_KEY_SECRET is required}"
pages_directory="${1:?gh-pages directory path is required}"
pages_url="${PAGES_URL:-https://ankraio.github.io/ankra-charts}"
repository_name="${ARTIFACTHUB_REPO_NAME:-ankra-charts}"
repository_display_name="${ARTIFACTHUB_REPO_DISPLAY_NAME:-Ankra Charts}"
repository_kind="${ARTIFACTHUB_REPO_KIND:-0}"
artifacthub_repo_file="${pages_directory}/artifacthub-repo.yml"

artifacthub_request() {
  local method="$1"
  local path="$2"
  local body="${3:-}"

  if [[ -n "${body}" ]]; then
    curl -sS -X "${method}" "${artifacthub_api_base}${path}" \
      -H "X-API-KEY-ID: ${artifacthub_api_key_id}" \
      -H "X-API-KEY-SECRET: ${artifacthub_api_key_secret}" \
      -H "Content-Type: application/json" \
      --data "${body}"
  else
    curl -sS -X "${method}" "${artifacthub_api_base}${path}" \
      -H "X-API-KEY-ID: ${artifacthub_api_key_id}" \
      -H "X-API-KEY-SECRET: ${artifacthub_api_key_secret}"
  fi
}

find_repository_id() {
  artifacthub_request GET \
    "/repositories/search?org=${artifacthub_organization}&url=${pages_url}" \
    | jq -r '.[0].repository_id // empty'
}

register_repository() {
  local payload
  payload="$(jq -nc \
    --arg kind "${repository_kind}" \
    --arg name "${repository_name}" \
    --arg display_name "${repository_display_name}" \
    --arg url "${pages_url}" \
    '{kind: ($kind | tonumber), name: $name, display_name: $display_name, url: $url}')"

  local response http_status
  response="$(curl -sS -w '\n%{http_code}' -X POST \
    "${artifacthub_api_base}/repositories/org/${artifacthub_organization}" \
    -H "X-API-KEY-ID: ${artifacthub_api_key_id}" \
    -H "X-API-KEY-SECRET: ${artifacthub_api_key_secret}" \
    -H "Content-Type: application/json" \
    --data "${payload}")"
  http_status="${response##*$'\n'}"
  response="${response%$'\n'*}"

  if [[ "${http_status}" == "201" ]]; then
    find_repository_id
    return 0
  fi

  if [[ "${http_status}" == "409" ]] || printf '%s' "${response}" | jq -e '.message | test("already exists"; "i")' >/dev/null 2>&1; then
    find_repository_id
    return 0
  fi

  echo "ArtifactHub repository registration failed (${http_status}): ${response}" >&2
  return 1
}

write_artifacthub_repo_file() {
  local repository_id="$1"

  cat > "${artifacthub_repo_file}" <<EOF
# ArtifactHub repository metadata.
# repositoryID is populated automatically by charts-pages CI and is used by
# ArtifactHub to verify ownership of this Helm repository.
repositoryID: "${repository_id}"
owners:
  - name: Ankra AB
    email: admin@ankra.io
EOF
}

claim_repository_ownership() {
  artifacthub_request PUT \
    "/repositories/org/${artifacthub_organization}/${repository_name}/claim-ownership" \
    >/dev/null
}

if [[ "${ARTIFACTHUB_ACTION:-sync}" == "claim" ]]; then
  echo "Claiming ArtifactHub repository ownership for ${artifacthub_organization}/${repository_name}"
  claim_repository_ownership || true
  exit 0
fi

repository_id="$(find_repository_id)"
if [[ -z "${repository_id}" ]]; then
  echo "Registering ArtifactHub repository ${artifacthub_organization}/${repository_name} for ${pages_url}"
  repository_id="$(register_repository)"
fi

if [[ -z "${repository_id}" ]]; then
  echo "Could not resolve ArtifactHub repository ID for ${pages_url}" >&2
  exit 1
fi

echo "ArtifactHub repository ID: ${repository_id}"
write_artifacthub_repo_file "${repository_id}"
