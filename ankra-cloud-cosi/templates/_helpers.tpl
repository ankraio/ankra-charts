{{- define "ankra-cloud-cosi.name" -}}
ankra-cloud-cosi
{{- end -}}

{{- define "ankra-cloud-cosi.labels" -}}
app.kubernetes.io/name: {{ include "ankra-cloud-cosi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "ankra-cloud-cosi.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ankra-cloud-cosi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{- define "ankra-cloud-cosi.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}

{{- define "ankra-cloud-cosi.secretName" -}}
{{- if .Values.api.existingSecret -}}
{{ .Values.api.existingSecret }}
{{- else -}}
{{ include "ankra-cloud-cosi.name" . }}-api
{{- end -}}
{{- end -}}

{{/* Whether the cluster serves the COSI API (the CRDs of the container-object-storage-interface controller). */}}
{{- define "ankra-cloud-cosi.servesCOSI" -}}
{{- if .Capabilities.APIVersions.Has "objectstorage.k8s.io/v1alpha1/BucketClass" -}}
true
{{- end -}}
{{- end -}}
