#!/usr/bin/env bash
# sync-kamaji.sh - Vendor the Kamaji Helm chart (charts/kamaji in clastix/kamaji)
# into kamaji/ from an upstream edge tag.
# Idempotent: re-running with the same tag produces no git diff.
#
# Usage:
#   ./scripts/sync-kamaji.sh 26.11.4-edge
#
# Upstream publishes only a floating 0.0.0+latest chart that follows master, and
# only weekly edge image tags, so the chart is pinned by vendoring it from a tag.
# Every file is copied verbatim, plus upstream's LICENSE and NOTICE, except:
#   Chart.yaml   version is the tag without -edge (plain semver, never a
#                prerelease), appVersion is the tag, the kamaji-etcd dependency
#                is dropped (Ankra renders its own etcd)
#   Chart.lock   removed with the dependency
#   values.yaml  image.tag is the tag, so nothing floats to latest; the
#                kamaji-etcd block is dropped; defaultDatastoreName is "";
#                telemetry.disabled is true
#   README.md    a header saying where the chart came from
# An edit that no longer matches upstream fails the sync rather than being
# skipped: a changed chart shape needs a person to look at it.
#
# Tools required: bash, curl, python3 3.12+.
set -euo pipefail
IFS=$'\n\t'

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <kamaji edge tag, e.g. 26.11.4-edge>" >&2
  exit 1
fi

tag="$1"
if [[ ! "${tag}" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-edge$ ]]; then
  echo "${tag} is not an edge tag of the form <year>.<month>.<n>-edge" >&2
  exit 1
fi
chart_version="${BASH_REMATCH[1]}"
repository="clastix/kamaji"
repository_root="$(cd "$(dirname "$0")/.." && pwd)"
target_directory="${repository_root}/kamaji"

scratch="$(mktemp -d)"
trap 'rm -rf "${scratch}"' EXIT

# GITHUB_TOKEN is optional; it spares CI the shared runner rate limit.
download_arguments=(-fsSL)
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
  download_arguments+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
curl "${download_arguments[@]}" "https://api.github.com/repos/${repository}/tarball/${tag}" -o "${scratch}/kamaji.tar.gz"

rm -rf "${target_directory}"
mkdir -p "${target_directory}"

python3 -I - "${scratch}/kamaji.tar.gz" "${target_directory}" "${tag}" "${chart_version}" "${repository}" <<'VENDOR'
import pathlib
import re
import sys
import tarfile

archive_path, target, tag, chart_version, repository = sys.argv[1:6]
target = pathlib.Path(target)

with tarfile.open(archive_path, "r:gz") as archive:
    members = archive.getmembers()
    top = members[0].name.split("/", 1)[0]
    commit = top.rsplit("-", 1)[-1]
    chart_prefix = f"{top}/charts/kamaji/"
    wanted = {f"{top}/LICENSE": "LICENSE", f"{top}/NOTICE": "NOTICE"}
    copied = 0
    for member in members:
        if member.name.startswith(chart_prefix):
            relative = member.name[len(chart_prefix):]
        elif member.name in wanted:
            relative = wanted[member.name]
        else:
            continue
        if member.isdir():
            continue
        if not member.isfile():
            raise SystemExit(f"{member.name} is not a regular file; refusing to vendor it")
        destination = target / relative
        if target.resolve() not in destination.resolve().parents:
            raise SystemExit(f"{member.name} would land outside {target}")
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(archive.extractfile(member).read())
        copied += 1
if copied == 0:
    raise SystemExit(f"no charts/kamaji in {repository}@{tag}")


def replace_once(text, pattern, replacement, what):
    updated, count = re.subn(pattern, replacement, text, count=1, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(f"{what}: upstream no longer matches {pattern!r}")
    return updated


def drop_block(lines, key, what):
    """Drop a top-level key, its indented body and the comments right above it."""
    try:
        start = lines.index(f"{key}:\n")
    except ValueError:
        raise SystemExit(f"{what}: upstream has no top-level {key}")
    end = start + 1
    while end < len(lines) and (lines[end].startswith((" ", "-")) or lines[end].strip() == ""):
        end += 1
    while end > start + 1 and lines[end - 1].strip() == "":
        end -= 1
    while start > 0 and lines[start - 1].startswith("#"):
        start -= 1
    if end < len(lines) and lines[end].strip() == "" and start > 0 and lines[start - 1].strip() == "":
        end += 1
    return lines[:start] + lines[end:]


chart_path = target / "Chart.yaml"
chart = chart_path.read_text(encoding="utf-8")
chart = replace_once(chart, r"^version: .*$", f"version: {chart_version}", "Chart.yaml version")
chart = replace_once(chart, r"^appVersion: .*$", f'appVersion: "{tag}"', "Chart.yaml appVersion")
chart_lines = chart.splitlines(keepends=True)
chart_lines = drop_block(chart_lines, "dependencies", "Chart.yaml dependencies")
chart = "".join(chart_lines)
if "kamaji-etcd" in chart:
    raise SystemExit("Chart.yaml still names kamaji-etcd after the dependency was dropped")
chart_path.write_text(chart, encoding="utf-8")
(target / "Chart.lock").unlink(missing_ok=True)

values_path = target / "values.yaml"
values = values_path.read_text(encoding="utf-8")
values = replace_once(values, r"^(image:\n(?:  .*\n|\s*\n)*?  tag:).*$", rf'\g<1> "{tag}"', "values.yaml image.tag")
values = replace_once(values, r"^defaultDatastoreName: .*$", 'defaultDatastoreName: ""', "values.yaml defaultDatastoreName")
values = replace_once(values, r"^(telemetry:\n  disabled:) false$", r"\g<1> true", "values.yaml telemetry.disabled")
values_lines = values.splitlines(keepends=True)
values_lines = drop_block(values_lines, "kamaji-etcd", "values.yaml kamaji-etcd")
values = "".join(values_lines)
if re.search(r"^kamaji-etcd:", values, flags=re.MULTILINE):
    raise SystemExit("values.yaml still carries a kamaji-etcd block")
values_path.write_text(values, encoding="utf-8")

readme_path = target / "README.md"
header = (
    f"> **Vendored by Ankra** from [`{repository}`](https://github.com/{repository}) "
    f"`charts/kamaji` at tag `{tag}` (commit `{commit}`), Apache-2.0 (see [LICENSE](LICENSE) and [NOTICE](NOTICE)).\n"
    f"> Chart version `{chart_version}`, image pinned to `{tag}`. The `kamaji-etcd` subchart is removed, "
    "`defaultDatastoreName` defaults to `\"\"` and telemetry is off. "
    "Re-vendor with `scripts/sync-kamaji.sh <tag>`; the upstream text below is unchanged.\n\n"
)
readme_path.write_text(header + readme_path.read_text(encoding="utf-8"), encoding="utf-8")

print(f"vendored {copied} files from {repository}@{tag} (commit {commit}) into kamaji/ as chart {chart_version}")
VENDOR
