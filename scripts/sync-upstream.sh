#!/usr/bin/env bash
# sync-upstream.sh - Sync upcloud-charts/{upcloud-ccm,upcloud-csi} with the
# latest UpCloud upstream releases. Idempotent: re-running with the same
# version produces no git diff.
#
# Usage:
#   ./scripts/sync-upstream.sh check                  # print latest upstream versions, no writes
#   ./scripts/sync-upstream.sh ccm [version]          # bump CCM appVersion (e.g. v1.2.3); default: latest
#   ./scripts/sync-upstream.sh csi [version]          # re-vendor + bump CSI appVersion; default: latest
#
# Exit codes:
#   0 - success, no structural change (image-tag-only diff). Safe to auto-merge.
#   1 - error (network, missing tool, validation failure).
#   2 - success, but structural change detected in vendored YAML. Workflow
#       should label the resulting PR `needs-review`.
#
# Tools required:
#   curl, yq (mikefarah), python3, sed, awk, jq.
#   Optional: crane (for CCM GHCR tag fallback + digest extraction).
set -euo pipefail
IFS=$'\n\t'

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
CHARTS_DIR="${REPO_ROOT}/upcloud-charts"
CCM_DIR="${CHARTS_DIR}/upcloud-ccm"
CSI_DIR="${CHARTS_DIR}/upcloud-csi"
CSI_VENDOR_DIR="${CSI_DIR}/vendor"

CCM_GHCR_IMAGE="ghcr.io/upcloudltd/cloud-controller-manager"
CCM_GH_REPO="UpCloudLtd/cloud-controller-manager"
CSI_GH_REPO="UpCloudLtd/upcloud-csi"

# -------------------------------------------------------------------------
# Helpers
# -------------------------------------------------------------------------

log() { printf '[sync-upstream] %s\n' "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "required tool not found: $1"
}

# Read current appVersion from a chart's Chart.yaml.
read_chart_appversion() {
    local chart_dir=$1
    grep -E '^appVersion:' "${chart_dir}/Chart.yaml" | awk '{print $2}' | tr -d '"'
}

# Read current chart version from a chart's Chart.yaml.
read_chart_version() {
    local chart_dir=$1
    grep -E '^version:' "${chart_dir}/Chart.yaml" | awk '{print $2}' | tr -d '"'
}

# Bump the patch part of a SemVer x.y.z.
bump_patch() {
    local v=$1
    local IFS=.
    # shellcheck disable=SC2206
    local parts=($v)
    local p=${parts[2]:-0}
    p=$((p + 1))
    printf '%s.%s.%s\n' "${parts[0]:-0}" "${parts[1]:-0}" "$p"
}

# Replace `appVersion: <whatever>` and `version: <whatever>` in a Chart.yaml.
patch_chart_yaml() {
    local chart_dir=$1 app_version=$2 chart_version=$3
    local f="${chart_dir}/Chart.yaml"
    # Cross-platform sed (BSD/GNU).
    sed -i.bak -E "s|^appVersion:.*$|appVersion: \"${app_version}\"|" "$f"
    sed -i.bak -E "s|^version:.*$|version: ${chart_version}|" "$f"
    rm -f "${f}.bak"
}

