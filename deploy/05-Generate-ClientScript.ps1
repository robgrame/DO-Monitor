<#
.SYNOPSIS
    Step 5 — Generate the client detection script with actual Function URL and cert thumbprint.
.DESCRIPTION
    Reads the deployment outputs and generates a ready-to-deploy Intune detection script
    with the correct Function URL. The client certificate thumbprint must be provided
    as the certificate is deployed to clients via Intune certificate profile.
.EXAMPLE
    .\05-Generate-ClientScript.ps1 -CertThumbprint "A1B2C3D4E5F6..."
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$CertThumbprint
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 5: Generate Client Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Load configuration
$Config = & "$PSScriptRoot\Config.ps1"

# Load deployment outputs
$OutputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
if (-not (Test-Path $OutputsFile)) {
    Write-Error "Deployment outputs not found. Run 01-Deploy-Infrastructure.ps1 first."
    exit 1
}
$Outputs = Get-Content $OutputsFile -Raw | ConvertFrom-Json

# Get Function App URL
$FunctionUrl = $Outputs.functionAppUrl.value
Write-Host "`n[1/2] Function URL: $FunctionUrl" -ForegroundColor Yellow
Write-Host "  Cert Thumbprint: $CertThumbprint" -ForegroundColor Yellow

# Generate the client script
Write-Host "`n[2/2] Generating client detection script..." -ForegroundColor Yellow

$ScriptTemplate = Get-Content (Join-Path $Config.ScriptsPath "Detect-DOStatus.ps1") -Raw
$GeneratedScript = $ScriptTemplate -replace 'https://<YOUR-FUNCTION-APP>\.azurewebsites\.net/api/DOIngest', $FunctionUrl
$GeneratedScript = $GeneratedScript -replace '<YOUR-CLIENT-CERT-THUMBPRINT>', $CertThumbprint

$OutputScript = Join-Path $PSScriptRoot "Detect-DOStatus-READY.ps1"
$GeneratedScript | Out-File -FilePath $OutputScript -Encoding utf8

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Client script generated successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output: $OutputScript" -ForegroundColor White
Write-Host ""
Write-Host "  Prerequisites (on each client):" -ForegroundColor Yellow
Write-Host "  - Client certificate with thumbprint '$CertThumbprint'" -ForegroundColor White
Write-Host "    must be installed in Cert:\LocalMachine\My" -ForegroundColor Gray
Write-Host "  - Deploy via Intune PKCS or SCEP certificate profile" -ForegroundColor Gray
Write-Host ""
Write-Host "  Intune Remediation settings:" -ForegroundColor Yellow
Write-Host "  1. Upload '$OutputScript' as Detection Script" -ForegroundColor White
Write-Host "  2. No Remediation script needed" -ForegroundColor White
Write-Host "  3. Run in 64-bit PowerShell: Yes" -ForegroundColor White
Write-Host "  4. Run as: SYSTEM (required for LocalMachine cert store)" -ForegroundColor White
Write-Host "  5. Schedule: Every 6 hours" -ForegroundColor White
Write-Host "  6. Assign to target device group" -ForegroundColor White
Write-Host ""
