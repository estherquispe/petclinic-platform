{{- /*
Expand the name of the chart.
*/}}
{{- define "petclinic.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- /*
Create a fully qualified resource name.
Per-service values set `nameOverride` so rendered names match the base K8s
manifests (e.g. `config-server`) rather than being prefixed with the release
name.
*/}}
{{- define "petclinic.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- /*
Common labels following the Kubernetes recommended label convention.
*/}}
{{- define "petclinic.labels" -}}
app.kubernetes.io/name: {{ include "petclinic.fullname" . }}
app.kubernetes.io/part-of: petclinic
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/component: {{ .Values.app.component }}
{{- end -}}

{{- /*
Service account name used by the deployment.
*/}}
{{- define "petclinic.serviceAccountName" -}}
{{- default (include "petclinic.fullname" .) .Values.serviceAccount.name | trunc 63 | trimSuffix "-" }}
{{- end -}}