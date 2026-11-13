#!/usr/bin/env bash
# The per-chart pull request gate: helm lint, helm template of every overlay,
# kubeconform against the Kubernetes and CRD-catalog schemas, helm-unittest,
# and, where a chart has them, the hardening guardrails, a Trivy
# misconfiguration scan and the pinned-image-digest check.
#
# Usage: ci/chart-gate.sh <group>
#   upcloud | digitalocean | cloudflare-operator | gateway-api-crds |
#   hermes-agent | isms-builder | claude-code-openai-wrapper
#
# The server-side install checks live in ci/dry-run.sh; this script needs no
# cluster.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

group="${1:?usage: ci/chart-gate.sh <group>}"
rendered="${CI_SCRATCH}/rendered"
mkdir -p "${rendered}"

section() {
  printf '\n==> %s\n' "$*"
}

# The Kubernetes version kubeconform validates against; the upcloud charts
# require 1.34+, the rest are checked at 1.31.
kubeconform_kubernetes_version=1.31.0

kubeconform_strict() {
  kubeconform \
    -strict -summary -verbose \
    -kubernetes-version "${kubeconform_kubernetes_version}" \
    -schema-location default \
    -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{ .Group }}/{{ .ResourceKind }}_{{ .ResourceAPIVersion }}.json' \
    -ignore-missing-schemas \
    "$@"
}

unittest_if_present() {
  local chart="$1"
  if [[ -d "${chart}/tests" ]]; then
    section "helm unittest ${chart}"
    helm unittest "${chart}"
  else
    echo "${chart} has no tests/ directory; skipping helm-unittest"
  fi
}

# refuses <chart> <namespace> <description> [helm template arguments...]
# Records a failure when the chart renders a configuration it must refuse.
guardrail_failures=0
refuses() {
  local chart="$1" namespace="$2" description="$3"
  shift 3
  if helm template ci "${chart}" --namespace "${namespace}" "$@" > /dev/null 2>&1; then
    echo "FAIL: ${description} was accepted but should have been refused" >&2
    guardrail_failures=1
  else
    echo "refused: ${description}"
  fi
}

