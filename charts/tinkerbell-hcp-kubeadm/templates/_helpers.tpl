{{/*
Expand the name of the chart.
*/}}
{{- define "tinkerbell-hcp-kubeadm.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "tinkerbell-hcp-kubeadm.fullname" -}}
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
Cluster name - defaults to release name
*/}}
{{- define "tinkerbell-hcp-kubeadm.clusterName" -}}
{{- default .Release.Name .Values.clusterName }}
{{- end }}

{{/*
Gateway name
*/}}
{{- define "tinkerbell-hcp-kubeadm.gatewayName" -}}
{{- .Values.gateway.name | default "capi" }}
{{- end }}
