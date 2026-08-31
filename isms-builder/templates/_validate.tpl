{{/*
Render-time validation. Functional rules always run; the hardening rules can be
waived one at a time through the .Values.hardening flags so that an operator who
needs a weaker posture has to say so explicitly, in values, under review.
*/}}

{{- define "isms-builder.validate" -}}
{{- include "isms-builder.validateRuntime" . -}}
{{- if .Values.hardening.enabled -}}
{{- include "isms-builder.validateHardening" . -}}
{{- end -}}
{{- end -}}

{{- define "isms-builder.validateRuntime" -}}
{{- $inlineSecretKeys := include "isms-builder.inlineSecretKeys" . | fromJsonArray -}}
{{- if not (has .Values.storage.backend (list "json" "sqlite" "postgres" "mariadb")) -}}
{{- fail (printf "storage.backend must be json, sqlite, postgres or mariadb; got %q." .Values.storage.backend) -}}
{{- end -}}
{{/*
JWT_SECRET signs every login token. Without it upstream falls back to a
well-known development default, which makes every session forgeable.
*/}}
{{- if and (not (include "isms-builder.secretManagedExternally" .)) (not (has "JWT_SECRET" $inlineSecretKeys)) -}}
{{- fail "a JWT_SECRET is required - it signs every login token: set secrets.existingSecret, enable externalSecret, or supply secrets.JWT_SECRET." -}}
{{- end -}}
{{- if include "isms-builder.usesSqlDatabase" . -}}
{{- if not .Values.storage.database.host -}}
{{- fail (printf "storage.backend=%s requires storage.database.host." .Values.storage.backend) -}}
{{- end -}}
{{- if and (not (include "isms-builder.secretManagedExternally" .)) (not (has "DB_PASS" $inlineSecretKeys)) -}}
{{- fail (printf "storage.backend=%s requires a DB_PASS: add the key to secrets.existingSecret or the ExternalSecret, or supply secrets.DB_PASS." .Values.storage.backend) -}}
{{- end -}}
{{- end -}}
{{- if and .Values.smtp.user (not (include "isms-builder.secretManagedExternally" .)) (not (has "SMTP_PASS" $inlineSecretKeys)) -}}
{{- fail "smtp.user is set but no SMTP_PASS is available: add the key to secrets.existingSecret or the ExternalSecret, or supply secrets.SMTP_PASS." -}}
{{- end -}}
{{/*
Uploaded files and the json/sqlite stores are per-pod files on one
ReadWriteOnce volume; a second replica would serve a different ISMS and the
two would silently diverge. Not waivable - it does not work.
*/}}
{{- if ne (int .Values.replicaCount) 1 -}}
{{- fail (printf "replicaCount must be 1: file uploads and the json/sqlite storage backends are per-pod state on a single ReadWriteOnce volume, so %d replicas would each hold a different ISMS." (int .Values.replicaCount)) -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled .Values.secrets.existingSecret -}}
{{- fail "externalSecret.enabled and secrets.existingSecret are mutually exclusive: pick which one owns the Secret." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (include "isms-builder.hasInlineSecrets" .) -}}
{{- fail "externalSecret.enabled cannot be combined with inline secrets.<KEY> values." -}}
{{- end -}}
{{- if and .Values.externalSecret.enabled (not .Values.externalSecret.secretStoreRef.name) -}}
{{- fail "externalSecret.enabled=true requires externalSecret.secretStoreRef.name." -}}
{{- end -}}
{{- if and .Values.ingress.enabled (not .Values.service.enabled) -}}
{{- fail "ingress.enabled=true requires service.enabled=true." -}}
{{- end -}}
{{- end -}}

{{- define "isms-builder.validateHardening" -}}
{{- $hardening := .Values.hardening -}}

{{- if and (not .Values.image.digest) (not $hardening.allowMutableImageTag) -}}
{{- fail "image.digest is empty: a tag can be moved under you. Pin a digest (scripts/sync-image-digest.sh isms-builder) or set hardening.allowMutableImageTag=true." -}}
{{- end -}}

{{- if and (include "isms-builder.hasInlineSecrets" .) (not $hardening.allowInlineSecrets) -}}
{{- fail (printf "inline secret values are refused (%s): plain secrets in values land in the Helm release Secret, in Git and in shell history. Use secrets.existingSecret or externalSecret.enabled, or set hardening.allowInlineSecrets=true." (include "isms-builder.inlineSecretKeys" .)) -}}
{{- end -}}

{{- if not $hardening.allowPrivilegedRuntime -}}
{{- $podSecurityContext := .Values.podSecurityContext | default dict -}}
{{- $securityContext := .Values.securityContext | default dict -}}
{{- $capabilities := $securityContext.capabilities | default dict -}}
{{- if ne ($podSecurityContext.runAsNonRoot | toString) "true" -}}
{{- fail "podSecurityContext.runAsNonRoot must be true: the chart bypasses the image's root entrypoint and runs the server directly as the image's isms user (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- $runAsUser := $podSecurityContext.runAsUser | toString -}}
{{- if or (eq $runAsUser "0") (eq $runAsUser "") (eq $runAsUser "<no value>") -}}
{{- fail "podSecurityContext.runAsUser must be a non-zero uid (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.privileged | toString) "true" -}}
{{- fail "securityContext.privileged must not be true (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq ($securityContext.allowPrivilegeEscalation | toString) "true" -}}
{{- fail "securityContext.allowPrivilegeEscalation must be false (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if ne ($securityContext.readOnlyRootFilesystem | toString) "true" -}}
{{- fail "securityContext.readOnlyRootFilesystem must be true; the writable paths (/app/data, /tmp) are provided as volumes (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if not (has "ALL" ($capabilities.drop | default list)) -}}
{{- fail "securityContext.capabilities.drop must contain ALL (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if gt (len ($capabilities.add | default list)) 0 -}}
{{- fail "securityContext.capabilities.add must stay empty: the server needs no capability at all (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- if eq (.Values.serviceAccount.automountServiceAccountToken | toString) "true" -}}
{{- fail "serviceAccount.automountServiceAccountToken must be false: the server does not call the Kubernetes API, and a mounted token is a ready-made privilege escalation path (waive with hardening.allowPrivilegedRuntime=true)." -}}
{{- end -}}
{{- end -}}

{{- if and (not .Values.networkPolicy.enabled) (not $hardening.allowUnrestrictedNetwork) -}}
{{- fail "networkPolicy.enabled=false leaves the pod holding your ISMS records free to reach - and be reached by - the whole cluster network (waive with hardening.allowUnrestrictedNetwork=true)." -}}
{{- end -}}
{{- end -}}
