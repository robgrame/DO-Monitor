<#
.SYNOPSIS
    Step 5 — Generate the client detection script with actual Function URL.
.DESCRIPTION
    Reads the deployment outputs, retrieves the Function App host key from
    Key Vault, and generates a ready-to-deploy Intune detection script
    with the correct Function URL and key.
.EXAMPLE
    .\05-Generate-ClientScript.ps1
#>

[CmdletBinding()]
param()

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
Write-Host "`n[1/3] Function URL: $FunctionUrl" -ForegroundColor Yellow

# Get Function key from Key Vault
Write-Host "`n[2/3] Retrieving Function host key from Key Vault..." -ForegroundColor Yellow
$KeyVaultName = $Outputs.keyVaultName.value
$FunctionKey = az keyvault secret show `
    --vault-name $KeyVaultName `
    --name "FunctionAppHostKey" `
    --query "value" -o tsv

if (-not $FunctionKey) {
    Write-Warning "Could not retrieve Function key from Key Vault."
    Write-Warning "Retrieving directly from Function App..."
    $FunctionAppName = $Outputs.functionAppName.value
    $FunctionKey = az functionapp keys list `
        --resource-group $Config.ResourceGroupName `
        --name $FunctionAppName `
        --query "functionKeys.default" -o tsv
}

$FullUrl = "${FunctionUrl}?code=${FunctionKey}"

# Generate the client script
Write-Host "`n[3/3] Generating client detection script..." -ForegroundColor Yellow

$ScriptTemplate = Get-Content (Join-Path $Config.ScriptsPath "Detect-DOStatus.ps1") -Raw
$GeneratedScript = $ScriptTemplate -replace 'https://<YOUR-FUNCTION-APP>\.azurewebsites\.net/api/DOIngest\?code=<YOUR-FUNCTION-KEY>', $FullUrl

$OutputScript = Join-Path $PSScriptRoot "Detect-DOStatus-READY.ps1"
$GeneratedScript | Out-File -FilePath $OutputScript -Encoding utf8

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Client script generated successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Output: $OutputScript" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  1. Upload '$OutputScript' to Intune" -ForegroundColor White
Write-Host "     Devices > Remediations > Create" -ForegroundColor Gray
Write-Host "  2. Set as Detection Script (no Remediation script)" -ForegroundColor White
Write-Host "  3. Run in 64-bit PowerShell: Yes" -ForegroundColor White
Write-Host "  4. Run as logged-on user: No (run as SYSTEM)" -ForegroundColor White
Write-Host "  5. Schedule: Every 6 hours" -ForegroundColor White
Write-Host "  6. Assign to device group (all managed devices)" -ForegroundColor White
Write-Host ""
