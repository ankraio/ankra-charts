{{/*
Render-time validation. Functional rules always run; the hardening rules can be
waived one at a time through the .Values.hardening flags so that an operator who
needs a weaker posture has to say so explicitly, in values, under review.
*/}}

{{- define "claude-code-openai-wrapper.validate" -}}
{{- include "claude-code-openai-wrapper.validateRuntime" . -}}
{{- if .Values.hardening.enabled -}}
{{- include "claude-code-openai-wrapper.validateHardening" . -}}
{{- end -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.validateRuntime" -}}
{{- $inlineSecretKeys := include "claude-code-openai-wrapper.inlineSecretKeys" . | fromJsonArray -}}
{{- if not (has .Values.auth.method (list "api-key" "bedrock" "vertex")) -}}
{{- fail (printf "auth.method must be api-key, bedrock or vertex; got %q." .Values.auth.method) -}}
{{- end -}}
{{- if and (eq .Values.auth.method "api-key") (not (include "claude-code-openai-wrapper.secretManagedExternally" .)) (not (has "ANTHROPIC_API_KEY" $inlineSecretKeys)) -}}
{{- fail "auth.method=api-key requires an ANTHROPIC_API_KEY: set secrets.existingSecret, enable externalSecret, or supply secrets.ANTHROPIC_API_KEY. For AWS or GCP credentials use auth.method=bedrock or vertex." -}}
{{- end -}}
{{- if and (eq .Values.auth.method "bedrock") (not .Values.auth.bedrock.region) -}}
{{- fail "auth.method=bedrock requires auth.bedrock.region." -}}
{{- end -}}
{{- if eq .Values.auth.method "vertex" -}}
{{- if not .Values.auth.vertex.projectId -}}
{{- fail "auth.method=vertex requires auth.vertex.projectId." -}}
{{- end -}}
{{- if not .Values.auth.vertex.region -}}
{{- fail "auth.method=vertex requires auth.vertex.region." -}}
{{- end -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled .Values.secrets.existingSecret -}}
{{- fail "externalSecret.enabled and secrets.existingSecret are mutually exclusive: pick which one owns the Secret." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (include "claude-code-openai-wrapper.hasInlineSecrets" .) -}}
{{- fail "externalSecret.enabled cannot be combined with inline secrets.<KEY> values." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (not .Values.externalSecret.secretStoreRef.name) -}}
{{- fail "externalSecret.enabled=true requires externalSecret.secretStoreRef.name." -}}
{{- end -}}
{{- if and .Values.ingress.enabled (not .Values.service.enabled) -}}
{{- fail "ingress.enabled=true requires service.enabled=true." -}}
{{- end -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.validateHardening" -}}
{{- $hardening := .Values.hardening -}}
{{- $inlineSecretKeys := include "claude-code-openai-wrapper.inlineSecretKeys" . | fromJsonArray -}}

{{- if and (not .Values.image.digest) (not $hardening.allowMutableImageTag) -}}
{{- fail "image.digest is empty: a tag can be moved under you. Pin a digest (scripts/sync-image-digest.sh claude-code-openai-wrapper) or set hardening.allowMutableImageTag=true." -}}
{{- end -}}

{{- if and (include "claude-code-openai-wrapper.hasInlineSecrets" .) (not $hardening.allowInlineSecrets) -}}
{{- fail (printf "inline secret values are refused (%s): plain API keys in values land in the Helm release Secret, in Git and in shell history. Use secrets.existingSecret or externalSecret.enabled, or set hardening.allowInlineSecrets=true." (include "claude-code-openai-wrapper.inlineSecretKeys" .)) -}}
{{- end -}}

{{/*
Any Ingress makes every endpoint reachable from outside the cluster, including
POST /v1/tools/config, which switches on Claude Code's Read/Write/Bash tools
inside the pod. API_KEY is the wrapper's own bearer-token protection.
*/}}
{{- if and .Values.ingress.enabled (not $hardening.allowUnauthenticatedIngress) (not (include "claude-code-openai-wrapper.secretManagedExternally" .)) (not (has "API_KEY" $inlineSecretKeys)) -}}
{{- fail "ingress.enabled=true requires an API_KEY for the wrapper's bearer-token protection: add the key to secrets.existingSecret or the ExternalSecret, or supply secrets.API_KEY (waive with hardening.allowUnauthenticatedIngress=true)." -}}
{{- end -}}

{{- if and (has "*" .Values.server.corsOrigins) (not $hardening.allowWildcardCors) -}}
{{- fail "server.corsOrigins contains \"*\", which exposes the API to every browser origin: list the origins that need it (waive with hardening.allowWildcardCors=true)." -}}
{{- end -}}

{{- if not $hardening.allowPrivilegedRuntime -}}
{{- $podSecurityContext := .Values.podSecurityContext | default dict -}}
{{- $securityContext := .Values.securityContext | default dict -}}
{{- $capabilities := $securityContext.capabilities | default dict -}}
{{- if ne ($podSecurityContext.runAsNonRoot | toString) "true" -}}
{{- fail "podSecurityContext.runAsNonRoot must be true: the image runs as its fixed wrapper user (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- $runAsUser := $podSecurityContext.runAsUser | toString -}}
{{- if or (eq $runAsUser "0") (eq $runAsUser "") (eq $runAsUser "<no value>") -}}
{{- fail "podSecurityContext.runAsUser must be a non-zero uid (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.privileged | toString) "true" -}}
{{- fail "securityContext.privileged must not be true (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.allowPrivilegeEscalation | toString) "true" -}}
{{- fail "securityContext.allowPrivilegeEscalation must be false (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if ne ($securityContext.readOnlyRootFilesystem | toString) "true" -}}
{{- fail "securityContext.readOnlyRootFilesystem must be true; the writable paths (HOME, /tmp) are provided as emptyDirs (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if not (has "ALL" ($capabilities.drop | default list)) -}}
{{- fail "securityContext.capabilities.drop must contain ALL (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if gt (len ($capabilities.add | default list)) 0 -}}
{{- fail "securityContext.capabilities.add must stay empty: the wrapper needs no capability at all (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq (.Values.serviceAccount.automountServiceAccountToken | toString) "true" -}}
{{- fail "serviceAccount.automountServiceAccountToken must be false: the wrapper does not call the Kubernetes API, and a mounted token is a ready-made privilege escalation path for a service whose tool mode executes commands in the pod (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- end -}}

{{- if not .Values.networkPolicy.enabled -}}
{{- if not $hardening.allowUnrestrictedNetwork -}}
{{- fail "networkPolicy.enabled=false leaves the wrapper free to reach the cluster network and the cloud metadata endpoint (waive with hardening.allowUnrestrictedNetwork=true)." -}}
{{- end -}}
{{- else if .Values.networkPolicy.egress.allowPublicInternet -}}
{{- $excluded := .Values.networkPolicy.egress.excludedCidrs | default list -}}
{{- if and (not (has "169.254.0.0/16" $excluded)) (not $hardening.allowMetadataEndpointEgress) -}}
{{- fail "networkPolicy.egress.excludedCidrs must exclude 169.254.0.0/16: it is the cloud instance metadata endpoint and hands out node credentials to anything that can reach it (waive with hardening.allowMetadataEndpointEgress=true)." -}}
{{- end -}}
{{- if not $hardening.allowClusterInternalEgress -}}
{{- range $cidr := list "10.0.0.0/8" "172.16.0.0/12" "192.168.0.0/16" -}}
{{- if not (has $cidr $excluded) -}}
{{- fail (printf "networkPolicy.egress.excludedCidrs must exclude %s so the wrapper cannot reach cluster-internal or private-network services (waive with hardening.allowClusterInternalEgress=true)." $cidr) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
