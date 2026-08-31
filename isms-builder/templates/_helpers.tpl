{{- define "isms-builder.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "isms-builder.fullname" -}}
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

{{- define "isms-builder.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "isms-builder.labels" -}}
helm.sh/chart: {{ include "isms-builder.chart" . }}
{{ include "isms-builder.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: isms-builder
{{- end -}}

{{- define "isms-builder.selectorLabels" -}}
app.kubernetes.io/name: {{ include "isms-builder.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "isms-builder.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "isms-builder.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{- define "isms-builder.generatedSecretName" -}}
{{- printf "%s-secrets" (include "isms-builder.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "isms-builder.secretName" -}}
{{- if .Values.externalSecret.enabled -}}
{{- default (include "isms-builder.generatedSecretName" .) .Values.externalSecret.target.name -}}
{{- else if .Values.secrets.existingSecret -}}
{{- .Values.secrets.existingSecret -}}
{{- else -}}
{{- include "isms-builder.generatedSecretName" . -}}
{{- end -}}
{{- end -}}

{{- define "isms-builder.claimName" -}}
{{- if .Values.persistence.existingClaim -}}
{{- .Values.persistence.existingClaim -}}
{{- else -}}
{{- printf "%s-data" (include "isms-builder.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Fully qualified image reference. A digest always wins; the tag is kept
alongside it so `kubectl describe` still shows a human-readable version.
*/}}
{{- define "isms-builder.image" -}}
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
{{- define "isms-builder.inlineSecretKeys" -}}
{{- $keys := list -}}
{{- range $key, $value := .Values.secrets -}}
{{- if and (ne $key "existingSecret") (ne $key "annotations") (ne (printf "%v" $value) "") -}}
{{- $keys = append $keys $key -}}
{{- end -}}
{{- end -}}
{{- $keys | sortAlpha | toJson -}}
{{- end -}}

{{- define "isms-builder.hasInlineSecrets" -}}
{{- if gt (len (include "isms-builder.inlineSecretKeys" . | fromJsonArray)) 0 -}}true{{- end -}}
{{- end -}}

{{/*
True when the Secret consumed by the pod is managed outside this release.
*/}}
{{- define "isms-builder.secretManagedExternally" -}}
{{- if or .Values.externalSecret.enabled .Values.secrets.existingSecret -}}true{{- end -}}
{{- end -}}

{{/*
True when the storage backend needs an external SQL database.
*/}}
{{- define "isms-builder.usesSqlDatabase" -}}
{{- if has .Values.storage.backend (list "postgres" "mariadb") -}}true{{- end -}}
{{- end -}}
