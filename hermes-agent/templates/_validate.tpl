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
{{- end -}}
{{- end -}}

{{- define "hermes-agent.validateHardening" -}}
{{- $hardening := .Values.hardening -}}

{{- if and (not .Values.image.digest) (not $hardening.allowMutableImageTag) -}}
{{- fail "image.digest is empty: a tag can be moved under you. Pin a digest (`make hermes-digest`, or scripts/sync-image-digest.sh) or set hardening.allowMutableImageTag=true." -}}
{{- end -}}

{{- if and (include "hermes-agent.hasInlineSecrets" .) (not $hardening.allowInlineSecrets) -}}
{{- fail (printf "inline secret values are refused (%s): plain API keys in values land in the Helm release Secret, in Git and in shell history. Use secrets.existingSecret or externalSecret.enabled, or set hardening.allowInlineSecrets=true." (include "hermes-agent.inlineSecretKeys" .)) -}}
{{- end -}}

{{- if not .Values.operator.enabled -}}
{{- if not $hardening.allowPrivilegedRuntime -}}
{{- $podSecurityContext := .Values.podSecurityContext | default dict -}}
{{- $securityContext := .Values.securityContext | default dict -}}
{{- $capabilities := $securityContext.capabilities | default dict -}}
{{- if ne ($podSecurityContext.runAsNonRoot | toString) "true" -}}
{{- fail "podSecurityContext.runAsNonRoot must be true (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($podSecurityContext.runAsUser | toString) "0" -}}
{{- fail "podSecurityContext.runAsUser must not be 0 (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.runAsUser | toString) "0" -}}
{{- fail "securityContext.runAsUser must not be 0 (waive with hardening.allowPrivilegedRuntime=true)." -}}
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
{{- if gt (len ($capabilities.add | default list)) 0 -}}
{{- fail "securityContext.capabilities.add must stay empty (waive with hardening.allowPrivilegedRuntime=true)." -}}
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