# Format-preserving in-place edit of a single nested `tag:` / `digest:` field
# inside a values.yaml `images.<key>:` block. Uses Python (which is available
# everywhere `yq` is) and walks the file line by line, looking for the matching
# image block and patching the requested sub-field while leaving every other
# byte alone — comments, blank lines, indentation all preserved.
patch_values_image_field() {
    local file=$1 image_key=$2 field=$3 value=$4
    require_tool python3
    python3 - "$file" "$image_key" "$field" "$value" <<'PY'
import re
import sys

path, image_key, field, value = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as f:
    lines = f.read().splitlines()

# Find the `images:` line, then the `  <image_key>:` line, then the
# `    <field>:` line and patch it in place. Indentation is significant.
out = []
state = "before_images"   # before_images | in_images | in_target_image
img_re = re.compile(r"^(\s*)" + re.escape(image_key) + r":\s*$")
field_re = re.compile(r"^(\s*)" + re.escape(field) + r":\s*.*$")
images_re = re.compile(r"^images:\s*$")
top_level_re = re.compile(r"^\S")   # any non-indented line resets state
patched = False

for line in lines:
    if state == "before_images" and images_re.match(line):
        state = "in_images"
        out.append(line)
        continue
    if state == "in_images":
        # Leaving the images block.
        if top_level_re.match(line) and not line.startswith("images:"):
            state = "before_images"
            out.append(line)
            continue
        m = img_re.match(line)
        if m:
            state = "in_target_image"
            out.append(line)
            continue
        out.append(line)
        continue
    if state == "in_target_image":
        # Leaving the image block (next image key at the same indent or
        # outdent to top-level).
        if re.match(r"^\s{2}\S", line) and not re.match(r"^\s{4,}", line):
            state = "in_images"
            # Fall through to re-evaluate this line.
            if img_re.match(line):
                out.append(line)
                state = "in_target_image"
                continue
            if top_level_re.match(line) and not line.startswith("images:"):
                state = "before_images"
            out.append(line)
            continue
        if top_level_re.match(line):
            state = "before_images"
            out.append(line)
            continue
        m = field_re.match(line)
        if m and not patched:
            indent = m.group(1)
            # Preserve any trailing inline comment on the original line.
            comment_match = re.match(r"^\s*\S+:\s*\S*(\s+#.*)?$", line)
            comment = (comment_match.group(1) or "") if comment_match else ""
            out.append(f'{indent}{field}: "{value}"{comment}')
            patched = True
            continue
        out.append(line)
        continue
    out.append(line)

if not patched:
    sys.stderr.write(
        f"[sync-upstream] WARN: did not find images.{image_key}.{field} in {path}\n"
    )

with open(path, "w", encoding="utf-8") as f:
    f.write("\n".join(out) + "\n")
PY
}

patch_csi_image_tag() {
    patch_values_image_field "${CSI_DIR}/values.yaml" "$1" tag "$2"
}

patch_csi_image_digest() {
    patch_values_image_field "${CSI_DIR}/values.yaml" "$1" digest "$2"
}

patch_ccm_image_tag() {
    patch_values_image_field "${CCM_DIR}/values.yaml" ccm tag "$1"
}

patch_ccm_image_digest() {
    patch_values_image_field "${CCM_DIR}/values.yaml" ccm digest "$1"
}

# Honour GITHUB_TOKEN to dodge rate limits in CI and authenticated local runs.
gh_curl() {
    local -a auth=()
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        auth=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
    fi
    curl -sS -H "Accept: application/vnd.github+json" "${auth[@]}" "$@"
}

# Fetch latest release tag from GitHub releases API. Empty if 404 or no releases.
gh_latest_release() {
    local repo=$1
    local url="https://api.github.com/repos/${repo}/releases/latest"
    local status body
    body=$(gh_curl -w "\n%{http_code}" "${url}" || true)
    status=$(printf '%s' "$body" | tail -n1)
    body=$(printf '%s' "$body" | sed '$ d')
    if [[ "$status" == "200" ]]; then
        printf '%s' "$body" | jq -r .tag_name
    elif [[ "$status" == "403" ]]; then
        log "GitHub API rate-limited (HTTP 403). Set GITHUB_TOKEN to authenticate."
    fi
}

# Fetch release body text.
gh_release_body() {
    local repo=$1 tag=$2
    gh_curl --fail "https://api.github.com/repos/${repo}/releases/tags/${tag}" | jq -r '.body // ""'
}

# Fall back to the highest SemVer tag visible on GHCR for the given image.
# Requires `crane`; returns empty if crane is unavailable.
ghcr_latest_tag() {
    local image=$1
    if ! command -v crane >/dev/null 2>&1; then
        log "crane not found; skipping GHCR tag fallback"
        return 0
    fi
    crane ls "${image}" 2>/dev/null \
        | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -n1
}

# Resolve an image digest via `crane`. Returns empty on failure.
image_digest() {
    local image=$1
    if ! command -v crane >/dev/null 2>&1; then
        log "crane not found; skipping digest pinning for ${image}"
        return 0
    fi
    crane digest "${image}" 2>/dev/null || true
}

# -------------------------------------------------------------------------
# Subcommands
# -------------------------------------------------------------------------

