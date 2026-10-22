{{- define "petclinic.labels" -}}
app.kubernetes.io/name: {{ include "petclinic.fullname" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.app.component }}
{{- end -}}

{{- define "petclinic.fullname" -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if .Values.fullnameOverride -}}
{{- $name = .Values.fullnameOverride -}}
{{- end -}}
$name
{{- end -}}