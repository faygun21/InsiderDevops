#Requires -Version 5.1
<#
.SYNOPSIS
    Publish the in-cluster insiderdevops Service on a public ngrok URL.

.DESCRIPTION
    Two hops, because the Service is ClusterIP (not reachable from outside the
    cluster) and minikube runs inside Docker:

      1. `kubectl port-forward` bridges localhost:8080 -> Service:80 in the dev
         namespace. It is started as a background job so this script can move on
         and own the foreground for ngrok.
      2. `ngrok http 8080` opens a public HTTPS tunnel to that local port and
         prints a Forwarding URL.

    ngrok is preferred over `minikube tunnel` for the public URL on Windows: no
    Administrator elevation, no edits to C:\Windows\System32\drivers\etc\hosts,
    and it yields a real internet-reachable HTTPS address (see docs/adr/003).

    When you stop ngrok (Ctrl+C), the script tears the port-forward job down so
    no orphaned kubectl process is left running.

.EXAMPLE
    .\scripts\expose-service.ps1

    # Copy the Forwarding URL from ngrok output, then curl <url>/ping to verify
    # the public endpoint, e.g.:
    #   curl https://<random>.ngrok-free.app/ping   ->  {"status":"pong"}
#>
[CmdletBinding()]
param(
    [string]$Namespace = "dev",
    [string]$Service   = "insiderdevops",
    [int]$LocalPort    = 8080,
    [int]$ServicePort  = 80
)

$ErrorActionPreference = "Stop"

Write-Host "==> Starting kubectl port-forward $LocalPort -> $Service`:$ServicePort (ns: $Namespace) in the background..." -ForegroundColor Cyan
$pf = Start-Job -ScriptBlock {
    param($ns, $svc, $local, $remote)
    kubectl port-forward -n $ns "svc/$svc" "${local}:${remote}"
} -ArgumentList $Namespace, $Service, $LocalPort, $ServicePort

# Give the port-forward a moment to bind the local port before ngrok attaches.
Start-Sleep -Seconds 3

if ($pf.State -eq "Failed") {
    Write-Error "port-forward job failed to start. Is the Service '$Service' deployed in namespace '$Namespace'?"
    Receive-Job $pf
    Remove-Job $pf -Force
    exit 1
}

Write-Host "==> port-forward is up (job id $($pf.Id)). Starting ngrok on port $LocalPort..." -ForegroundColor Green
Write-Host "    Copy the 'Forwarding' URL below, then verify with:  curl <url>/ping" -ForegroundColor Gray

try {
    # ngrok runs in the foreground; Ctrl+C ends it and falls through to cleanup.
    ngrok http $LocalPort
}
finally {
    Write-Host ""
    Write-Host "==> Stopping the port-forward background job..." -ForegroundColor Cyan
    Stop-Job $pf -ErrorAction SilentlyContinue
    Remove-Job $pf -Force -ErrorAction SilentlyContinue
    Write-Host "Done." -ForegroundColor Green
}
