# shellcheck shell=bash
# Sourced by every ci/*.sh script. Points every tool at the pipeline workspace:
# a step's root file system is read-only, HOME is a small tmpfs, and the
# workspace (the repository checkout) is the one volume every stage shares.

CI_REPOSITORY_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export CI_REPOSITORY_ROOT
export CI_TOOLS="${CI_TOOLS:-${CI_REPOSITORY_ROOT}/.ci-tools}"
# One scratch directory per step, so stages running side by side on the shared
# workspace never write into each other's files.
export CI_SCRATCH="${CI_SCRATCH:-${CI_REPOSITORY_ROOT}/.ci-tmp/${ANKRA_STEP_ID:-local}}"
mkdir -p "${CI_SCRATCH}"

export PATH="${CI_TOOLS}/bin:${PATH}"
export PYTHONPATH="${CI_TOOLS}/python${PYTHONPATH:+:${PYTHONPATH}}"
export HELM_CACHE_HOME="${CI_SCRATCH}/helm/cache"
export HELM_CONFIG_HOME="${CI_SCRATCH}/helm/config"
export HELM_DATA_HOME="${CI_TOOLS}/helm/data"
export HELM_PLUGINS="${CI_TOOLS}/helm/plugins"
export TRIVY_CACHE_DIR="${CI_SCRATCH}/trivy-cache"

# The checkout belongs to another user than the one a step runs as, so git
# refuses to work in it until the directory is marked safe.
if [[ -n "${ANKRA_STEP_ID:-}" ]] && ! git config --global --get-all safe.directory 2> /dev/null | grep -qx '\*'; then
  git config --global --add safe.directory '*'
fi

cd "${CI_REPOSITORY_ROOT}" || exit 1
