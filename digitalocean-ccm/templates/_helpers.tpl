{{/*
Expand the name of the chart.
*/}}
{{- define "digitalocean-ccm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "digitalocean-ccm.fullname" -}}
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
{{- define "digitalocean-ccm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (override > release).
*/}}
{{- define "digitalocean-ccm.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Selector labels — must remain stable across upgrades to avoid orphaning pods.
*/}}
{{- define "digitalocean-ccm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "digitalocean-ccm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Common labels stamped onto every resource.
*/}}
{{- define "digitalocean-ccm.labels" -}}
helm.sh/chart: {{ include "digitalocean-ccm.chart" . }}
{{ include "digitalocean-ccm.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: cloud-controller-manager
app.kubernetes.io/part-of: digitalocean-charts
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "digitalocean-ccm.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name resolver.
*/}}
{{- define "digitalocean-ccm.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "digitalocean-ccm.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "cloud-controller-manager" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding the DigitalOcean API token.
Returns `existingSecret` when set, otherwise the chart-managed Secret name.
*/}}
{{- define "digitalocean-ccm.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-credentials" (include "digitalocean-ccm.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Image reference. Uses digest when set, falls back to tag.
Honors `global.imageRegistry` override.
Usage: {{ include "digitalocean-ccm.image" (dict "image" .Values.images.ccm "context" .) }}
*/}}
{{- define "digitalocean-ccm.image" -}}
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
{{- define "digitalocean-ccm.imagePullSecrets" -}}
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
{{- define "digitalocean-ccm.validate" -}}
{{- if and .Values.credentials.create .Values.credentials.existingSecret }}
{{- fail "credentials.create and credentials.existingSecret are mutually exclusive." }}
{{- end }}
{{- if and .Values.credentials.create (not .Values.credentials.token) }}
{{- fail "credentials.create=true requires credentials.token." }}
{{- end }}
{{- end }}

{{/*
Replica-count validation, only relevant to the Deployment.
*/}}
{{- define "digitalocean-ccm.validateReplicas" -}}
{{- if and (gt (int .Values.replicaCount) 1) (not .Values.leaderElect) }}
{{- fail "replicaCount > 1 requires leaderElect=true." }}
{{- end }}
{{- end }}
