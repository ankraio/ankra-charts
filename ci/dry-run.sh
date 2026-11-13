#!/usr/bin/env bash
# Server-side install checks against a real kube-apiserver of one Kubernetes
# minor: `helm install --dry-run=server` for every chart that cannot become
# Ready without its cloud or model provider, and a real install of
# gateway-api-crds (CRDs only, so it needs no kubelet).
#
# Usage: ci/dry-run.sh <envtest version>   (1.27.1, 1.29.5 or 1.31.0)
#
# GitHub Actions ran this on kind. Kind needs Docker and a privileged runner,
# which an Ankra Pipelines step is not, so this starts the envtest builds of
# etcd and kube-apiserver as plain processes instead: the same apiserver, its
# schema validation, admission and RBAC, without nodes. The checks that have
# to start a container (the kind smoke tests) stay in
# .github/workflows/charts-smoke.yml.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

kubernetes_version="${1:?usage: ci/dry-run.sh <envtest version>}"
binaries="${CI_TOOLS}/envtest/${kubernetes_version}"
if [[ ! -x "${binaries}/kube-apiserver" ]]; then
  echo "dry-run: no kube-apiserver ${kubernetes_version} under ${binaries}; run ci/tools.sh first" >&2
  exit 1
fi
export PATH="${binaries}:${PATH}"

state="${CI_SCRATCH}/apiserver"
rm -rf "${state}"
mkdir -p "${state}/etcd" "${state}/certs"

section() {
  printf '\n==> %s\n' "$*"
}

processes=()
stop_cluster() {
  local status=$?
  for process in "${processes[@]}"; do
    kill "${process}" 2> /dev/null || true
  done
  wait 2> /dev/null || true
  if [[ "${status}" != 0 ]]; then
    echo "--- etcd log (tail)"
    tail -n 40 "${state}/etcd.log" 2> /dev/null || true
    echo "--- kube-apiserver log (tail)"
    tail -n 80 "${state}/kube-apiserver.log" 2> /dev/null || true
  fi
  rm -rf "${state}"
  exit "${status}"
}
trap stop_cluster EXIT

section "starting etcd and kube-apiserver ${kubernetes_version}"
etcd \
  --name ci \
  --data-dir "${state}/etcd" \
  --listen-client-urls http://127.0.0.1:2379 \
  --advertise-client-urls http://127.0.0.1:2379 \
  --listen-peer-urls http://127.0.0.1:2380 \
  --initial-advertise-peer-urls http://127.0.0.1:2380 \
  --initial-cluster ci=http://127.0.0.1:2380 \
  --unsafe-no-fsync \
  > "${state}/etcd.log" 2>&1 &
processes+=("$!")

ssh-keygen -q -t rsa -b 2048 -m PEM -N '' -f "${state}/service-account.key"
ssh-keygen -e -m PKCS8 -f "${state}/service-account.key" > "${state}/service-account.pub"
token="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
printf '%s,ci-admin,ci-admin,"system:masters"\n' "${token}" > "${state}/tokens.csv"

kube-apiserver \
  --etcd-servers http://127.0.0.1:2379 \
  --cert-dir "${state}/certs" \
  --bind-address 127.0.0.1 \
  --advertise-address 127.0.0.1 \
  --secure-port 6443 \
  --service-cluster-ip-range 10.0.0.0/24 \
  --allow-privileged=true \
  --authorization-mode RBAC \
  --token-auth-file "${state}/tokens.csv" \
  --service-account-issuer https://kubernetes.default.svc \
  --service-account-key-file "${state}/service-account.pub" \
  --service-account-signing-key-file "${state}/service-account.key" \
  > "${state}/kube-apiserver.log" 2>&1 &
processes+=("$!")

export KUBECONFIG="${state}/kubeconfig"
kubectl config set-cluster ci --server https://127.0.0.1:6443 --insecure-skip-tls-verify=true > /dev/null
kubectl config set-credentials ci-admin --token "${token}" > /dev/null
kubectl config set-context ci --cluster ci --user ci-admin > /dev/null
kubectl config use-context ci > /dev/null

for _ in $(seq 1 90); do
  if kubectl get --raw /readyz > /dev/null 2>&1 && kubectl get namespace default > /dev/null 2>&1; then
    break
  fi
  sleep 2
done
kubectl get --raw /readyz > /dev/null
kubectl version

create_namespace() {
  kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - > /dev/null
}

apply_crds() {
  kubectl apply --server-side --force-conflicts -f "$1" > /dev/null
  kubectl wait --for=condition=Established --timeout=60s crd --all > /dev/null
}

section "upcloud-ccm and upcloud-csi"
create_namespace ccm-ci
helm install ccm upcloud-ccm --namespace ccm-ci --dry-run=server \
  --set ccmConfig.clusterID=ci-test --set credentials.username=ci --set credentials.password=ci > /dev/null
