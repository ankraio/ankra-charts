#!/usr/bin/env bash
# Copy an image the publish stage released into the organisation registry, by
# its gated digest, to the public registry share.ankra.cloud, where customer CI
# clusters pull it without credentials.
#
# Environment:
#   SOURCE_IMAGE_REFERENCE  the publish stage's image_ref (<repository>:<tag>)
#   SOURCE_IMAGE_DIGEST     the publish stage's image_digest
#   PUBLIC_IMAGE            the target, <registry>/<project>/<repository>:<tag>
#
# The source is read with the organisation_registry_login secret and the copy is
# written with share_login (the organisation's connected registry
# share-ankra-cloud); both are protected and arrive once an administrator has
# approved the pipeline definition. A public tag is never moved: when it already
# exists the stage says so and copies nothing, and publishing a new build means
# raising the -ankra.N suffix of PUBLIC_IMAGE.
set -euo pipefail

# shellcheck source=ci/env.sh
source "$(dirname "$0")/env.sh"

source_reference="${SOURCE_IMAGE_REFERENCE:?SOURCE_IMAGE_REFERENCE is required}"
source_digest="${SOURCE_IMAGE_DIGEST:?SOURCE_IMAGE_DIGEST is required}"
public_image="${PUBLIC_IMAGE:?PUBLIC_IMAGE is required}"
secrets_directory="/run/agent-secrets"
source_login_file="${secrets_directory}/organisation_registry_login"
public_login_file="${secrets_directory}/share_login"

[[ "${source_digest}" =~ ^sha256:[a-f0-9]{64}$ ]] || {
  echo "distribute-image: '${source_digest}' is not a digest" >&2
  exit 1
}
source_repository="${source_reference%@*}"
source_repository="${source_repository%:*}"
public_repository="${public_image%:*}"
public_registry="${public_image%%/*}"

for login_file in "${source_login_file}" "${public_login_file}"; do
  test -s "${login_file}" || {
    echo "distribute-image: the ${login_file##*/} secret was not delivered; it is granted once an organisation" \
      "administrator approves the pipeline definition (ankra pipeline definitions approve <definition-id>)" >&2
    exit 1
  }
done

# One Docker configuration holding both logins: the organisation registry's as
# delivered, the public registry's added with crane, which keeps the rest.
export DOCKER_CONFIG="${CI_SCRATCH}/docker"
mkdir -p "${DOCKER_CONFIG}"
cp "${source_login_file}" "${DOCKER_CONFIG}/config.json"
public_auth="$(tr -d '\n' < "${public_login_file}" \
  | sed -n "s|.*\"${public_registry//./\\.}\" *: *{[^}]*\"auth\" *: *\"\\([^\"]*\\)\".*|\\1|p")"
test -n "${public_auth}" || {
  echo "distribute-image: the share_login secret holds no login for ${public_registry}" >&2
  exit 1
}
public_login="$(printf '%s' "${public_auth}" | base64 -d)"
printf '%s' "${public_login#*:}" \
  | crane auth login "${public_registry}" --username "${public_login%%:*}" --password-stdin > /dev/null

if existing_digest="$(crane digest "${public_image}" 2> /dev/null)"; then
  if [[ "${existing_digest}" == "${source_digest}" ]]; then
    echo "distribute-image: ${public_image} is already ${source_digest}"
  else
    echo "distribute-image: ${public_image} is already published as ${existing_digest}; a public tag is never moved." \
      "Raise the -ankra.N suffix of PUBLIC_IMAGE in .ankra/pipeline.yaml to publish this build (${source_digest})."
  fi
  exit 0
fi

crane copy "${source_repository}@${source_digest}" "${public_image}"
published_digest="$(crane digest "${public_image}")"
[[ "${published_digest}" == "${source_digest}" ]] || {
  echo "distribute-image: ${public_image} is ${published_digest}, not the gated ${source_digest}" >&2
  exit 1
}

# What a customer cluster sees: the image has to pull with no login at all.
anonymous_digest="$(DOCKER_CONFIG="${CI_SCRATCH}/anonymous" crane digest "${public_repository}@${source_digest}")"
[[ "${anonymous_digest}" == "${source_digest}" ]] || {
  echo "distribute-image: ${public_repository} does not serve ${source_digest} without credentials" >&2
  exit 1
}
echo "distribute-image: published ${public_image}@${source_digest}"
