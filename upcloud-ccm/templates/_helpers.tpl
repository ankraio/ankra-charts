{{/*
Expand the name of the chart.
*/}}
{{- define "upcloud-ccm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "upcloud-ccm.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart label, used for `helm.sh/chart`.
*/}}
{{- define "upcloud-ccm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (override > release).
*/}}
{{- define "upcloud-ccm.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Selector labels — must remain stable across upgrades to avoid orphaning pods.
*/}}
{{- define "upcloud-ccm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "upcloud-ccm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels stamped onto every resource.
*/}}
{{- define "upcloud-ccm.labels" -}}
helm.sh/chart: {{ include "upcloud-ccm.chart" . }}
{{ include "upcloud-ccm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: cloud-controller-manager
app.kubernetes.io/part-of: upcloud-charts
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "upcloud-ccm.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name resolver.
*/}}
{{- define "upcloud-ccm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "upcloud-ccm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "cloud-controller-manager" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding UpCloud credentials.
Returns `existingSecret` when set, otherwise the chart-managed Secret name.
*/}}
{{- define "upcloud-ccm.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-credentials" (include "upcloud-ccm.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Image tag fallback to .Chart.AppVersion.
*/}}
{{- define "upcloud-ccm.imageTag" -}}
{{- if and .Values.images.ccm.tag (ne .Values.images.ccm.tag "") }}
{{- .Values.images.ccm.tag }}
{{- else }}
{{- .Chart.AppVersion }}
{{- end }}
{{- end }}

{{/*
Image reference. Uses digest when set, falls back to tag.
Honors `global.imageRegistry` override.
Usage: {{ include "upcloud-ccm.image" (dict "image" .Values.images.ccm "context" .) }}
*/}}
{{- define "upcloud-ccm.image" -}}
{{- $img := .image -}}
{{- $ctx := .context -}}
{{- $registry := default $img.registry $ctx.Values.global.imageRegistry -}}
{{- if $img.digest -}}
{{- printf "%s/%s@%s" $registry $img.repository $img.digest -}}
{{- else -}}
{{- $tag := $img.tag -}}
{{- if not $tag -}}
{{- $tag = $ctx.Chart.AppVersion -}}
{{- end -}}
{{- printf "%s/%s:%s" $registry $img.repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Merge chart-level and global image pull secrets into a single list.
*/}}
{{- define "upcloud-ccm.imagePullSecrets" -}}
{{- $secrets := concat (default (list) .Values.imagePullSecrets) (default (list) .Values.global.imagePullSecrets) -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - {{ if kindIs "map" . }}{{ toYaml . | nindent 4 | trim }}{{ else }}name: {{ . }}{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate required values. Called at the top of every template that depends on them.
*/}}
{{- define "upcloud-ccm.validate" -}}
{{- if not .Values.ccmConfig.clusterID }}
{{- fail "ccmConfig.clusterID is required. Generate one with `uuidgen` and pin it in your values." }}
{{- end }}
{{- if and .Values.credentials.create .Values.credentials.existingSecret }}
{{- fail "credentials.create and credentials.existingSecret are mutually exclusive." }}
{{- end }}
{{- if and .Values.credentials.create (or (not .Values.credentials.username) (not .Values.credentials.password)) }}
{{- fail "credentials.create=true requires both credentials.username and credentials.password." }}
{{- end }}
{{- end }}