# The hardened application charts (hermes-agent, isms-builder,
# claude-code-openai-wrapper) share one gate shape.
hardened_chart_gate() {
  local chart="$1" namespace="$2" secret="$3"

  section "helm lint --strict ${chart} (defaults and every overlay)"
  if [[ "${chart}" == hermes-agent ]]; then
    helm lint --strict "${chart}"
  else
    helm lint --strict "${chart}" --set "secrets.existingSecret=${secret}"
  fi
  for overlay in "${chart}"/values-examples/*.yaml; do
    echo "--> ${overlay}"
    helm lint --strict "${chart}" --values "${overlay}"
  done

  section "helm template ${chart} (defaults and every overlay)"
  helm template ci "${chart}" --namespace "${namespace}" \
    --set "secrets.existingSecret=${secret}" > "${rendered}/${chart}-defaults.yaml"
  for overlay in "${chart}"/values-examples/*.yaml; do
    name="$(basename "${overlay}" .yaml)"
    helm template ci "${chart}" --namespace "${namespace}" --values "${overlay}" \
      > "${rendered}/${chart}-${name}.yaml"
    echo "${name}: $(grep -c '^kind:' "${rendered}/${chart}-${name}.yaml") resources"
  done

  section "kubeconform ${chart}"
  kubeconform_strict "${rendered}"/"${chart}"-*.yaml

  section "helm unittest ${chart}"
  helm unittest "${chart}"

  section "Weak configurations of ${chart} must be refused"
  case "${chart}" in
    hermes-agent)
      refuses "${chart}" "${namespace}" "unpinned image" --set image.digest=
      refuses "${chart}" "${namespace}" "inline API key" --set secrets.OPENROUTER_API_KEY=ci-placeholder
      refuses "${chart}" "${namespace}" "no NetworkPolicy" --set networkPolicy.enabled=false
      refuses "${chart}" "${namespace}" "root user" --set podSecurityContext.runAsUser=0
      refuses "${chart}" "${namespace}" "writable root filesystem" --set securityContext.readOnlyRootFilesystem=false
      refuses "${chart}" "${namespace}" "privilege escalation" --set securityContext.allowPrivilegeEscalation=true
      refuses "${chart}" "${namespace}" "mounted ServiceAccount token" --set serviceAccount.automountServiceAccountToken=true
      refuses "${chart}" "${namespace}" "metadata endpoint reachable" --set 'networkPolicy.egress.excludedCidrs={10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}'
      refuses "${chart}" "${namespace}" "cluster network reachable" --set 'networkPolicy.egress.excludedCidrs={169.254.0.0/16}'
      refuses "${chart}" "${namespace}" "wildcard CORS" --set secrets.existingSecret=h --set apiServer.enabled=true --set apiServer.corsOrigins='*'
      refuses "${chart}" "${namespace}" "unknown values key" --set secrets.existingSecret=h --set totallyNotAValue=1
      refuses "${chart}" "${namespace}" "inline provider api_key" --set secrets.existingSecret=h --set config.values.providers.salad.api=https://ai.salad.cloud/v1 --set config.values.providers.salad.api_key=ci-placeholder
      refuses "${chart}" "${namespace}" "provider key_env the pod lacks" --set config.values.providers.salad.api=https://ai.salad.cloud/v1 --set config.values.providers.salad.key_env=SALAD_API_KEY
      refuses "${chart}" "${namespace}" "in-cluster model, no egress" --set secrets.existingSecret=h --set config.values.model.provider=lmstudio --set config.values.model.base_url=http://model.claude.svc:8000/v1
      refuses "${chart}" "${namespace}" "fallback entry without model" --set secrets.existingSecret=h --set 'config.values.fallback_providers[0].provider=openrouter'
      ;;
    isms-builder)
      refuses "${chart}" "${namespace}" "no JWT secret source"
      refuses "${chart}" "${namespace}" "unpinned image" --set secrets.existingSecret=s --set image.digest=
      refuses "${chart}" "${namespace}" "inline JWT secret" --set secrets.JWT_SECRET=ci-placeholder
      refuses "${chart}" "${namespace}" "no NetworkPolicy" --set secrets.existingSecret=s --set networkPolicy.enabled=false
      refuses "${chart}" "${namespace}" "root user" --set secrets.existingSecret=s --set podSecurityContext.runAsUser=0
      refuses "${chart}" "${namespace}" "writable root filesystem" --set secrets.existingSecret=s --set securityContext.readOnlyRootFilesystem=false
      refuses "${chart}" "${namespace}" "privilege escalation" --set secrets.existingSecret=s --set securityContext.allowPrivilegeEscalation=true
      refuses "${chart}" "${namespace}" "mounted ServiceAccount token" --set secrets.existingSecret=s --set serviceAccount.automountServiceAccountToken=true
      refuses "${chart}" "${namespace}" "two replicas" --set secrets.existingSecret=s --set replicaCount=2
      refuses "${chart}" "${namespace}" "SQL backend without a host" --set secrets.existingSecret=s --set storage.backend=postgres
      refuses "${chart}" "${namespace}" "unknown values key" --set secrets.existingSecret=s --set totallyNotAValue=1
      ;;
    claude-code-openai-wrapper)
      refuses "${chart}" "${namespace}" "no Claude credential source"
      refuses "${chart}" "${namespace}" "unpinned image" --set secrets.existingSecret=s --set image.digest=
      refuses "${chart}" "${namespace}" "inline API key" --set secrets.ANTHROPIC_API_KEY=ci-placeholder
      refuses "${chart}" "${namespace}" "no NetworkPolicy" --set secrets.existingSecret=s --set networkPolicy.enabled=false
      refuses "${chart}" "${namespace}" "root user" --set secrets.existingSecret=s --set podSecurityContext.runAsUser=0
      refuses "${chart}" "${namespace}" "writable root filesystem" --set secrets.existingSecret=s --set securityContext.readOnlyRootFilesystem=false
      refuses "${chart}" "${namespace}" "privilege escalation" --set secrets.existingSecret=s --set securityContext.allowPrivilegeEscalation=true
      refuses "${chart}" "${namespace}" "mounted ServiceAccount token" --set secrets.existingSecret=s --set serviceAccount.automountServiceAccountToken=true
      refuses "${chart}" "${namespace}" "metadata endpoint reachable" --set secrets.existingSecret=s --set 'networkPolicy.egress.excludedCidrs={10.0.0.0/8,172.16.0.0/12,192.168.0.0/16}'
      refuses "${chart}" "${namespace}" "cluster network reachable" --set secrets.existingSecret=s --set 'networkPolicy.egress.excludedCidrs={169.254.0.0/16}'
      refuses "${chart}" "${namespace}" "wildcard CORS" --set secrets.existingSecret=s --set 'server.corsOrigins={*}'
      refuses "${chart}" "${namespace}" "unauthenticated Ingress" --set hardening.allowInlineSecrets=true --set secrets.ANTHROPIC_API_KEY=ci-placeholder --set ingress.enabled=true
      refuses "${chart}" "${namespace}" "unknown values key" --set secrets.existingSecret=s --set totallyNotAValue=1
      ;;
  esac
  if [[ "${guardrail_failures}" != 0 ]]; then
    exit 1
  fi
  helm template ci "${chart}" --namespace "${namespace}" \
    --set "secrets.existingSecret=${secret}" > /dev/null
  echo "the shipped defaults still render"

  section "trivy misconfiguration scan of ${chart} (production overlay)"
  mkdir -p "${CI_SCRATCH}/scan"
  helm template ci "${chart}" --namespace "${namespace}" \
    --values "${chart}/values-examples/production.yaml" > "${CI_SCRATCH}/scan/manifests.yaml"
  trivy config --quiet --severity HIGH,CRITICAL --exit-code 1 --format table "${CI_SCRATCH}/scan/manifests.yaml"

  section "values.yaml, Chart.yaml and the registry agree on ${chart}'s pinned image"
  image_pin_check "${chart}"
}

image_pin_check() {
  local chart="$1"
  local registry repository tag digest app_version annotated expected
  registry="$(yq -r '.image.registry' "${chart}/values.yaml")"
  repository="$(yq -r '.image.repository' "${chart}/values.yaml")"
  tag="$(yq -r '.image.tag' "${chart}/values.yaml")"
  digest="$(yq -r '.image.digest' "${chart}/values.yaml")"
  app_version="$(yq -r '.appVersion' "${chart}/Chart.yaml")"
  annotated="$(yq -r '.annotations["artifacthub.io/images"]' "${chart}/Chart.yaml" | yq -r '.[0].image')"
  expected="${registry}/${repository}:${tag}@${digest}"

  echo "values.yaml : ${expected}"
  echo "Chart.yaml  : ${annotated}"
  echo "appVersion  : ${app_version}"

  if [[ "${app_version}" != "${tag}" ]]; then
    echo "Chart.yaml appVersion (${app_version}) does not match image.tag (${tag})" >&2
    exit 1
  fi
  if [[ "${annotated}" != "${expected}" ]]; then
    echo "the artifacthub.io/images annotation is stale; run scripts/sync-image-digest.sh ${chart}" >&2
    exit 1
  fi
  if ! git diff --quiet --exit-code -- "${chart}"; then
    echo "${chart} has uncommitted changes before the check; refusing to judge it" >&2
    exit 1
  fi
  ./scripts/sync-image-digest.sh "${chart}" check
  if ! git diff --quiet --exit-code -- "${chart}"; then
    echo "check mode should never write; something is wrong with the sync script" >&2
    exit 1
  fi
  ./scripts/sync-image-digest.sh "${chart}"
  if ! git diff --quiet --exit-code -- "${chart}"; then
    echo "the pinned tag no longer resolves to the pinned digest - the tag moved" >&2
    git --no-pager diff -- "${chart}"
    exit 1
  fi
  echo "the pinned digest still matches the registry"
}

cloud_driver_gate() {
  local chart="$1"
  shift
  local -a values=("$@")

  section "helm lint ${chart}"
  helm lint "${chart}" "${values[@]}"

  section "helm template ${chart}"
  helm template ci "${chart}" --namespace kube-system --kube-version "${kubeconform_kubernetes_version}" \
    "${values[@]}" > "${rendered}/${chart}.yaml"
  wc -l "${rendered}/${chart}.yaml"

  section "kubeconform ${chart}"
  kubeconform_strict "${rendered}/${chart}.yaml"

  unittest_if_present "${chart}"
}

case "${group}" in
  upcloud)
    # Helm 3.14 renders for Kubernetes 1.29 by default, below upcloud-csi's
    # kubeVersion (>=1.34, external-provisioner v6).
    kubeconform_kubernetes_version=1.34.0
    cloud_driver_gate upcloud-ccm \
      --set ccmConfig.clusterID=ci-test --set credentials.username=ci --set credentials.password=ci
    cloud_driver_gate upcloud-csi \
      --set credentials.create=true --set credentials.existingSecret= \
      --set credentials.username=ci --set credentials.password=ci \
      --set storageClasses.defaultClass=maxiops
    ;;

  digitalocean)
    cloud_driver_gate digitalocean-ccm --set credentials.token=ci
    cloud_driver_gate digitalocean-csi --set credentials.token=ci
    ;;

  cloudflare-operator)
    chart=cloudflare-operator
    section "helm lint ${chart}"
    helm lint "${chart}"
    section "helm template ${chart} (every overlay and every toggle)"
    for overlay in minimal production air-gapped; do
      helm template ci "${chart}" --namespace cloudflare-operator-system \
        -f "${chart}/values-examples/${overlay}.yaml" > "${rendered}/${overlay}.yaml"
    done
    helm template ci "${chart}" --namespace cloudflare-operator-system \
      --set credentials.create=true \
      --set credentials.existingSecret= \
      --set-string credentials.apiToken=ci-token \
      --set-string credentials.accountId=ci-account \
      --set sampleClusterTunnel.enabled=true \
      --set sampleClusterTunnel.cloudflareDomain=example.com \
      --set sampleClusterTunnel.cloudflareEmail=ci@example.com \
      --set originIssuer.enabled=true \
      --set originIssuer.secret.create=true \
      --set originIssuer.secret.existingSecret= \
      --set-string originIssuer.secret.token=ci-origin-token \
      --set metrics.serviceMonitor.enabled=true \
      --set networkPolicy.enabled=true \
      --set replicaCount=2 \
      > "${rendered}/full.yaml"
    section "kubeconform ${chart}"
    for rendered_file in "${rendered}"/*.yaml; do
      echo "--> ${rendered_file}"
      kubeconform \
        -strict \
        -ignore-missing-schemas \
        -skip "CustomResourceDefinition,ClusterTunnel,ClusterOriginIssuer,ServiceMonitor,Certificate,Issuer" \
        -schema-location default \
        -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
        "${rendered_file}"
    done
    section "helm unittest ${chart}"
    helm unittest "${chart}"
    ;;

  gateway-api-crds)
    chart=gateway-api-crds
    section "helm lint --strict ${chart}"
    helm lint --strict "${chart}"

    section "the vendored files match the upstream tag appVersion names"
    tag="$(grep -E '^appVersion:' "${chart}/Chart.yaml" | awk '{print $2}' | tr -d '"')"
    version="$(grep -E '^version:' "${chart}/Chart.yaml" | awk '{print $2}' | tr -d '"')"
    if [[ "${tag}" != "v${version}" ]]; then
      echo "Chart.yaml version ${version} does not match appVersion ${tag}" >&2
      exit 1
    fi
    bash scripts/sync-gateway-api-crds.sh "${tag}"
    git diff --exit-code -- "${chart}/templates"

    section "every CRD carries the bundle version the chart names, and is kept on uninstall"
    helm template "${chart}" "${chart}" --kube-version 1.31.0 > "${rendered}/${chart}.yaml"
    yq -o=json -I=0 '.' "${rendered}/${chart}.yaml" > "${rendered}/${chart}.jsonl"
    python3 - "${tag}" "${rendered}/${chart}.jsonl" << 'CHECK'
import json
import sys

tag, path = sys.argv[1], sys.argv[2]
objects = [json.loads(line) for line in open(path, encoding="utf-8") if line.strip() not in ("", "null")]
crds = [item for item in objects if item["kind"] == "CustomResourceDefinition"]
if len(crds) != 8:
    raise SystemExit(f"expected 8 CRDs, rendered {len(crds)}")
for item in objects:
    annotations = item["metadata"].get("annotations") or {}
    if annotations.get("helm.sh/resource-policy") != "keep":
        raise SystemExit(f"{item['metadata']['name']} is not kept on uninstall")
for item in crds:
    annotations = item["metadata"]["annotations"]
    if annotations.get("gateway.networking.k8s.io/bundle-version") != tag:
        raise SystemExit(f"{item['metadata']['name']} is not at {tag}")
    if annotations.get("gateway.networking.k8s.io/channel") != "standard":
        raise SystemExit(f"{item['metadata']['name']} is not the standard channel")
print(f"{len(objects)} objects, {len(crds)} CRDs at {tag}, all kept on uninstall")
CHECK
    ;;

  hermes-agent)
    hardened_chart_gate hermes-agent hermes hermes-credentials
    ;;

  isms-builder)
    hardened_chart_gate isms-builder isms isms-credentials
    ;;

  claude-code-openai-wrapper)
    hardened_chart_gate claude-code-openai-wrapper claude claude-credentials
    ;;

  *)
    echo "ci/chart-gate.sh: unknown group ${group}" >&2
    exit 64
    ;;
esac

section "${group}: every check passed"
