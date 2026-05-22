{{/*
Expand the name of the chart.
*/}}
{{- define "cloudflare-operator.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "cloudflare-operator.fullname" -}}
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
{{- define "cloudflare-operator.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Target namespace (override > release).
*/}}
{{- define "cloudflare-operator.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride }}
{{- end }}

{{/*
Selector labels — must remain stable across upgrades to avoid orphaning pods.
*/}}
{{- define "cloudflare-operator.selectorLabels" -}}
app.kubernetes.io/name: {{ include "cloudflare-operator.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/component: controller-manager
{{- end }}

{{/*
Common labels stamped onto every resource.
*/}}
{{- define "cloudflare-operator.labels" -}}
helm.sh/chart: {{ include "cloudflare-operator.chart" . }}
{{ include "cloudflare-operator.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: cloudflare-operator
control-plane: controller-manager
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
Common annotations.
*/}}
{{- define "cloudflare-operator.annotations" -}}
{{- with .Values.commonAnnotations }}
{{ toYaml . }}
{{- end }}
{{- end }}

{{/*
ServiceAccount name resolver. Defaults to `<fullname>-controller-manager`
when serviceAccount.create is true and no explicit name is set.
*/}}
{{- define "cloudflare-operator.serviceAccountName" -}}
{{- if .Values.serviceAccount.name }}
{{- .Values.serviceAccount.name }}
{{- else if .Values.serviceAccount.create }}
{{- printf "%s-controller-manager" (include "cloudflare-operator.fullname" .) }}
{{- else }}
{{- "default" }}
{{- end }}
{{- end }}

{{/*
Image tag fallback to .Chart.AppVersion. Strips a leading "v" so docker tags
match upstream (`adyanth/cloudflare-operator:0.13.1`, not `:v0.13.1`).
*/}}
{{- define "cloudflare-operator.imageTag" -}}
{{- $tag := .Values.images.manager.tag -}}
{{- if not $tag -}}
{{- $tag = .Chart.AppVersion -}}
{{- end -}}
{{- $tag | trimPrefix "v" -}}
{{- end }}

{{/*
Image reference. Uses digest when set, falls back to tag.
Honors `global.imageRegistry` override.
Usage: {{ include "cloudflare-operator.image" (dict "image" .Values.images.manager "context" .) }}
*/}}
{{- define "cloudflare-operator.image" -}}
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
{{- $tag = $tag | trimPrefix "v" -}}
{{- printf "%s/%s:%s" $registry $img.repository $tag -}}
{{- end -}}
{{- end }}

{{/*
Merge chart-level and global image pull secrets into a single list.
*/}}
{{- define "cloudflare-operator.imagePullSecrets" -}}
{{- $secrets := concat (default (list) .Values.imagePullSecrets) (default (list) .Values.global.imagePullSecrets) -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - {{ if kindIs "map" . }}{{ toYaml . | nindent 4 | trim }}{{ else }}name: {{ . }}{{ end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding Cloudflare API credentials.
*/}}
{{- define "cloudflare-operator.cloudflareSecretName" -}}
{{- if .Values.credentials.existingSecret }}
{{- .Values.credentials.existingSecret }}
{{- else }}
{{- default "cloudflare-secrets" .Values.credentials.secretName }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding the Origin CA token.
*/}}
{{- define "cloudflare-operator.originIssuerSecretName" -}}
{{- if .Values.originIssuer.secret.existingSecret }}
{{- .Values.originIssuer.secret.existingSecret }}
{{- else }}
{{- default "origin-ca-issuer-secret" .Values.originIssuer.secret.name }}
{{- end }}
{{- end }}

{{/*
Resolve the Secret name holding the webhook TLS material.
*/}}
{{- define "cloudflare-operator.webhookCertSecretName" -}}
{{- if and (not .Values.webhook.certManager.enabled) .Values.webhook.existingSecretName -}}
{{- .Values.webhook.existingSecretName -}}
{{- else -}}
{{- printf "%s-webhook-tls" (include "cloudflare-operator.fullname" .) -}}
{{- end -}}
{{- end }}

{{/*
Resolve the Secret name holding metrics TLS material.
*/}}
{{- define "cloudflare-operator.metricsCertSecretName" -}}
{{- printf "%s-metrics-tls" (include "cloudflare-operator.fullname" .) -}}
{{- end }}

{{/*
Validate required values. Called from any template that depends on them.
*/}}
{{- define "cloudflare-operator.validate" -}}
{{- if and .Values.credentials.create .Values.credentials.existingSecret -}}
{{- fail "credentials.create=true and credentials.existingSecret are mutually exclusive. Pick one." -}}
{{- end -}}
{{- if and .Values.credentials.create (or (not .Values.credentials.apiToken) (not .Values.credentials.accountId)) -}}
{{- fail "credentials.create=true requires both credentials.apiToken and credentials.accountId. Pass via --set-string or sealed-secrets." -}}
{{- end -}}
{{- if and (not .Values.webhook.certManager.enabled) (not .Values.webhook.existingSecretName) -}}
{{- fail "webhook.certManager.enabled=false requires webhook.existingSecretName to point at a Secret containing tls.crt/tls.key." -}}
{{- end -}}
{{- if and .Values.webhook.certManager.enabled (not .Values.webhook.certManager.createSelfSignedIssuer) (not .Values.webhook.certManager.issuerRef.name) -}}
{{- fail "webhook.certManager.createSelfSignedIssuer=false requires webhook.certManager.issuerRef.name." -}}
{{- end -}}
{{- if and .Values.sampleClusterTunnel.enabled (or (not .Values.sampleClusterTunnel.cloudflareDomain) (not .Values.sampleClusterTunnel.cloudflareEmail)) -}}
{{- fail "sampleClusterTunnel.enabled=true requires sampleClusterTunnel.cloudflareDomain and sampleClusterTunnel.cloudflareEmail." -}}
{{- end -}}
{{- if and .Values.originIssuer.enabled .Values.originIssuer.secret.create (not .Values.originIssuer.secret.token) -}}
{{- fail "originIssuer.secret.create=true requires originIssuer.secret.token." -}}
{{- end -}}
{{- end }}
