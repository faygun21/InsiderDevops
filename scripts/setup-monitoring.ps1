#Requires -Version 5.1
<#
.SYNOPSIS
    Install the kube-prometheus-stack (Prometheus + Grafana + Alertmanager)
    into the `monitoring` namespace and wait for Grafana to be ready.

.DESCRIPTION
    kube-prometheus-stack is the community umbrella chart that bundles the
    Prometheus Operator, Prometheus, Alertmanager, Grafana and a set of
    kube-state-metrics / node-exporter exporters in a single release. It is the
    de-facto standard way to stand up cluster monitoring.

    Two --set overrides matter for this case study:

      prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false
        By default the Operator only scrapes ServiceMonitors carrying the
        stack's own release label. Setting this to false makes Prometheus pick
        up EVERY ServiceMonitor in the cluster, so the app's ServiceMonitor
        (charts/insiderdevops/templates/servicemonitor.yaml) is discovered even
        though it lives in the `dev` namespace, not `monitoring`.

      grafana.adminPassword=admin123
        Passed only via --set (never committed) so there is no password baked
        into source. Rotate it for anything beyond a local demo.

    Native tools (helm/kubectl) signal failure via $LASTEXITCODE rather than
    PowerShell exceptions, so each step is checked explicitly.

.EXAMPLE
    .\scripts\setup-monitoring.ps1
#>
[CmdletBinding()]
param(
    [string]$Namespace     = "monitoring",
    [string]$Release       = "kube-prometheus-stack",
    [string]$GrafanaPass   = "admin123",
    [string]$Timeout       = "5m"
)

$ErrorActionPreference = "Stop"

function Assert-LastExit {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED: $What (exit code $LASTEXITCODE)"
        exit 1
    }
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host "==================================================================" -ForegroundColor Cyan
    Write-Host " $Text" -ForegroundColor Cyan
    Write-Host "==================================================================" -ForegroundColor Cyan
}

# --- 1. Add and refresh the prometheus-community Helm repo -----------------
Write-Step "1/4  helm repo add prometheus-community + repo update"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
Assert-LastExit "helm repo add prometheus-community"
helm repo update
Assert-LastExit "helm repo update"

# --- 2. Install / upgrade the stack ---------------------------------------
Write-Step "2/4  helm upgrade --install $Release -> namespace '$Namespace'"
helm upgrade --install $Release prometheus-community/kube-prometheus-stack `
    --namespace $Namespace --create-namespace `
    --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false `
    --set grafana.adminPassword=$GrafanaPass `
    --timeout $Timeout
Assert-LastExit "helm upgrade --install kube-prometheus-stack"

# --- 3. Wait for Grafana to be ready --------------------------------------
Write-Step "3/4  Waiting for Grafana to roll out (timeout 300s)"
kubectl rollout status "deployment/$Release-grafana" -n $Namespace --timeout=300s
Assert-LastExit "rollout status for $Release-grafana"

# --- 4. Print access instructions -----------------------------------------
Write-Step "4/4  Monitoring is up. Access instructions:"
Write-Host ""
Write-Host "Grafana (admin / $GrafanaPass):" -ForegroundColor Green
Write-Host "  kubectl port-forward svc/$Release-grafana 3000:80 -n $Namespace" -ForegroundColor Gray
Write-Host "  then open http://localhost:3000" -ForegroundColor Gray
Write-Host ""
Write-Host "Prometheus:" -ForegroundColor Green
Write-Host "  kubectl port-forward svc/$Release-prometheus 9090:9090 -n $Namespace" -ForegroundColor Gray
Write-Host "  then open http://localhost:9090  (Status > Targets to confirm the app is scraped)" -ForegroundColor Gray
Write-Host ""
Write-Host "Import the dashboard from monitoring/grafana-dashboard.json once Grafana is open." -ForegroundColor Green
