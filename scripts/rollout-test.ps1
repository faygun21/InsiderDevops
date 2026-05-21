#Requires -Version 5.1
<#
.SYNOPSIS
    End-to-end Helm rollout + rollback drill for the insiderdevops chart.

.DESCRIPTION
    Demonstrates that a bad release can be detected and recovered:

      1. Deploy (helm upgrade --install) with values-dev.yaml.
      2. Wait for the rollout to become healthy.
      3. Bump the image tag to a deliberately FAKE version (v0.2.0-test).
         That tag was never loaded into minikube, so with
         imagePullPolicy: IfNotPresent the new pods get stuck in
         ErrImagePull / ImagePullBackOff — a realistic "bad deploy".
      4. Watch the rollout FAIL (bounded by a timeout — this failure is
         expected and does not abort the script).
      5. helm rollback to the previous (good) revision.
      6. Confirm the rollback is healthy, then print `helm history` and
         `kubectl rollout status` as evidence.

    All knobs are variables at the top so the release/namespace/tags are
    easy to change. Native tool failures are detected via $LASTEXITCODE
    (helm/kubectl do not raise PowerShell exceptions).

.EXAMPLE
    .\scripts\rollout-test.ps1
#>
[CmdletBinding()]
param()

# --- Configuration (edit these) -------------------------------------------
$Release       = "insiderdevops"
$Namespace     = "dev"
$ChartPath     = "./charts/insiderdevops"
$ValuesFile    = "values-dev.yaml"
$BadTag        = "v0.2.0-test"          # intentionally not loaded into minikube
$GoodTimeout   = "120s"                 # rollouts that SHOULD succeed
$BadTimeout    = "60s"                  # the rollout we EXPECT to fail
# --------------------------------------------------------------------------

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

# Resolve the Deployment name from the release label rather than hardcoding
# the Helm fullname logic, so this keeps working if $Release changes.
function Get-DeploymentName {
    $name = kubectl get deploy -n $Namespace `
        -l "app.kubernetes.io/instance=$Release" `
        -o jsonpath="{.items[0].metadata.name}" 2>$null
    return $name
}

# --- 1. Deploy the known-good release -------------------------------------
Write-Step "1/6  helm upgrade --install ($ValuesFile) -> namespace '$Namespace'"
helm upgrade --install $Release $ChartPath `
    -f $ValuesFile `
    --namespace $Namespace --create-namespace `
    --wait --timeout $GoodTimeout
Assert-LastExit "initial helm upgrade --install"

$Deployment = Get-DeploymentName
if ([string]::IsNullOrWhiteSpace($Deployment)) {
    Write-Error "Could not resolve the Deployment name via label app.kubernetes.io/instance=$Release"
    exit 1
}
Write-Host "Resolved Deployment: $Deployment" -ForegroundColor DarkGray

# --- 2. Wait for the good rollout -----------------------------------------
Write-Step "2/6  kubectl rollout status (expect: SUCCESS)"
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=$GoodTimeout
Assert-LastExit "rollout status for the initial release"

# --- 3. Push a deliberately bad image tag ---------------------------------
Write-Step "3/6  helm upgrade --set image.tag=$BadTag (a fake, unloaded tag)"
# No --wait here: helm returns immediately; the broken ReplicaSet rolls out
# in the background so we can observe (and then fix) the failure ourselves.
helm upgrade $Release $ChartPath `
    -f $ValuesFile `
    --namespace $Namespace `
    --set image.tag=$BadTag `
    --timeout $GoodTimeout
Assert-LastExit "helm upgrade to bad tag $BadTag"

# --- 4. Watch the bad rollout fail (expected) -----------------------------
Write-Step "4/6  kubectl rollout status (expect: FAILURE within $BadTimeout)"
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=$BadTimeout
if ($LASTEXITCODE -eq 0) {
    Write-Warning "The bad rollout unexpectedly succeeded. Was '$BadTag' loaded into minikube?"
} else {
    Write-Host "As expected: the rollout did NOT become healthy (exit $LASTEXITCODE)." -ForegroundColor Yellow
    Write-Host "Offending pods:" -ForegroundColor Yellow
    kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$Release"
}

# --- 5. Roll back to the previous good revision ---------------------------
Write-Step "5/6  helm rollback $Release 0  (0 = previous revision)"
helm rollback $Release 0 --namespace $Namespace --wait --timeout $GoodTimeout
Assert-LastExit "helm rollback"

kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=$GoodTimeout
Assert-LastExit "rollout status after rollback"
Write-Host "Recovered: the rollback is healthy again." -ForegroundColor Green

# --- 6. Evidence ----------------------------------------------------------
Write-Step "6/6  Evidence: helm history + rollout status + pods"
Write-Host "--- helm history $Release -n $Namespace ---" -ForegroundColor DarkGray
helm history $Release --namespace $Namespace

Write-Host ""
Write-Host "--- kubectl rollout status ---" -ForegroundColor DarkGray
kubectl rollout status "deployment/$Deployment" -n $Namespace --timeout=$GoodTimeout

Write-Host ""
Write-Host "--- pods ---" -ForegroundColor DarkGray
kubectl get pods -n $Namespace -l "app.kubernetes.io/instance=$Release" -o wide

Write-Host ""
Write-Host "Rollout/rollback drill complete." -ForegroundColor Green
