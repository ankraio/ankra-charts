{{- define "ankra-cloud-ccm.name" -}}
ankra-cloud-ccm
{{- end -}}

{{- define "ankra-cloud-ccm.labels" -}}
app.kubernetes.io/name: {{ include "ankra-cloud-ccm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/component: cloud-controller-manager
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
{{- end -}}

{{- define "ankra-cloud-ccm.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ankra-cloud-ccm.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ankra-cloud-ccm.secretName" -}}
{{- if .Values.api.existingSecret -}}
{{ .Values.api.existingSecret }}
{{- else -}}
{{ include "ankra-cloud-ccm.name" . }}
{{- end -}}
{{- end -}}

{{- define "ankra-cloud-ccm.hasCABundle" -}}
{{- if or .Values.api.caBundle .Values.api.existingSecretHasCABundle -}}true{{- end -}}
{{- end -}}