apply_crds upcloud-csi/crds/
create_namespace csi-ci
helm install csi upcloud-csi --namespace csi-ci --dry-run=server \
  --set credentials.create=true --set credentials.existingSecret= \
  --set credentials.username=ci --set credentials.password=ci \
  --set storageClasses.defaultClass=maxiops > /dev/null

section "digitalocean-ccm and digitalocean-csi"
create_namespace do-ccm-ci
helm install ccm digitalocean-ccm --namespace do-ccm-ci --dry-run=server --set credentials.token=ci > /dev/null
apply_crds digitalocean-csi/crds/
create_namespace do-csi-ci
helm install csi digitalocean-csi --namespace do-csi-ci --dry-run=server --set credentials.token=ci > /dev/null

section "hermes-agent"
create_namespace hermes-ci
kubectl -n hermes-ci create secret generic hermes-credentials \
  --from-literal=OPENROUTER_API_KEY=ci --from-literal=API_SERVER_KEY=ci > /dev/null
helm install hermes hermes-agent --namespace hermes-ci --dry-run=server \
  --set secrets.existingSecret=hermes-credentials > /dev/null
helm install hermes-api hermes-agent --namespace hermes-ci --dry-run=server \
  --set secrets.existingSecret=hermes-credentials \
  --set apiServer.enabled=true --set service.enabled=true \
  --set ingress.enabled=true --set ingress.className=nginx > /dev/null
apply_crds hermes-agent/crds/
helm install hermes-operator hermes-agent --namespace hermes-ci --dry-run=server \
  --values hermes-agent/values-examples/operator.yaml \
  --set 'operator.tenants[0].namespace=hermes-ci' \
  --set 'operator.tenants[1].namespace=hermes-ci' > /dev/null

section "isms-builder"
create_namespace isms-ci
kubectl -n isms-ci create secret generic isms-credentials --from-literal=JWT_SECRET=ci-placeholder > /dev/null
helm install isms isms-builder --namespace isms-ci --dry-run=server \
  --set secrets.existingSecret=isms-credentials > /dev/null
helm install isms-ingress isms-builder --namespace isms-ci --dry-run=server \
  --set secrets.existingSecret=isms-credentials \
  --set ingress.enabled=true --set ingress.className=traefik > /dev/null
helm install isms-postgres isms-builder --namespace isms-ci --dry-run=server \
  --values isms-builder/values-examples/postgres.yaml > /dev/null

section "claude-code-openai-wrapper"
create_namespace claude-ci
kubectl -n claude-ci create secret generic claude-credentials \
  --from-literal=ANTHROPIC_API_KEY=ci-placeholder --from-literal=API_KEY=ci-token > /dev/null
helm install claude-wrapper claude-code-openai-wrapper --namespace claude-ci --dry-run=server \
  --set secrets.existingSecret=claude-credentials > /dev/null
helm install claude-wrapper-ingress claude-code-openai-wrapper --namespace claude-ci --dry-run=server \
  --set secrets.existingSecret=claude-credentials \
  --set ingress.enabled=true --set ingress.className=nginx > /dev/null
helm install claude-wrapper-bedrock claude-code-openai-wrapper --namespace claude-ci --dry-run=server \
  --values claude-code-openai-wrapper/values-examples/bedrock.yaml > /dev/null

if [[ "${kubernetes_version}" == 1.31.* ]]; then
  # The check that matters for this chart: Helm stores the whole chart in its
  # release Secret and the apiserver refuses one over 1 MiB, which neither
  # helm lint nor helm template can see. CRDs need no kubelet, so this is a
  # real install, not a dry-run.
  section "gateway-api-crds (real install, release Secret size, uninstall keeps the CRDs)"
  helm install gateway-api-crds gateway-api-crds -n gateway-system --create-namespace --wait --timeout 3m > /dev/null
  kubectl get crd httproutes.gateway.networking.k8s.io gateways.gateway.networking.k8s.io gatewayclasses.gateway.networking.k8s.io
  size="$(kubectl get secret -n gateway-system sh.helm.release.v1.gateway-api-crds.v1 -o json \
    | python3 -c 'import base64,json,sys; print(len(base64.b64decode(json.load(sys.stdin)["data"]["release"])))')"
  echo "release Secret data: ${size} bytes (the apiserver refuses over 1048576)"
  if [[ "${size}" -gt 900000 ]]; then
    echo "the release Secret is ${size} bytes, too close to the 1 MiB limit" >&2
    exit 1
  fi
  helm uninstall gateway-api-crds -n gateway-system --wait --timeout 2m > /dev/null
  kubectl get crd httproutes.gateway.networking.k8s.io > /dev/null
  echo "uninstall kept the CRDs"
fi

section "every server-side check passed on kube-apiserver ${kubernetes_version}"
