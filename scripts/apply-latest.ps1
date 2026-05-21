#Requires -Version 5.1
<#
.SYNOPSIS
    Apply the image recorded by CI (deploy/current-image.txt) to the local
    minikube cluster — the local half of the Track B "poor man's GitOps" flow.

.DESCRIPTION
    deploy.yaml runs on every push to main, writes the desired image reference
    (ghcr.io/faygun21/insiderdevops:<sha>) into deploy/current-image.txt, and
    commits it back to the repo. Because a GitHub-hosted runner cannot reach
    the developer's local minikube, the actual rollout is pulled onto the
    cluster here, on the laptop:

        git pull                       # fetch the latest deploy/current-image.txt
        .\scripts\apply-latest.ps1

    This script:
      1. Reads the image reference from deploy/current-image.txt.
      2. Splits it into repository + tag.
      3. helm upgrade --install into namespace `dev` with values-dev.yaml,
         overriding image.repository / image.tag to the GHCR image.
      4. Waits for the rollout to become healthy.

    NOTE: the image now lives in GHCR, not minikube's local daemon. For the
    kubelet to pull it the GHCR package must be PUBLIC (or an imagePullSecret
    configured). Alternatively pre-load it once with:
        minikube image load ghcr.io/faygun21/insiderdevops:<tag>

.PARAMETER ImageFile
    Path to the file containing the image reference. Defaults to
    deploy/current-image.txt.

.EXAMPLE
    .\scripts\apply-latest.ps1
#>
[CmdletBinding()]
param(
    [string]$ImageFile = "deploy/current-image.txt"
)

# --- Configuration --------------------------------------------------------
$Release    = "insiderdevops"
$ChartPath  = ".\charts\insiderdevops"
$ValuesFile = "values-dev.yaml"
$Namespace  = "dev"
$Timeout    = "120s"
# --------------------------------------------------------------------------

$ErrorActionPreference = "Stop"

function Assert-LastExit {
    param([string]$What)
    if ($LASTEXITCODE -ne 0) {
        Write-Error "FAILED: $What (exit code $LASTEXITCODE)"
        exit 1
    }
}

# --- 1. Read the desired image -------------------------------------------
if (-not (Test-Path $ImageFile)) {
    Write-Error "Image file '$ImageFile' not found. Has the deploy workflow run on main yet?"
    exit 1
}

# Take the first non-empty, non-comment line so the file tolerates stray blanks.
$ImageRef = (Get-Content $ImageFile |
    Where-Object { $_.Trim() -ne "" -and -not $_.Trim().StartsWith("#") } |
    Select-Object -First 1)
if ($ImageRef) { $ImageRef = $ImageRef.Trim() }

if ([string]::IsNullOrWhiteSpace($ImageRef)) {
    Write-Error "No image reference found in '$ImageFile'."
    exit 1
}
Write-Host "==> Desired image: $ImageRef" -ForegroundColor Cyan

# --- 2. Split into repository + tag --------------------------------------
# Split on the LAST colon so a registry host:port prefix (if any) is preserved.
$lastColon = $ImageRef.LastIndexOf(":")
if ($lastColon -lt 0) {
    Write-Error "Image reference '$ImageRef' has no tag (expected repository:tag)."
    exit 1
}
$Repository = $ImageRef.Substring(0, $lastColon)
$Tag        = $ImageRef.Substring($lastColon + 1)
Write-Host "    repository = $Repository" -ForegroundColor DarkGray
Write-Host "    tag        = $Tag" -ForegroundColor DarkGray

# --- 3. helm upgrade --install -------------------------------------------
Write-Host "==> helm upgrade --install $Release -> namespace '$Namespace'" -ForegroundColor Cyan
helm upgrade --install $Release $ChartPath `
    -f $ValuesFile `
    --namespace $Namespace --create-namespace `
    --set image.repository=$Repository `
    --set image.tag=$Tag `
    --wait --timeout $Timeout
Assert-LastExit "helm upgrade --install"

# --- 4. Confirm the rollout ----------------------------------------------
Write-Host "==> kubectl rollout status deployment/$Release -n $Namespace" -ForegroundColor Cyan
kubectl rollout status "deployment/$Release" -n $Namespace --timeout=$Timeout
Assert-LastExit "rollout status"

Write-Host "OK: '$ImageRef' is live in namespace '$Namespace'." -ForegroundColor Green
