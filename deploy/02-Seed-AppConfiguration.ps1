<#
.SYNOPSIS
    Step 2 — Seed App Configuration with DO-Monitor settings.
.DESCRIPTION
    Populates Azure App Configuration with all configuration values
    needed by the Function App. Non-secret values only — secrets
    are stored in Key Vault and referenced via KV references.
.EXAMPLE
    .\02-Seed-AppConfiguration.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 2: Seed App Configuration" -ForegroundColor Cyan
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

Write-Host "`n[1/2] Reading deployment outputs..." -ForegroundColor Yellow
$AppConfigName = $Outputs.appConfigName.value
$FunctionAppUrl = $Outputs.functionAppUrl.value
$DCEEndpoint = $Outputs.dceEndpoint.value
$DCRImmutableId = $Outputs.dcrImmutableId.value

Write-Host "  App Config: $AppConfigName" -ForegroundColor Green

# Define configuration key-values
$ConfigEntries = @(
    @{ Key = "DO-Monitor:ServiceBusQueueName";     Value = "do-telemetry";          Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:LogAnalyticsStreamName";   Value = "Custom-DOStatus_CL";    Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:LogAnalyticsDCE";          Value = $DCEEndpoint;            Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:FunctionAppUrl";           Value = $FunctionAppUrl;         Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:BatchSize";                Value = "500";                   Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:MaxRetries";               Value = "3";                     Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:ClientMinFileSizeBytes";   Value = "0";                     Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:CollectionFrequencyHours"; Value = "6";                     Label = "prod"; ContentType = "" }
    @{ Key = "DO-Monitor:Sentinel";                 Value = "1";                     Label = "prod"; ContentType = "" }

    # Certificate Validation — disable by default, enable after configuring CA chains
    @{ Key = "DO-Monitor:CertificateValidation:DisableValidation"; Value = "true";   Label = "prod"; ContentType = "" }

    # CA chain placeholders are NOT seeded here.
    # Use Manage-TrustedCAChains.ps1 to add actual CA chains after deployment.
)

Write-Host "`n[2/2] Writing configuration entries..." -ForegroundColor Yellow

$FailCount = 0
foreach ($Entry in $ConfigEntries) {
    Write-Host "  Setting: $($Entry.Key) = $($Entry.Value)" -ForegroundColor Gray
    az appconfig kv set `
        --name $AppConfigName `
        --key $Entry.Key `
        --value $Entry.Value `
        --label $Entry.Label `
        --yes `
        --output none 2>$null

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "  Failed to set $($Entry.Key)"
        $FailCount++
    }
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " App Configuration seeded successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Total entries: $($ConfigEntries.Count) (failed: $FailCount)" -ForegroundColor White
Write-Host "  App Config:    $AppConfigName" -ForegroundColor White
Write-Host ""
Write-Host "  Next: Use Manage-TrustedCAChains.ps1 to add CA chains for cert validation." -ForegroundColor Yellow
Write-Host ""
