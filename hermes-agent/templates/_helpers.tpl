{{- define "hermes-agent.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
Renders empty when no MCP server is declared, so callers can gate on it.
*/ -}}
{{- define "hermes-agent.mcpServers" -}}
{{- $servers := (.Values.mcp | default dict).servers | default dict -}}
{{- if gt (len $servers) 0 -}}
{{- $servers | toJson -}}
{{- end -}}
{{- end -}}

{{- /*
The agent validates mcp.json strictly: the document carries exactly $schema and
mcpServers, and anything else is rejected as an invalid top-level shape.
*/ -}}
{{- define "hermes-agent.mcpJson" -}}
{{- $servers := (.Values.mcp | default dict).servers | default dict -}}
{{- dict "$schema" "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json" "mcpServers" $servers | toPrettyJson -}}
{{- end -}}

{{- define "hermes-agent.cdpImage" -}}
{{- $image := .Values.browser.cdp.image -}}
{{- $reference := printf "%s/%s" $image.registry $image.repository -}}
{{- if $image.digest -}}
{{- printf "%s@%s" $reference $image.digest -}}
{{- else -}}
{{- printf "%s:%s" $reference $image.tag -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.tenantLabelKey" -}}
tenant.hermes.ai/id
{{- end -}}

{{- define "hermes-agent.tenantLabels" -}}
{{- if .Values.tenant.id }}
{{ include "hermes-agent.tenantLabelKey" . }}: {{ .Values.tenant.id | quote }}
{{- end }}
{{- with .Values.tenant.labels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{- define "hermes-agent.labels" -}}
helm.sh/chart: {{ include "hermes-agent.chart" . }}
{{ include "hermes-agent.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: hermes-agent
{{- $tenantLabels := include "hermes-agent.tenantLabels" . }}
{{- if $tenantLabels }}
{{ $tenantLabels }}
{{- end }}
{{- end -}}

{{- define "hermes-agent.selectorLabels" -}}
app.kubernetes.io/name: {{ include "hermes-agent.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "hermes-agent.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "hermes-agent.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.configMapName" -}}
{{- printf "%s-config" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.bootstrapConfigMapName" -}}
{{- default (include "hermes-agent.configMapName" .) .Values.bootstrap.existingConfigMap -}}
{{- end -}}

{{- define "hermes-agent.generatedSecretName" -}}
{{- printf "%s-secrets" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "hermes-agent.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{- default (include "hermes-agent.generatedSecretName" .) .Values.externalSecret.target.name -}}
{{- else if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- include "hermes-agent.generatedSecretName" . -}}
{{- end -}}
{{- end -}}

{{- define "hermes-agent.pvcName" -}}
{{- printf "%s-data" (include "hermes-agent.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified image reference. A digest always wins; the tag is kept
alongside it so `kubectl describe` still shows a human-readable version.
*/}}
{{- define "hermes-agent.image" -}}
{{- $repository := .Values.image.repository -}}
{{- if .Values.image.registry -}}
{{- $repository = printf "%s/%s" .Values.image.registry .Values.image.repository -}}
{{- end -}}
{{- $tag := default .Chart.AppVersion .Values.image.tag -}}
{{- if .Values.image.digest -}}
{{- if $tag -}}
{{- printf "%s:%s@%s" $repository $tag .Values.image.digest -}}
{{- else -}}
{{- printf "%s@%s" $repository .Values.image.digest -}}
{{- end -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
Fully qualified Camofox sidecar image reference, same digest-wins rule as the
agent image.
*/}}
{{- define "hermes-agent.camofoxImage" -}}
{{- $repository := .Values.camofox.image.repository -}}
{{- if .Values.camofox.image.registry -}}
{{- $repository = printf "%s/%s" .Values.camofox.image.registry .Values.camofox.image.repository -}}
{{- end -}}
{{- $tag := .Values.camofox.image.tag -}}
{{- if .Values.camofox.image.digest -}}
{{- if $tag -}}
{{- printf "%s:%s@%s" $repository $tag .Values.camofox.image.digest -}}
{{- else -}}
{{- printf "%s@%s" $repository .Values.camofox.image.digest -}}
{{- end -}}
{{- else -}}
{{- printf "%s:%s" $repository $tag -}}
{{- end -}}
{{- end -}}

{{/*
The URL the agent uses to reach Camofox: an explicit camofox.url wins,
otherwise the sidecar over loopback.
*/}}
{{- define "hermes-agent.camofoxUrl" -}}
{{- if .Values.camofox.url -}}
{{- .Values.camofox.url -}}
{{- else -}}
{{- printf "http://localhost:%v" .Values.camofox.port -}}
{{- end -}}
{{- end -}}

{{/*
Keys under .Values.secrets that carry an inline value, as a sorted JSON array.
`existingSecret` and `annotations` are reserved and never treated as data.
*/}}
{{- define "hermes-agent.inlineSecretKeys" -}}
{{- $keys := list -}}
{{- range $key, $value := .Values.secrets -}}
{{- if and (ne $key "existingSecret") (ne $key "annotations") (ne (printf "%v" $value) "") -}}
{{- $keys = append $keys $key -}}
{{- end -}}
{{- end -}}
{{- $keys | sortAlpha | toJson -}}
{{- end -}}

{{- define "hermes-agent.hasInlineSecrets" -}}
{{- if gt (len (include "hermes-agent.inlineSecretKeys" . | fromJsonArray)) 0 -}}true{{- end -}}
{{- end -}}

{{/*
True when the Secret consumed by the pod is managed outside this release.
*/}}
{{- define "hermes-agent.secretManagedExternally" -}}
{{- if or .Values.externalSecret.enabled .Values.secrets.existingSecret -}}true{{- end -}}
{{- end -}}

{{/*
Named model endpoints declared under config.values.providers, as JSON.
*/}}
{{- define "hermes-agent.modelProviders" -}}
{{- $config := .Values.config.values | default dict -}}
{{- $providers := $config.providers | default dict -}}
{{- if not (kindIs "map" $providers) -}}
{{- fail "config.values.providers must be a map of <name>: {api, key_env, ...}" -}}
{{- end -}}
{{- $providers | toJson -}}
{{- end -}}

{{/*
The fallback chain declared under config.values.fallback_providers, as JSON.
*/}}
{{- define "hermes-agent.fallbackProviders" -}}
{{- $config := .Values.config.values | default dict -}}
{{- $chain := $config.fallback_providers | default list -}}
{{- if not (kindIs "slice" $chain) -}}
{{- fail "config.values.fallback_providers must be a list of {provider, model, ...} entries" -}}
{{- end -}}
{{- $chain | toJson -}}
{{- end -}}

{{/*
The URL a provider entry points at. Hermes accepts `api` (current), `base_url`
(legacy) or `url`.
*/}}
{{- define "hermes-agent.providerEndpoint" -}}
{{- if kindIs "map" . -}}
{{- $endpoint := coalesce .api .base_url .url -}}
{{- if $endpoint -}}{{- $endpoint | toString | trim -}}{{- end -}}
{{- end -}}
{{- end -}}

{{/*
True when a URL resolves inside the cluster or a private network, which the
default NetworkPolicy egress excludes.
*/}}
{{- define "hermes-agent.isClusterInternalUrl" -}}
{{- $url := . | toString | lower -}}
{{- if regexMatch "^https?://(localhost|127\\.[0-9.]+|10\\.[0-9]+\\.[0-9]+\\.[0-9]+|192\\.168\\.[0-9]+\\.[0-9]+|172\\.(1[6-9]|2[0-9]|3[01])\\.[0-9]+\\.[0-9]+|[^/:]+\\.svc(\\.cluster\\.local)?|[^/:]+\\.cluster\\.local)(:[0-9]+)?(/.*)?$" $url -}}true{{- end -}}
{{- end -}}

{{/*
Model-endpoint entries (main model, named providers, fallback chain) that carry
an inline api_key, as a JSON array of value paths.
*/}}
{{- define "hermes-agent.inlineModelSecretPaths" -}}
{{- $paths := list -}}
{{- $config := .Values.config.values | default dict -}}
{{- $model := $config.model | default dict -}}
{{- if and (kindIs "map" $model) (ne (printf "%v" ($model.api_key | default "")) "") -}}
{{- $paths = append $paths "config.values.model.api_key" -}}
{{- end -}}
{{- range $name, $entry := include "hermes-agent.modelProviders" . | fromJson -}}
{{- if and (kindIs "map" $entry) (ne (printf "%v" ($entry.api_key | default "")) "") -}}
{{- $paths = append $paths (printf "config.values.providers.%s.api_key" $name) -}}
{{- end -}}
{{- end -}}
{{- range $index, $entry := include "hermes-agent.fallbackProviders" . | fromJsonArray -}}
{{- if and (kindIs "map" $entry) (ne (printf "%v" ($entry.api_key | default "")) "") -}}
{{- $paths = append $paths (printf "config.values.fallback_providers[%d].api_key" $index) -}}
{{- end -}}
{{- end -}}
{{- $paths | toJson -}}
{{- end -}}

{{/*
Names of the environment variables the chart itself puts on the agent
container: env, extraEnv and the inline secret keys. Keys that arrive through
secrets.existingSecret, externalSecret or extraEnvFrom are not visible here.
*/}}
{{- define "hermes-agent.chartManagedEnvNames" -}}
{{- $names := list -}}
{{- range $name, $_ := .Values.env | default dict -}}
{{- $names = append $names $name -}}
{{- end -}}
{{- range .Values.extraEnv | default list -}}
{{- if and (kindIs "map" .) .name -}}
{{- $names = append $names .name -}}
{{- end -}}
{{- end -}}
{{- $names = concat $names (include "hermes-agent.inlineSecretKeys" . | fromJsonArray) -}}
{{- $names | uniq | toJson -}}
{{- end -}}

{{/*
Service/container ports, as a JSON array. Explicit service.ports wins;
otherwise every enabled listener contributes its configured port.
*/}}
{{- define "hermes-agent.servicePorts" -}}
{{- $ports := list -}}
{{- if gt (len .Values.service.ports) 0 -}}
  {{- $ports = .Values.service.ports -}}
{{- else -}}
  {{- if .Values.apiServer.enabled -}}
    {{- $ports = append $ports (dict "name" "api-server" "port" (.Values.apiServer.port | int) "targetPort" (.Values.apiServer.port | int) "containerPort" (.Values.apiServer.port | int) "protocol" "TCP") -}}
  {{- end -}}
  {{- if .Values.webhook.enabled -}}
    {{- $ports = append $ports (dict "name" "webhook" "port" (.Values.webhook.port | int) "targetPort" (.Values.webhook.port | int) "containerPort" (.Values.webhook.port | int) "protocol" "TCP") -}}
  {{- end -}}
  {{- if .Values.telegramWebhook.enabled -}}
    {{- $ports = append $ports (dict "name" "telegram-webhook" "port" (.Values.telegramWebhook.port | int) "targetPort" (.Values.telegramWebhook.port | int) "containerPort" (.Values.telegramWebhook.port | int) "protocol" "TCP") -}}
  {{- end -}}
{{- end -}}
{{- $ports | toJson -}}
{{- end -}}

{{- define "hermes-agent.primaryServicePortNumber" -}}
{{- $servicePorts := include "hermes-agent.servicePorts" . | fromJsonArray -}}
{{- if and .Values.service.enabled (gt (len $servicePorts) 0) -}}
{{- (index $servicePorts 0).port -}}
{{- else -}}
{{- fail "service.enabled=true with either explicit service.ports entries or an enabled apiServer/webhook/telegramWebhook listener is required for ingress or virtualService routing" -}}
{{- end -}}
{{- end -}}
