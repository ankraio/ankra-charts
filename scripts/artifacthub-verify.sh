#!/usr/bin/env bash
set -euo pipefail

# Verify that every chart version published to the GitHub Pages Helm repo has
# actually been ingested by Artifact Hub.
#
# Artifact Hub rejects a package version silently from the publisher's point of
# view: the tracker records the reason in last_tracking_errors and then refuses
# to re-process until the index.yaml digest changes, so one bad annotation can
# keep a chart unlisted indefinitely while CI stays green. This script closes
# that gap and needs no API credentials — every endpoint it reads is public.
#
# Exit codes:
#   0  repository registered, no tracking errors, every version indexed
#   1  a verification check failed
#   2  the repository is not registered on Artifact Hub yet

artifacthub_api_base="${ARTIFACTHUB_API_BASE:-https://artifacthub.io/api/v1}"
artifacthub_organization="${ARTIFACTHUB_ORG:-ankra}"
pages_url="${PAGES_URL:-https://ankraio.github.io/ankra-charts}"
repository_name="${ARTIFACTHUB_REPO_NAME:-ankra-charts}"
index_source="${1:-${pages_url}/index.yaml}"

failure_count=0

report_failure() {
  printf '::error::%s\n' "$1" >&2
  failure_count=$((failure_count + 1))
}

read_index_yaml() {
  if [[ -f "${index_source}" ]]; then
    cat "${index_source}"
  else
    curl -sSfL "${index_source}"
  fi
}

index_yaml="$(read_index_yaml)"

if [[ -z "${index_yaml}" ]]; then
  printf '::error::Could not read the Helm repo index from %s\n' "${index_source}" >&2
  exit 1
fi

# "<chart> <version>" per line, straight out of the published index.
published_versions="$(printf '%s' "${index_yaml}" | python3 -c '
import sys, yaml

index = yaml.safe_load(sys.stdin) or {}
for chart_name, releases in sorted((index.get("entries") or {}).items()):
    for release in releases or []:
        version = release.get("version")
        if version:
            print(f"{chart_name} {version}")
')"

if [[ -z "${published_versions}" ]]; then
  printf '::error::No chart entries found in %s\n' "${index_source}" >&2
  exit 1
fi

printf 'Verifying %s chart version(s) from %s\n\n' \
  "$(printf '%s\n' "${published_versions}" | wc -l | tr -d ' ')" "${index_source}"

# Look the repository up by URL alone. The URL is unique across Artifact Hub, and
# combining it with org= silently returns nothing for a freshly added repository
# — the org filter only picks it up once ownership has been established, so an
# org-scoped query reports a registered repo as missing.
repository_json="$(curl -sSfL \
  "${artifacthub_api_base}/repositories/search?url=${pages_url}")"
repository_id="$(printf '%s' "${repository_json}" | jq -r '.[0].repository_id // empty')"
repository_organization="$(printf '%s' "${repository_json}" | jq -r '.[0].organization_name // empty')"

if [[ -z "${repository_id}" ]]; then
  cat >&2 <<EOF
::error::Helm repository ${pages_url} is not registered on Artifact Hub.

Nothing will ever be published until the repository is added once, by hand:

  1. Sign in at https://artifacthub.io as a member of the "${artifacthub_organization}" organization.
  2. Control Panel -> Repositories -> Add, with:
       Kind:         Helm charts
       Name:         ${repository_name}
       Display name: Ankra Charts
       URL:          ${pages_url}
  3. Re-run this workflow.

After that Artifact Hub re-indexes the repo automatically (~30 min) on every
index.yaml change, so new chart versions publish with no further action.
EOF
  exit 2
fi

printf 'Repository registered: %s (id %s, org %s)\n' \
  "${repository_name}" "${repository_id}" "${repository_organization:-unknown}"

if [[ -n "${repository_organization}" && "${repository_organization}" != "${artifacthub_organization}" ]]; then
  report_failure "${pages_url} is registered under organization '${repository_organization}', expected '${artifacthub_organization}'"
fi

# Tracking errors are reported but not fatal on their own: Artifact Hub keeps
# the last error around after a bad version is withdrawn from the index, which
# would otherwise leave this check permanently red. An error that still blocks a
# live version is caught by the per-version check below, which is fatal.
tracking_errors="$(printf '%s' "${repository_json}" | jq -r '.[0].last_tracking_errors // empty')"
if [[ -n "${tracking_errors}" ]]; then
  printf '::warning::Artifact Hub reported tracking errors for %s:\n' "${repository_name}" >&2
  printf '%s\n\n' "${tracking_errors}" >&2
fi

while read -r chart_name chart_version; do
  [[ -n "${chart_name}" ]] || continue

  package_json="$(curl -sSL \
    "${artifacthub_api_base}/packages/helm/${repository_name}/${chart_name}" || true)"
  indexed_versions="$(printf '%s' "${package_json}" \
    | jq -r '.available_versions[]?.version' 2>/dev/null || true)"

  if [[ -z "${indexed_versions}" ]]; then
    report_failure "${chart_name}: not indexed on Artifact Hub at all"
    continue
  fi

  if printf '%s\n' "${indexed_versions}" | grep -qxF "${chart_version}"; then
    printf '  ok      %s %s\n' "${chart_name}" "${chart_version}"
  else
    report_failure "${chart_name} ${chart_version}: published to Pages but missing on Artifact Hub (indexed: $(printf '%s' "${indexed_versions}" | tr '\n' ' '))"
  fi
done <<< "${published_versions}"

printf '\n'

if [[ "${failure_count}" -gt 0 ]]; then
  printf '::error::%s Artifact Hub verification check(s) failed.\n' "${failure_count}" >&2
  exit 1
fi

printf 'All published chart versions are live on Artifact Hub.\n'