cmd_check() {
    require_tool curl
    require_tool jq

    local ccm_current ccm_latest csi_current csi_latest
    ccm_current=$(read_chart_appversion "${CCM_DIR}")
    csi_current=$(read_chart_appversion "${CSI_DIR}")
    ccm_latest=$(gh_latest_release "${CCM_GH_REPO}")
    if [[ -z "$ccm_latest" ]]; then
        ccm_latest=$(ghcr_latest_tag "${CCM_GHCR_IMAGE}")
        ccm_latest="${ccm_latest:+${ccm_latest} (via GHCR)}"
    fi
    csi_latest=$(gh_latest_release "${CSI_GH_REPO}")

    printf 'chart\tcurrent\tlatest\n'
    printf 'upcloud-ccm\t%s\t%s\n' "${ccm_current:-?}" "${ccm_latest:-?}"
    printf 'upcloud-csi\t%s\t%s\n' "${csi_current:-?}" "${csi_latest:-?}"
}

cmd_ccm() {
    require_tool curl
    require_tool jq
    require_tool yq

    local version="${1:-}"
    if [[ -z "$version" ]]; then
        version=$(gh_latest_release "${CCM_GH_REPO}")
        if [[ -z "$version" ]]; then
            log "no GitHub release for ${CCM_GH_REPO}; falling back to GHCR tag listing"
            version=$(ghcr_latest_tag "${CCM_GHCR_IMAGE}")
        fi
    fi
    [[ -n "$version" ]] || die "could not determine latest CCM version (no GH release, no GHCR fallback)"

    log "syncing CCM to ${version}"

    local current
    current=$(read_chart_appversion "${CCM_DIR}")
    if [[ "$current" == "$version" ]]; then
        log "CCM appVersion already ${version}; no-op"
        exit 0
    fi

    local new_chart_version
    new_chart_version=$(bump_patch "$(read_chart_version "${CCM_DIR}")")
    patch_chart_yaml "${CCM_DIR}" "${version}" "${new_chart_version}"

    # Best-effort: pin the image digest too.
    local digest
    digest=$(image_digest "${CCM_GHCR_IMAGE}:${version}")
    if [[ -n "$digest" ]]; then
        log "pinning CCM digest: ${digest}"
        patch_ccm_image_digest "${digest}"
    fi

    log "CCM bumped: ${current} -> ${version} (chart ${new_chart_version})"
}

cmd_csi() {
    require_tool curl
    require_tool jq
    require_tool yq

    local version="${1:-}"
    if [[ -z "$version" ]]; then
        version=$(gh_latest_release "${CSI_GH_REPO}")
    fi
    [[ -n "$version" ]] || die "could not determine latest CSI version"

    log "syncing CSI to ${version}"

    local current
    current=$(read_chart_appversion "${CSI_DIR}")
    local vendor_target="${CSI_VENDOR_DIR}/${version}"
    mkdir -p "${vendor_target}"

    # Download upstream assets.
    local assets=(crd-upcloud-csi.yaml rbac-upcloud-csi.yaml setup-upcloud-csi.yaml snapshot-webhook-upcloud-csi.yaml)
    for asset in "${assets[@]}"; do
        local url="https://github.com/UpCloudLtd/upcloud-csi/releases/download/${version}/${asset}"
        log "downloading ${asset}"
        curl -fsSL "${url}" -o "${vendor_target}/${asset}" \
            || die "failed to download ${url}"
    done

    # Swap the `current` symlink atomically.
    local tmp_link
    tmp_link="${CSI_VENDOR_DIR}/current.tmp.$$"
    ln -sfn "${version}" "${tmp_link}"
    mv -f "${tmp_link}" "${CSI_VENDOR_DIR}/current"

    # Detect structural changes vs the previous vendor snapshot.
    local structural_change=0
    if [[ "$current" != "$version" && -d "${CSI_VENDOR_DIR}/${current}" ]]; then
        log "diffing ${current} -> ${version} (setup-upcloud-csi.yaml only)"
        if diff -u \
            "${CSI_VENDOR_DIR}/${current}/setup-upcloud-csi.yaml" \
            "${vendor_target}/setup-upcloud-csi.yaml" \
            | grep -vE '^(\+\+\+|---|@@|[+-]\s+image:|[+-]\s+tag:)' \
            | grep -qE '^[+-]'
        then
            log "structural change detected in setup-upcloud-csi.yaml"
            structural_change=1
        fi
    fi

    # Extract image tags from the new setup-upcloud-csi.yaml and patch values.yaml.
    extract_and_patch_csi_tags "${vendor_target}/setup-upcloud-csi.yaml"

    # Bump Chart.yaml only when appVersion actually changed.
    if [[ "$current" != "$version" ]]; then
        local new_chart_version
        new_chart_version=$(bump_patch "$(read_chart_version "${CSI_DIR}")")
        patch_chart_yaml "${CSI_DIR}" "${version}" "${new_chart_version}"
        log "CSI bumped: ${current:-?} -> ${version} (chart ${new_chart_version})"
    else
        log "CSI appVersion already ${version}; Chart.yaml left alone"
    fi

    # Best-effort: pin the upcloud-csi driver image digest.
    local digest
    digest=$(image_digest "ghcr.io/upcloudltd/upcloud-csi:${version}")
    if [[ -n "$digest" ]]; then
        log "pinning csiDriver digest: ${digest}"
        patch_csi_image_digest "csiDriver" "${digest}"
    fi

    if [[ "$structural_change" == "1" ]]; then
        log "STRUCTURAL CHANGE detected — workflow should label PR 'needs-review'"
        exit 2
    fi
    exit 0
}

