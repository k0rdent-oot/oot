{{/*
Expand the name of the chart.
*/}}
{{- define "nutanix-capx.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "nutanix-capx.fullname" -}}
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
Create chart name and version as used by the chart label.
*/}}
{{- define "nutanix-capx.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "nutanix-capx.labels" -}}
helm.sh/chart: {{ include "nutanix-capx.chart" . }}
{{ include "nutanix-capx.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "nutanix-capx.selectorLabels" -}}
app.kubernetes.io/name: {{ include "nutanix-capx.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Template names for HCP mode
*/}}
{{- define "nutanix-capx.hcp.controlPlaneTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-hcp-cp
{{- end }}

{{- define "nutanix-capx.hcp.workerBootstrapTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-hcp-worker-bootstrap
{{- end }}

{{- define "nutanix-capx.hcp.workerMachineTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-hcp-worker-mt
{{- end }}

{{/*
Template names for Standalone mode
*/}}
{{- define "nutanix-capx.standalone.controlPlaneTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-standalone-cp
{{- end }}

{{- define "nutanix-capx.standalone.controlPlaneMachineTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-standalone-cp-mt
{{- end }}

{{- define "nutanix-capx.standalone.workerBootstrapTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-standalone-worker-bootstrap
{{- end }}

{{- define "nutanix-capx.standalone.workerMachineTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-standalone-worker-mt
{{- end }}

{{/*
Common template names
*/}}
{{- define "nutanix-capx.clusterTemplateName" -}}
{{- include "nutanix-capx.fullname" . }}-cluster
{{- end }}
