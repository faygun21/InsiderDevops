#Requires -Version 5.1
<#
.SYNOPSIS
    Side-load the locally built Docker image into minikube's Docker daemon.

.DESCRIPTION
    Track B uses no container registry. minikube runs its own Docker daemon
    inside the cluster VM and CANNOT see images in the host's Docker daemon,
    so `helm install` would fail with ErrImagePull / ImagePullBackOff even
    though `docker images` shows the image on the host.

    `minikube image load` copies the host image into the cluster's daemon.
    Combined with the chart's imagePullPolicy: IfNotPresent, the kubelet then
    uses this pre-loaded image instead of trying to pull it from a registry.

    Run this once after every `docker build` (i.e. whenever the image
    content for a given tag changes) and BEFORE `helm upgrade --install`.

.PARAMETER ImageRef
    The local image reference to load. Defaults to insiderdevops:dev.

.EXAMPLE
    .\scripts\load-image.ps1
    .\scripts\load-image.ps1 -ImageRef insiderdevops:dev
#>
[CmdletBinding()]
param(
    [string]$ImageRef = "insiderdevops:dev"
)

$ErrorActionPreference = "Stop"

Write-Host "==> Checking the image exists in the host Docker daemon: $ImageRef" -ForegroundColor Cyan
docker image inspect $ImageRef *> $null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Image '$ImageRef' not found in host Docker. Build it first, e.g.:`n  docker build -t $ImageRef ."
    exit 1
}

Write-Host "==> Loading '$ImageRef' into minikube's Docker daemon (this can take ~20-40s)..." -ForegroundColor Cyan
minikube image load $ImageRef
if ($LASTEXITCODE -ne 0) {
    Write-Error "minikube image load failed. Is minikube running?  Try: minikube status"
    exit 1
}

Write-Host "==> Verifying the image is now visible inside minikube:" -ForegroundColor Cyan
minikube image ls | Select-String -SimpleMatch ($ImageRef.Split(":")[0])

Write-Host "OK: '$ImageRef' is loaded. You can now run helm upgrade --install." -ForegroundColor Green
