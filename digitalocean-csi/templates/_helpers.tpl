{{/*
Expand the name of the chart.
*/}}
{{- define "digitalocean-csi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "digitalocean-csi.fullname" -}}
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
{{- define "digitalocean-csi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (override > release).
*/}}
{{- define "digitalocean-csi.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Selector labels for the controller StatefulSet.
*/}}
{{- define "digitalocean-csi.controllerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "digitalocean-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: controller
{{- end }}

{{/*
Selector labels for the node DaemonSet.
*/}}
{{- define "digitalocean-csi.nodeSelectorLabels" -}}
app.kubernetes.io/name: {{ include "digitalocean-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: node
{{- end }}

{{/*
Selector labels for the snapshot controller.
*/}}
{{- define "digitalocean-csi.snapshotControllerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "digitalocean-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: snapshot-controller
{{- end }}

{{/*
Common labels stamped onto every resource.
*/}}
{{- define "digitalocean-csi.labels" -}}
helm.sh/chart: {{ include "digitalocean-csi.chart" . }}
app.kubernetes.io/name: {{ include "digitalocean-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: digitalocean-charts
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "digitalocean-csi.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding the DigitalOcean API token.
*/}}
{{- define "digitalocean-csi.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-credentials" (include "digitalocean-csi.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Image reference. Uses digest when set, falls back to tag, then AppVersion.
Usage: {{ include "digitalocean-csi.image" (dict "image" .Values.images.csiDriver "context" .) }}
*/}}
{{- define "digitalocean-csi.image" -}}
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
{{- define "digitalocean-csi.imagePullSecrets" -}}
{{- $secrets := concat (default (list) .Values.imagePullSecrets) (default (list) .Values.global.imagePullSecrets) -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - {{ if kindIs "map" . }}{{ toYaml . | nindent 4 | trim }}{{ else }}name: {{ . }}{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Validate required values.
*/}}
{{- define "digitalocean-csi.validate" -}}
{{- if and .Values.credentials.create .Values.credentials.existingSecret }}
{{- fail "credentials.create and credentials.existingSecret are mutually exclusive." }}
{{- end }}
{{- if and .Values.credentials.create (not .Values.credentials.token) }}
{{- fail "credentials.create=true requires credentials.token." }}
{{- end }}
{{- end }}