# Pull every `image: …` reference from the upstream setup-upcloud-csi.yaml
# and map it to a values.yaml key. Patches the .tag of each. Skips upstream
# `latest` tags for the csiDriver image — the chart resolves those from
# `.Chart.AppVersion` instead, which keeps `helm install` deterministic.
extract_and_patch_csi_tags() {
    local setup_yaml=$1
    require_tool yq

    # `yq` may emit `---` between docs and blank lines for nulls; filter them.
    local images
    images=$(yq -r '.. | select(has("image")) | .image' "${setup_yaml}" 2>/dev/null \
        | grep -vE '^(---|null)$' \
        | grep -v '^$' \
        | sort -u || true)

    while IFS= read -r image; do
        [[ -n "$image" ]] || continue
        local tag="${image##*:}"
        local repo="${image%:*}"
        local key=""
        case "$repo" in
            *csi-provisioner*)             key=provisioner ;;
            *csi-attacher*)                key=attacher ;;
            *csi-resizer*)                 key=resizer ;;
            *csi-snapshotter*)             key=snapshotter ;;
            *csi-node-driver-registrar*)   key=nodeDriverRegistrar ;;
            *snapshot-controller*)         key=snapshotController ;;
            *snapshot-validation-webhook*) key=snapshotValidationWebhook ;;
            *livenessprobe*)               key=livenessProbe ;;
            *ghcr.io/upcloudltd/upcloud-csi*) key=csiDriver ;;
            *)
                log "skipping unrecognised image ${image}"
                continue
                ;;
        esac
        # The upstream YAML pins the csiDriver to `:latest`; the chart pins
        # it to `.Chart.AppVersion` instead, so we keep tag empty.
        if [[ "$key" == "csiDriver" && "$tag" == "latest" ]]; then
            log "leaving images.csiDriver.tag empty (upstream uses :latest; chart uses .Chart.AppVersion)"
            patch_csi_image_tag "csiDriver" ""
            continue
        fi
        log "patching images.${key}.tag = ${tag}"
        patch_csi_image_tag "${key}" "${tag}"
    done <<<"$images"
}

# -------------------------------------------------------------------------
# Dispatcher
# -------------------------------------------------------------------------

main() {
    local cmd="${1:-}"
    shift || true
    case "$cmd" in
        check) cmd_check "$@" ;;
        ccm)   cmd_ccm   "$@" ;;
        csi)   cmd_csi   "$@" ;;
        ""|-h|--help)
            cat >&2 <<EOF
sync-upstream.sh - sync upcloud-charts with upstream UpCloud releases

Usage:
  $0 check                  # print latest upstream versions
  $0 ccm [version]          # bump upcloud-ccm appVersion (default: latest)
  $0 csi [version]          # re-vendor upcloud-csi (default: latest)

Exit codes:
  0 - success, image-tag-only diff
  1 - error
  2 - success, structural change (PR should be labeled 'needs-review')
EOF
            exit 1
            ;;
        *) die "unknown command: ${cmd}" ;;
    esac
}

main "$@"
