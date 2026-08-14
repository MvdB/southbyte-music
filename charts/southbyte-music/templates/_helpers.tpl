{{/* Name und Vollname nach dem ueblichen Muster der Helm-Vorlage. */}}
{{- define "southbyte-music.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "southbyte-music.fullname" -}}
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

{{- define "southbyte-music.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "southbyte-music.labels" -}}
helm.sh/chart: {{ include "southbyte-music.chart" . }}
{{ include "southbyte-music.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "southbyte-music.selectorLabels" -}}
app.kubernetes.io/name: {{ include "southbyte-music.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "southbyte-music.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "southbyte-music.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/* Name des Modell-PVC: entweder ein vorhandenes oder das vom Chart angelegte. */}}
{{- define "southbyte-music.modelClaim" -}}
{{- if .Values.model.persistence.existingClaim }}
{{- .Values.model.persistence.existingClaim }}
{{- else }}
{{- printf "%s-modell" (include "southbyte-music.fullname" .) }}
{{- end }}
{{- end }}

{{/* Vollstaendiger Pfad zum Modell im Container. */}}
{{- define "southbyte-music.modelPath" -}}
{{- printf "/modelle/%s" .Values.model.dir }}
{{- end }}
