{{- define "stalwart.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "stalwart.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- include "stalwart.name" . -}}
{{- end -}}
{{- end -}}

{{- define "stalwart.labels" -}}
app.kubernetes.io/name: {{ include "stalwart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end -}}

{{- define "stalwart.selectorLabels" -}}
app.kubernetes.io/name: {{ include "stalwart.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}
