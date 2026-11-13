#!/usr/bin/env bash
# Install the pinned CI toolchain into ${CI_TOOLS} (the shared pipeline
# workspace), verifying every download against the sha256/sha512 recorded here.
#
# Ankra Pipelines steps run unprivileged on a read-only root file system, so
# nothing can be installed system-wide: the `tools` stage runs this once and
# every later stage puts ${CI_TOOLS}/bin on PATH (ci/env.sh). Re-running it is a
# no-op for anything already installed. Bumping a tool means changing its
# version and both architecture hashes below.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

case "$(uname -m)" in
  x86_64 | amd64) architecture=amd64 ;;
  aarch64 | arm64) architecture=arm64 ;;
  *)
    echo "tools: unsupported architecture $(uname -m)" >&2
    exit 1
    ;;
esac

HELM_VERSION=v3.14.0
HELM_UNITTEST_VERSION=0.5.2
KUBECONFORM_VERSION=v0.6.7
YQ_VERSION=v4.44.3
JQ_VERSION=1.7.1
SHELLCHECK_VERSION=v0.10.0
GITLEAKS_VERSION=8.30.1
TRIVY_VERSION=0.75.0
CRANE_VERSION=v0.20.2
# Real kube-apiserver + etcd builds for the server-side dry-run matrix
# (ci/dry-run.sh), published by kubernetes-sigs/controller-tools.
ENVTEST_VERSIONS=(1.27.1 1.29.5 1.31.0)

declare -A sha256=(
  [helm-amd64]=f43e1c3387de24547506ab05d24e5309c0ce0b228c23bd8aa64e9ec4b8206651
  [helm-arm64]=b29e61674731b15f6ad3d1a3118a99d3cc2ab25a911aad1b8ac8c72d5a9d2952
  [helm-unittest-amd64]=36aa3d18478d717bc6a2fac1283a91c0eca347f7b22bd17b831c1c061c40bbed
  [helm-unittest-arm64]=8b4a2baa6fa3501511de7de046d715fcfaa57a8e6ddc977402a85963c4ca6f81
  [kubeconform-amd64]=95f14e87aa28c09d5941f11bd024c1d02fdc0303ccaa23f61cef67bc92619d73
  [kubeconform-arm64]=dc82f79bb03c5479b1ae5fd4af221e4b5a3111f62bf01a2795d9c5c20fa96644
  [yq-amd64]=a2c097180dd884a8d50c956ee16a9cec070f30a7947cf4ebf87d5f36213e9ed7
  [yq-arm64]=0e7e1524f68d91b3ff9b089872d185940ab0fa020a5a9052046ef10547023156
  [jq-amd64]=5942c9b0934e510ee61eb3e30273f1b3fe2590df93933a93d7c58b81d19c8ff5
  [jq-arm64]=4dd2d8a0661df0b22f1bb9a1f9830f06b6f3b8f7d91211a1ef5d7c4f06a8b4a5
  [shellcheck-amd64]=6c881ab0698e4e6ea235245f22832860544f17ba386442fe7e9d629f8cbedf87
  [shellcheck-arm64]=324a7e89de8fa2aed0d0c28f3dab59cf84c6d74264022c00c22af665ed1a09bb
  [gitleaks-amd64]=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb
  [gitleaks-arm64]=e4a487ee7ccd7d3a7f7ec08657610aa3606637dab924210b3aee62570fb4b080
  [trivy-amd64]=c6e65abddb348e25f10549df887045629cf28cc72453cd1c63acb717316b3f3f
  [trivy-arm64]=a1ee9f6ffb7d112b64ff726a2a0717c21175c1114361391f4a132956751a13b3
  [crane-amd64]=c14340087103ba9dadf61d45acd20675490fd0ccbd56ac7901fc1b502137f44b
  [crane-arm64]=aff0db48825124c9331ea310057214bd4e92c01aa2e414d539e9659841d9422a
)

