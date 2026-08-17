{{- define "claude-code-openai-wrapper.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.fullname" -}}
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

{{- define "claude-code-openai-wrapper.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.labels" -}}
helm.sh/chart: {{ include "claude-code-openai-wrapper.chart" . }}
{{ include "claude-code-openai-wrapper.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: claude-code-openai-wrapper
{{- end -}}

{{- define "claude-code-openai-wrapper.selectorLabels" -}}
app.kubernetes.io/name: {{ include "claude-code-openai-wrapper.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "claude-code-openai-wrapper.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "claude-code-openai-wrapper.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.generatedSecretName" -}}
{{- printf "%s-secrets" (include "claude-code-openai-wrapper.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{- default (include "claude-code-openai-wrapper.generatedSecretName" .) .Values.externalSecret.target.name -}}
{{- else if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- include "claude-code-openai-wrapper.generatedSecretName" . -}}
{{- end -}}
{{- end -}}

{{/*
Fully qualified image reference. A digest always wins; the tag is kept
alongside it so `kubectl describe` still shows a human-readable version.
*/}}
{{- define "claude-code-openai-wrapper.image" -}}
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
Keys under .Values.secrets that carry an inline value, as a sorted JSON array.
`existingSecret` and `annotations` are reserved and never treated as data.
*/}}
{{- define "claude-code-openai-wrapper.inlineSecretKeys" -}}
{{- $keys := list -}}
{{- range $key, $value := .Values.secrets -}}
{{- if and (ne $key "existingSecret") (ne $key "annotations") (ne (printf "%v" $value) "") -}}
{{- $keys = append $keys $key -}}
{{- end -}}
{{- end -}}
{{- $keys | sortAlpha | toJson -}}
{{- end -}}

{{- define "claude-code-openai-wrapper.hasInlineSecrets" -}}
{{- if gt (len (include "claude-code-openai-wrapper.inlineSecretKeys" . | fromJsonArray)) 0 -}}true{{- end -}}
{{- end -}}

{{/*
True when the Secret consumed by the pod is managed outside this release.
*/}}
{{- define "claude-code-openai-wrapper.secretManagedExternally" -}}
{{- if or .Values.externalSecret.enabled .Values.secrets.existingSecret -}}true{{- end -}}
{{- end -}}
