<#
.SYNOPSIS
    Imports the DO-Monitor client certificate into LocalMachine\My store.
.DESCRIPTION
    The scheduled task runs as SYSTEM which needs the cert in LocalMachine\My.
    Run this script from an elevated (admin) PowerShell prompt.
.EXAMPLE
    # Run from elevated PowerShell:
    .\Import-ClientCert.ps1 -Thumbprint "4e050adbd50a4132c1cc2b237929e113431993d2"
#>

param(
    [Parameter(Mandatory)]
    [string]$Thumbprint
)

$ErrorActionPreference = "Stop"

# Check if running elevated
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "This script must be run as Administrator. Right-click PowerShell > Run as Administrator."
    exit 1
}

# Check source
$srcCert = Get-ChildItem -Path "Cert:\CurrentUser\My\$Thumbprint" -ErrorAction SilentlyContinue
if (-not $srcCert) {
    Write-Error "Certificate $Thumbprint not found in CurrentUser\My"
    exit 1
}
Write-Host "Source: CurrentUser\My - $($srcCert.Subject)" -ForegroundColor Cyan

# Check if already in LocalMachine
$existing = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
if ($existing) {
    Write-Host "Certificate already in LocalMachine\My. Nothing to do." -ForegroundColor Green
    exit 0
}

# Export and reimport
$pfx = Join-Path $env:TEMP "do-monitor-cert-$([guid]::NewGuid().ToString('N').Substring(0,8)).pfx"
$pwd = ConvertTo-SecureString -String ([guid]::NewGuid().ToString()) -Force -AsPlainText

Export-PfxCertificate -Cert $srcCert -FilePath $pfx -Password $pwd | Out-Null
Import-PfxCertificate -FilePath $pfx -CertStoreLocation "Cert:\LocalMachine\My" -Password $pwd | Out-Null
Remove-Item $pfx -Force

# Verify
$destCert = Get-ChildItem -Path "Cert:\LocalMachine\My\$Thumbprint" -ErrorAction SilentlyContinue
if ($destCert) {
    Write-Host "Certificate imported to LocalMachine\My successfully." -ForegroundColor Green
    Write-Host "  Subject:    $($destCert.Subject)"
    Write-Host "  Thumbprint: $($destCert.Thumbprint)"
    Write-Host "  Expires:    $($destCert.NotAfter)"
} else {
    Write-Error "Import failed."
    exit 1
}
