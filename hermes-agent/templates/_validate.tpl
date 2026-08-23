{{/*
Render-time validation. Functional rules always run; the hardening rules can be
waived one at a time through the .Values.hardening flags so that an operator who
needs a weaker posture has to say so explicitly, in values, under review.
*/}}

{{- define "hermes-agent.validate" -}}
{{- include "hermes-agent.validateRuntime" . -}}
{{- if .Values.hardening.enabled -}}
{{- include "hermes-agent.validateHardening" . -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.validateRuntime" -}}
{{- if .Values.operator.enabled -}}
{{- if and .Values.operator.installCustomResources (eq (len .Values.operator.tenants) 0) -}}
{{- fail "operator.enabled=true renders HermesTenant resources from operator.tenants, which is empty" -}}
{{- end -}}
{{- else -}}
{{- if and (gt (int .Values.replicaCount) 1) .Values.persistence.enabled -}}
{{- fail "replicaCount must stay 1 while persistence.enabled=true: HERMES_HOME holds mutable single-writer state. Install one release per agent instead." -}}
{{- end -}}
{{- if and .Values.persistence.enabled (ne .Values.strategy.type "Recreate") -}}
{{- fail "strategy.type must be Recreate while persistence.enabled=true: RollingUpdate would run two pods against one ReadWriteOnce volume." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled .Values.secrets.existingSecret -}}
{{- fail "externalSecret.enabled and secrets.existingSecret are mutually exclusive: pick which one owns the Secret." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (include "hermes-agent.hasInlineSecrets" .) -}}
{{- fail "externalSecret.enabled cannot be combined with inline secrets.<KEY> values." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (not .Values.externalSecret.secretStoreRef.name) -}}
{{- fail "externalSecret.enabled=true requires externalSecret.secretStoreRef.name." -}}
{{- end -}}
{{- $inlineSecretKeys := include "hermes-agent.inlineSecretKeys" . | fromJsonArray -}}
{{- if and .Values.apiServer.enabled (not (include "hermes-agent.secretManagedExternally" .)) (not (has "API_SERVER_KEY" $inlineSecretKeys)) -}}
{{- fail "apiServer.enabled=true requires an API_SERVER_KEY: set secrets.existingSecret, enable externalSecret, or supply secrets.API_SERVER_KEY." -}}
{{- end -}}
{{- if and .Values.telegramWebhook.enabled (eq (trim .Values.telegramWebhook.url) "") -}}
{{- fail "telegramWebhook.enabled=true requires telegramWebhook.url." -}}
{{- end -}}
{{- if and .Values.telegramWebhook.enabled (not (include "hermes-agent.secretManagedExternally" .)) (not (has "TELEGRAM_BOT_TOKEN" $inlineSecretKeys)) -}}
{{- fail "telegramWebhook.enabled=true requires a TELEGRAM_BOT_TOKEN: set secrets.existingSecret, enable externalSecret, or supply secrets.TELEGRAM_BOT_TOKEN." -}}
{{- end -}}
{{- if and .Values.tenantIsolation.enabled (eq (trim .Values.tenant.id) "") -}}
{{- fail "tenantIsolation.enabled=true requires tenant.id." -}}
{{- end -}}
{{- if and (gt (len .Values.npm.packages) 0) (not .Values.npm.enabled) -}}
{{- fail "npm.packages is set but npm.enabled=false: installing packages into a running pod pulls code from a registry at startup, so it must be turned on deliberately." -}}
{{- end -}}
{{- if and .Values.ingress.enabled (not .Values.service.enabled) -}}
{{- fail "ingress.enabled=true requires service.enabled=true." -}}
{{- end -}}
{{- if and .Values.virtualService.enabled (not .Values.service.enabled) -}}
{{- fail "virtualService.enabled=true requires service.enabled=true." -}}
{{- end -}}
{{- include "hermes-agent.validateModelProviders" . -}}
{{- end -}}
{{- end -}}

{{/*
Model endpoints: the main model, the named providers and the fallback chain.
Hermes silently drops a fallback entry it cannot parse and silently keeps a
provider whose key is missing, so both are caught here instead.
*/}}
{{- define "hermes-agent.validateModelProviders" -}}
{{- $config := .Values.config.values | default dict -}}
{{- $model := $config.model | default dict -}}
{{- $providers := include "hermes-agent.modelProviders" . | fromJson -}}
{{- $chain := include "hermes-agent.fallbackProviders" . | fromJsonArray -}}
{{- $envNames := include "hermes-agent.chartManagedEnvNames" . | fromJsonArray -}}
{{- $envVisible := or (include "hermes-agent.secretManagedExternally" .) (gt (len (.Values.extraEnvFrom | default list)) 0) -}}
{{- $egress := .Values.networkPolicy.egress -}}
{{- $excluded := $egress.excludedCidrs | default list -}}
{{- $privateExcluded := or (has "10.0.0.0/8" $excluded) (has "172.16.0.0/12" $excluded) (has "192.168.0.0/16" $excluded) -}}
{{- $hasEgressHole := or (gt (len ($egress.extra | default list)) 0) (and .Values.tenantIsolation.enabled (gt (len (.Values.tenantIsolation.additionalEgress | default list)) 0)) -}}
{{- $internalBlocked := and .Values.networkPolicy.enabled (not $hasEgressHole) (or (not $egress.allowPublicInternet) $privateExcluded) -}}

{{- range $name, $entry := $providers -}}
{{- if not (kindIs "map" $entry) -}}
{{- fail (printf "config.values.providers.%s must be a map with at least `api` (the endpoint URL)." $name) -}}
{{- end -}}
{{- $endpoint := include "hermes-agent.providerEndpoint" $entry -}}
{{- if eq $endpoint "" -}}
{{- fail (printf "config.values.providers.%s has no endpoint: set `api` to the OpenAI-compatible base URL (e.g. https://ai.salad.cloud/v1)." $name) -}}
{{- end -}}
{{- $keyEnv := $entry.key_env | default $entry.api_key_env | default "" | toString | trim -}}
{{- if and (ne $keyEnv "") (not $envVisible) (not (has $keyEnv $envNames)) -}}
{{- fail (printf "config.values.providers.%s.key_env names %s, but nothing in this release puts that variable on the pod: add it to secrets.existingSecret (or externalSecret / extraEnvFrom), or declare it under secrets.%s." $name $keyEnv $keyEnv) -}}
{{- end -}}
{{- if and $internalBlocked (include "hermes-agent.isClusterInternalUrl" $endpoint) -}}
{{- fail (printf "config.values.providers.%s points at %s, inside the cluster, but the NetworkPolicy egress excludes private networks: add a networkPolicy.egress.extra rule for that namespace, pod and port (see values-examples/multi-provider.yaml)." $name $endpoint) -}}
{{- end -}}
{{- end -}}

{{- $modelProvider := $model.provider | default "" | toString | trim -}}
{{- $modelBaseUrl := $model.base_url | default "" | toString | trim -}}
{{- if hasKey $providers $modelProvider -}}
{{- $named := index $providers $modelProvider -}}
{{- $namedEndpoint := include "hermes-agent.providerEndpoint" $named -}}
{{- if and (ne $modelBaseUrl "") (ne (trimSuffix "/" $modelBaseUrl) (trimSuffix "/" $namedEndpoint)) -}}
{{- fail (printf "config.values.model.provider names providers.%s (%s) but config.values.model.base_url is %s: leave base_url empty so the named provider's endpoint is the only one in play." $modelProvider $namedEndpoint $modelBaseUrl) -}}
{{- end -}}
{{- else if and $internalBlocked (include "hermes-agent.isClusterInternalUrl" $modelBaseUrl) -}}
{{- fail (printf "config.values.model.base_url points at %s, inside the cluster, but the NetworkPolicy egress excludes private networks: add a networkPolicy.egress.extra rule for that namespace, pod and port (see values-examples/multi-provider.yaml)." $modelBaseUrl) -}}
{{- end -}}

{{- range $index, $entry := $chain -}}
{{- if not (kindIs "map" $entry) -}}
{{- fail (printf "config.values.fallback_providers[%d] must be a map with `provider` and `model`." $index) -}}
{{- end -}}
{{- $provider := $entry.provider | default "" | toString | trim -}}
{{- $fallbackModel := $entry.model | default "" | toString | trim -}}
{{- if or (eq $provider "") (eq $fallbackModel "") -}}
{{- fail (printf "config.values.fallback_providers[%d] needs both `provider` and `model`; Hermes ignores an entry missing either, so the chain would silently be shorter than configured." $index) -}}
{{- end -}}
{{- $baseUrl := $entry.base_url | default "" | toString | trim -}}
{{- if and (eq $provider "custom") (eq $baseUrl "") -}}
{{- fail (printf "config.values.fallback_providers[%d] uses provider `custom` without `base_url`: set base_url (and key_env), or name an entry under config.values.providers instead." $index) -}}
{{- end -}}
{{- $keyEnv := $entry.key_env | default $entry.api_key_env | default "" | toString | trim -}}
{{- if and (ne $keyEnv "") (not $envVisible) (not (has $keyEnv $envNames)) -}}
{{- fail (printf "config.values.fallback_providers[%d].key_env names %s, but nothing in this release puts that variable on the pod: add it to secrets.existingSecret (or externalSecret / extraEnvFrom), or declare it under secrets.%s." $index $keyEnv $keyEnv) -}}
{{- end -}}
{{- if and $internalBlocked (include "hermes-agent.isClusterInternalUrl" $baseUrl) -}}
{{- fail (printf "config.values.fallback_providers[%d] points at %s, inside the cluster, but the NetworkPolicy egress excludes private networks: add a networkPolicy.egress.extra rule for that namespace, pod and port (see values-examples/multi-provider.yaml)." $index $baseUrl) -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.validateHardening" -}}
{{- $hardening := .Values.hardening -}}

{{- if and (not .Values.image.digest) (not $hardening.allowMutableImageTag) -}}
{{- fail "image.digest is empty: a tag can be moved under you. Pin a digest (`make hermes-digest`, or scripts/sync-image-digest.sh) or set hardening.allowMutableImageTag=true." -}}
{{- end -}}

{{- if and .Values.camofox.enabled (not .Values.camofox.image.digest) (not $hardening.allowMutableImageTag) -}}
{{- fail "camofox.image.digest is empty: the browser sidecar renders every page the agent visits, so a moved tag is a code-execution change. Pin a digest (scripts/sync-image-digest.sh camofox-browser) or set hardening.allowMutableImageTag=true." -}}
{{- end -}}

{{- if and (include "hermes-agent.hasInlineSecrets" .) (not $hardening.allowInlineSecrets) -}}
{{- fail (printf "inline secret values are refused (%s): plain API keys in values land in the Helm release Secret, in Git and in shell history. Use secrets.existingSecret or externalSecret.enabled, or set hardening.allowInlineSecrets=true." (include "hermes-agent.inlineSecretKeys" .)) -}}
{{- end -}}

{{- $inlineModelSecretPaths := include "hermes-agent.inlineModelSecretPaths" . | fromJsonArray -}}
{{- if and (gt (len $inlineModelSecretPaths) 0) (not $hardening.allowInlineSecrets) -}}
{{- fail (printf "inline api_key values on model endpoints are refused (%s): they land in the rendered config.yaml, the Helm release Secret, Git and shell history. Point key_env at a key of secrets.existingSecret or the ExternalSecret target instead, or set hardening.allowInlineSecrets=true." (join ", " $inlineModelSecretPaths)) -}}
{{- end -}}

{{- if not .Values.operator.enabled -}}
{{- $podSecurityContext := .Values.podSecurityContext | default dict -}}
{{- $securityContext := .Values.securityContext | default dict -}}

{{/*
The image enters as root under s6-overlay and drops to env.HERMES_UID itself;
its stage2 bootstrap exits non-zero on a pinned UID with "container started
with --user <n> (an arbitrary, non-hermes UID)". Catch that here rather than in
a CrashLoopBackOff.
*/}}
{{- if or (hasKey $podSecurityContext "runAsUser") (hasKey $securityContext "runAsUser") -}}
{{- fail "do not pin runAsUser: this image must enter as root and remaps its own user to env.HERMES_UID/HERMES_GID. A pinned UID makes its bootstrap fail with \"an arbitrary, non-hermes UID\". Set env.HERMES_UID instead, or hardening.enabled=false if you run an image that supports a pinned UID." -}}
{{- end -}}
{{- if eq ($podSecurityContext.runAsNonRoot | toString) "true" -}}
{{- fail "podSecurityContext.runAsNonRoot=true cannot work with this image: it needs to enter as root to remap its user and chown the data volume. The agent still ends up unprivileged via env.HERMES_UID." -}}
{{- end -}}

{{- if not $hardening.allowPrivilegedRuntime -}}
{{- $capabilities := $securityContext.capabilities | default dict -}}
{{/*
Entering as root is forced by the image, so the meaningful guard is that it
actually drops to a non-root uid afterwards.
*/}}
{{- $hermesUID := (.Values.env | default dict).HERMES_UID | toString -}}
{{- if or (eq $hermesUID "") (eq $hermesUID "0") (eq $hermesUID "<no value>") -}}
{{- fail "env.HERMES_UID must be set to a non-zero uid: it is what the container drops to after bootstrap, and without it Hermes keeps running as root (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.privileged | toString) "true" -}}
{{- fail "securityContext.privileged must not be true (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.allowPrivilegeEscalation | toString) "true" -}}
{{- fail "securityContext.allowPrivilegeEscalation must be false (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if ne ($securityContext.readOnlyRootFilesystem | toString) "true" -}}
{{- fail "securityContext.readOnlyRootFilesystem must be true; writable paths are provided as volumes (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if not (has "ALL" ($capabilities.drop | default list)) -}}
{{- fail "securityContext.capabilities.drop must contain ALL (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{/*
The image cannot de-privilege itself without CHOWN/DAC_OVERRIDE/SETGID/SETUID,
so an empty add list is not achievable here. Guard the shape that matters
instead: nothing beyond that bootstrap set.
*/}}
{{- $bootstrapCapabilities := list "CHOWN" "DAC_OVERRIDE" "SETGID" "SETUID" -}}
{{- range $capability := ($capabilities.add | default list) -}}
{{- if not (has $capability $bootstrapCapabilities) -}}
{{- fail (printf "securityContext.capabilities.add may only contain the capabilities s6-overlay needs to drop privileges (%s); %s is not one of them (waive with hardening.allowPrivilegedRuntime=true)." (join ", " $bootstrapCapabilities) $capability) -}}
{{- end -}}
{{- end -}}
{{- if eq (.Values.serviceAccount.automountServiceAccountToken | toString) "true" -}}
{{- fail "serviceAccount.automountServiceAccountToken must be false: Hermes does not call the Kubernetes API, and a mounted token is a ready-made privilege escalation path for an agent that executes tools (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- end -}}

{{- if and .Values.rbac.create (not $hardening.allowWildcardRbac) -}}
{{- range $rule := .Values.rbac.rules -}}
{{- if or (has "*" ($rule.apiGroups | default list)) (has "*" ($rule.resources | default list)) (has "*" ($rule.verbs | default list)) -}}
{{- fail "rbac.rules contains a \"*\" wildcard: grant named apiGroups, resources and verbs (waive with hardening.allowWildcardRbac=true)." -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- if eq (trim (.Values.apiServer.corsOrigins | toString)) "*" -}}
{{- fail "apiServer.corsOrigins=\"*\" exposes the OpenAI-compatible endpoint to every origin: list the origins that need it." -}}
{{- end -}}

{{- if not .Values.networkPolicy.enabled -}}
{{- if not $hardening.allowUnrestrictedNetwork -}}
{{- fail "networkPolicy.enabled=false leaves the agent free to reach the cluster network and the cloud metadata endpoint (waive with hardening.allowUnrestrictedNetwork=true)." -}}
{{- end -}}
{{- else if .Values.networkPolicy.egress.allowPublicInternet -}}
{{- $excluded := .Values.networkPolicy.egress.excludedCidrs | default list -}}
{{- if and (not (has "169.254.0.0/16" $excluded)) (not $hardening.allowMetadataEndpointEgress) -}}
{{- fail "networkPolicy.egress.excludedCidrs must exclude 169.254.0.0/16: it is the cloud instance metadata endpoint and hands out node credentials to anything that can reach it (waive with hardening.allowMetadataEndpointEgress=true)." -}}
{{- end -}}
{{- if not $hardening.allowClusterInternalEgress -}}
{{- range $cidr := list "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" -}}
{{- if not (has $cidr $excluded) -}}
{{- fail (printf "networkPolicy.egress.excludedCidrs must exclude %s so the agent cannot reach cluster-internal or private-network services (waive with hardening.allowClusterInternalEgress=true)." $cidr) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
