{{/*
Expand the name of the chart.
*/}}
{{- define "upcloud-csi.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "upcloud-csi.fullname" -}}
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
Chart label.
*/}}
{{- define "upcloud-csi.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (override > release).
*/}}
{{- define "upcloud-csi.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Common labels.
*/}}
{{- define "upcloud-csi.labels" -}}
helm.sh/chart: {{ include "upcloud-csi.chart" . }}
app.kubernetes.io/name: {{ include "upcloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: upcloud-charts
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Controller selector labels — stable across upgrades.
*/}}
{{- define "upcloud-csi.controllerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "upcloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: controller
app: csi-upcloud-controller
{{- end }}

{{/*
Node DaemonSet selector labels — stable across upgrades.
*/}}
{{- define "upcloud-csi.nodeSelectorLabels" -}}
app.kubernetes.io/name: {{ include "upcloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: node
app: csi-upcloud-node
{{- end }}

{{/*
Snapshot Controller selector labels.
*/}}
{{- define "upcloud-csi.snapshotControllerSelectorLabels" -}}
app.kubernetes.io/name: {{ include "upcloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: snapshot-controller
app: csi-upcloud-snapshot-controller
{{- end }}

{{/*
Snapshot validation webhook selector labels.
*/}}
{{- define "upcloud-csi.snapshotWebhookSelectorLabels" -}}
app.kubernetes.io/name: {{ include "upcloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: snapshot-validation
app: csi-upcloud-snapshot-validation
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "upcloud-csi.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding UpCloud credentials.
*/}}
{{- define "upcloud-csi.secretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- printf "%s-credentials" (include "upcloud-csi.fullname" .) }}
{{- end }}
{{- end }}

{{/*
Image reference. Uses digest when set, falls back to tag.
Honors `global.imageRegistry` override.
Usage: {{ include "upcloud-csi.image" (dict "image" .Values.images.csiDriver "context" .) }}
*/}}
{{- define "upcloud-csi.image" -}}
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
Merge chart-level and global image pull secrets.
*/}}
{{- define "upcloud-csi.imagePullSecrets" -}}
{{- $secrets := concat (default (list) .Values.imagePullSecrets) (default (list) .Values.global.imagePullSecrets) -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - {{ if kindIs "map" . }}{{ toYaml . | nindent 4 | trim }}{{ else }}name: {{ . }}{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Resolve the StorageClass name for a given tier (maxiops|standard|hdd).
Falls back to the upstream-default name when not overridden.
*/}}
{{- define "upcloud-csi.storageClassName" -}}
{{- $tier := .tier -}}
{{- $ctx := .context -}}
{{- $cfg := index $ctx.Values.storageClasses $tier -}}
{{- $cfg.name -}}
{{- end }}

{{/*
Validate values.
*/}}
{{- define "upcloud-csi.validate" -}}
{{- if and .Values.credentials.create .Values.credentials.existingSecret }}
{{- fail "credentials.create and credentials.existingSecret are mutually exclusive." }}
{{- end }}
{{- if and (not .Values.credentials.create) (not .Values.credentials.existingSecret) }}
{{- fail "Either credentials.create=true (with username/password) or credentials.existingSecret must be set." }}
{{- end }}
{{- if and .Values.credentials.create (or (not .Values.credentials.username) (not .Values.credentials.password)) }}
{{- fail "credentials.create=true requires both credentials.username and credentials.password." }}
{{- end }}
{{- $dc := .Values.storageClasses.defaultClass -}}
{{- if and $dc (not (has $dc (list "" "maxiops" "standard" "hdd"))) }}
{{- fail (printf "storageClasses.defaultClass must be one of: \"\", maxiops, standard, hdd (got %q)" $dc) }}
{{- end }}
{{- if $dc -}}
  {{- $tierCfg := index .Values.storageClasses $dc -}}
  {{- if not $tierCfg.enabled -}}
    {{- fail (printf "storageClasses.defaultClass=%q but storageClasses.%s.enabled=false. Enable the tier or pick a different default." $dc $dc) -}}
  {{- end -}}
{{- end -}}
{{- end }}
