{{- define "ankra-cloud-csi.name" -}}
ankra-cloud-csi
{{- end -}}

{{- define "ankra-cloud-csi.labels" -}}
app.kubernetes.io/name: {{ include "ankra-cloud-csi.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end -}}

{{- define "ankra-cloud-csi.image" -}}
{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}
{{- end -}}

{{- define "ankra-cloud-csi.secretName" -}}
{{- if .Values.api.existingSecret -}}
{{ .Values.api.existingSecret }}
{{- else -}}
{{ include "ankra-cloud-csi.name" . }}-api
{{- end -}}
{{- end -}}

{{/* The API environment shared by the controller and the node plugin. */}}
{{- define "ankra-cloud-csi.apiEnvironment" -}}
- name: ANKRA_CLOUD_API_URL
  value: {{ required "api.url is required" .Values.api.url | quote }}
- name: ANKRA_CLOUD_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ include "ankra-cloud-csi.secretName" . }}
      key: {{ .Values.api.existingSecretKey }}
{{- if .Values.api.caBundle.existingSecret }}
- name: ANKRA_CLOUD_CA_BUNDLE
  value: /etc/ankra-cloud/ca/{{ .Values.api.caBundle.key }}
{{- end }}
{{- end -}}

{{- define "ankra-cloud-csi.caVolumeMount" -}}
{{- if .Values.api.caBundle.existingSecret }}
- name: ca-bundle
  mountPath: /etc/ankra-cloud/ca
  readOnly: true
{{- end }}
{{- end -}}

{{- define "ankra-cloud-csi.caVolume" -}}
{{- if .Values.api.caBundle.existingSecret }}
- name: ca-bundle
  secret:
    secretName: {{ .Values.api.caBundle.existingSecret }}
{{- end }}
{{- end -}}