declare -A envtest_sha512=(
  [1.27.1-amd64]=607ffc315583a654a7ce6d9ee1bc0ce18ba85750a13f7d972effe253a53e3bb9910f5fb083ebafd7802d39192226493013b9c88108ceeaaa8192323099cf7a9e
  [1.27.1-arm64]=4505684de16e556fea03ea2a9c60bd543dd263b3d07e56bfa2391f09a05edb7c65da3c4544e1d6b6b14b05b9ed991df88385e59911399620ae9b660d56f4a848
  [1.29.5-amd64]=b11190b9dd52e473ce57f780a145fc6e2250794a2a9fed4db9b4b13043df436a5fc66c077f1eb4808761764066a1936da27660c62d02ab5925b264f3f7caf7b5
  [1.29.5-arm64]=7cb476a57076775faec1ef6ea264bd3bb954432da0166b93c92f517869bceb51336121b4ec050bef5e5a5a1ca4dfbf3d73d56fd90acc56c90c09ed064eb92d7a
  [1.31.0-amd64]=5d96ae284610863ce5974e030aecd2eaad693f3210103ca778107aa0ea00f6f1d0a7b1b34aa74d7257cb0d7f713c2da365beba89b1d60823ce56c7b84b935423
  [1.31.0-arm64]=72f5c8fd615c9db62eeb66e30edfda0f3879bffa3577c5776ec83363c018d7f51c174ac5ea807414072a21f8151a7bdf9826f414543f690686550e49db202ca0
)

download_directory="${CI_SCRATCH}/downloads"
mkdir -p "${CI_TOOLS}/bin" "${download_directory}" "${HELM_PLUGINS}"

# fetch <url> <file> <algorithm> <expected digest>
fetch() {
  local url="$1" file="$2" algorithm="$3" expected="$4"
  curl -fsSL --retry 3 --retry-delay 2 -o "${file}" "${url}"
  if ! printf '%s  %s\n' "${expected}" "${file}" | "${algorithm}sum" --check --quiet -; then
    echo "tools: ${url} does not match its pinned ${algorithm} digest" >&2
    exit 1
  fi
}

installed() {
  [[ -x "${CI_TOOLS}/bin/$1" ]]
}

if ! installed helm; then
  fetch "https://get.helm.sh/helm-${HELM_VERSION}-linux-${architecture}.tar.gz" \
    "${download_directory}/helm.tar.gz" sha256 "${sha256[helm-${architecture}]}"
  tar -xzf "${download_directory}/helm.tar.gz" -C "${download_directory}" "linux-${architecture}/helm"
  install -m 0755 "${download_directory}/linux-${architecture}/helm" "${CI_TOOLS}/bin/helm"
fi

if [[ ! -x "${HELM_PLUGINS}/unittest/untt" ]]; then
  fetch "https://github.com/helm-unittest/helm-unittest/releases/download/v${HELM_UNITTEST_VERSION}/helm-unittest-linux-${architecture}-${HELM_UNITTEST_VERSION}.tgz" \
    "${download_directory}/helm-unittest.tgz" sha256 "${sha256[helm-unittest-${architecture}]}"
  mkdir -p "${HELM_PLUGINS}/unittest"
  tar -xzf "${download_directory}/helm-unittest.tgz" -C "${HELM_PLUGINS}/unittest" plugin.yaml untt
  chmod 0755 "${HELM_PLUGINS}/unittest/untt"
fi

if ! installed kubeconform; then
  fetch "https://github.com/yannh/kubeconform/releases/download/${KUBECONFORM_VERSION}/kubeconform-linux-${architecture}.tar.gz" \
    "${download_directory}/kubeconform.tar.gz" sha256 "${sha256[kubeconform-${architecture}]}"
  tar -xzf "${download_directory}/kubeconform.tar.gz" -C "${CI_TOOLS}/bin" kubeconform
fi

if ! installed yq; then
  fetch "https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/yq_linux_${architecture}" \
    "${CI_TOOLS}/bin/yq" sha256 "${sha256[yq-${architecture}]}"
  chmod 0755 "${CI_TOOLS}/bin/yq"
fi

if ! installed jq; then
  fetch "https://github.com/jqlang/jq/releases/download/jq-${JQ_VERSION}/jq-linux-${architecture}" \
    "${CI_TOOLS}/bin/jq" sha256 "${sha256[jq-${architecture}]}"
  chmod 0755 "${CI_TOOLS}/bin/jq"
fi

if ! installed shellcheck; then
  shellcheck_architecture=x86_64
  [[ "${architecture}" == arm64 ]] && shellcheck_architecture=aarch64
  fetch "https://github.com/koalaman/shellcheck/releases/download/${SHELLCHECK_VERSION}/shellcheck-${SHELLCHECK_VERSION}.linux.${shellcheck_architecture}.tar.xz" \
    "${download_directory}/shellcheck.tar.xz" sha256 "${sha256[shellcheck-${architecture}]}"
  tar -xJf "${download_directory}/shellcheck.tar.xz" -C "${download_directory}"
  install -m 0755 "${download_directory}/shellcheck-${SHELLCHECK_VERSION}/shellcheck" "${CI_TOOLS}/bin/shellcheck"
fi

if ! installed gitleaks; then
  gitleaks_architecture=x64
  [[ "${architecture}" == arm64 ]] && gitleaks_architecture=arm64
  fetch "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${gitleaks_architecture}.tar.gz" \
    "${download_directory}/gitleaks.tar.gz" sha256 "${sha256[gitleaks-${architecture}]}"
  tar -xzf "${download_directory}/gitleaks.tar.gz" -C "${CI_TOOLS}/bin" gitleaks
fi

if ! installed trivy; then
  trivy_architecture=64bit
  [[ "${architecture}" == arm64 ]] && trivy_architecture=ARM64
  fetch "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${trivy_architecture}.tar.gz" \
    "${download_directory}/trivy.tar.gz" sha256 "${sha256[trivy-${architecture}]}"
  tar -xzf "${download_directory}/trivy.tar.gz" -C "${CI_TOOLS}/bin" trivy
fi

if ! installed crane; then
  crane_architecture=x86_64
  [[ "${architecture}" == arm64 ]] && crane_architecture=arm64
  fetch "https://github.com/google/go-containerregistry/releases/download/${CRANE_VERSION}/go-containerregistry_Linux_${crane_architecture}.tar.gz" \
    "${download_directory}/crane.tar.gz" sha256 "${sha256[crane-${architecture}]}"
  tar -xzf "${download_directory}/crane.tar.gz" -C "${CI_TOOLS}/bin" crane
fi

for envtest_version in "${ENVTEST_VERSIONS[@]}"; do
  target="${CI_TOOLS}/envtest/${envtest_version}"
  [[ -x "${target}/kube-apiserver" ]] && continue
  fetch "https://github.com/kubernetes-sigs/controller-tools/releases/download/envtest-v${envtest_version}/envtest-v${envtest_version}-linux-${architecture}.tar.gz" \
    "${download_directory}/envtest.tar.gz" sha512 "${envtest_sha512[${envtest_version}-${architecture}]}"
  mkdir -p "${target}"
  tar -xzf "${download_directory}/envtest.tar.gz" -C "${target}" --strip-components 2
done

if [[ ! -d "${CI_TOOLS}/python/yaml" ]]; then
  python3 -m pip install --quiet --disable-pip-version-check --no-cache-dir \
    --only-binary :all: --require-hashes --target "${CI_TOOLS}/python" \
    --requirement "${CI_REPOSITORY_ROOT}/ci/requirements.txt"
fi

rm -rf "${download_directory}"

helm version --short
helm unittest --help > /dev/null
kubeconform -v
yq --version
jq --version
shellcheck --version | sed -n 2p
gitleaks version
trivy --version | head -1
crane version
python3 -c 'import yaml; print("PyYAML", yaml.__version__)'
for envtest_version in "${ENVTEST_VERSIONS[@]}"; do
  "${CI_TOOLS}/envtest/${envtest_version}/kube-apiserver" --version
done
