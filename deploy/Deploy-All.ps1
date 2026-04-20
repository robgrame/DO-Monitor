<#
.SYNOPSIS
    DO-Monitor — Full deployment orchestrator.
.DESCRIPTION
    Runs all deployment steps in sequence:
    1. Deploy Azure infrastructure (Bicep)
    2. Seed App Configuration
    3. Build & Publish Azure Functions
    4. Deploy Workbook & Alert Rules
    5. Generate client detection script
    6. Validate deployment
.EXAMPLE
    .\Deploy-All.ps1
    .\Deploy-All.ps1 -SkipValidation
    .\Deploy-All.ps1 -StopOnError
#>

[CmdletBinding()]
param(
    [switch]$SkipValidation,
    [switch]$StopOnError,
    [switch]$WhatIf
)

$ErrorActionPreference = if ($StopOnError) { "Stop" } else { "Continue" }
Set-StrictMode -Version Latest

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     DO-Monitor — Full Deployment Orchestrator        ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Step 1: Deploy Infrastructure (Bicep)               ║" -ForegroundColor White
Write-Host "║  Step 2: Seed App Configuration                      ║" -ForegroundColor White
Write-Host "║  Step 3: Build & Publish Functions                   ║" -ForegroundColor White
Write-Host "║  Step 4: Deploy Monitoring (Workbook + Alerts)       ║" -ForegroundColor White
Write-Host "║  Step 5: Generate Client Script                      ║" -ForegroundColor White
Write-Host "║  Step 6: Validate Deployment                         ║" -ForegroundColor White
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$StartTime = Get-Date

function Run-Step {
    param([string]$StepNumber, [string]$Description, [string]$Script, [hashtable]$Params = @{})

    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray
    Write-Host " Step $StepNumber — $Description" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor DarkGray

    $StepStart = Get-Date
    try {
        & (Join-Path $PSScriptRoot $Script) @Params

        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Script exited with code $LASTEXITCODE"
        }

        $Duration = (Get-Date) - $StepStart
        Write-Host "  ✓ Completed in $([math]::Round($Duration.TotalSeconds, 1))s" -ForegroundColor Green
        return $true
    } catch {
        $Duration = (Get-Date) - $StepStart
        Write-Host "  ✗ Failed after $([math]::Round($Duration.TotalSeconds, 1))s: $($_.Exception.Message)" -ForegroundColor Red
        if ($StopOnError) { throw }
        return $false
    }
}

# ---- Execute Steps ----
$Results = @{}

if ($WhatIf) {
    Write-Host "`n  Running in WhatIf mode — only Step 1 will execute (with what-if)." -ForegroundColor Yellow
    $Results["Step 1"] = Run-Step "1" "Deploy Infrastructure" "01-Deploy-Infrastructure.ps1" @{ WhatIf = $true }
} else {
    $Results["Step 1"] = Run-Step "1" "Deploy Infrastructure" "01-Deploy-Infrastructure.ps1"
    $Results["Step 2"] = Run-Step "2" "Seed App Configuration" "02-Seed-AppConfiguration.ps1"
    $Results["Step 3"] = Run-Step "3" "Build & Publish Functions" "03-Build-And-Publish-Functions.ps1"
    $Results["Step 4"] = Run-Step "4" "Deploy Monitoring" "04-Deploy-Monitoring.ps1"
    $Results["Step 5"] = Run-Step "5" "Generate Client Script" "05-Generate-ClientScript.ps1"

    if (-not $SkipValidation) {
        $Results["Step 6"] = Run-Step "6" "Validate Deployment" "06-Validate-Deployment.ps1"
    }
}

# ---- Summary ----
$TotalDuration = (Get-Date) - $StartTime
$PassedSteps = ($Results.Values | Where-Object { $_ -eq $true }).Count
$FailedSteps = ($Results.Values | Where-Object { $_ -eq $false }).Count

Write-Host "`n╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║               DEPLOYMENT SUMMARY                     ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan

foreach ($Key in $Results.Keys | Sort-Object) {
    $Status = if ($Results[$Key]) { "✓ PASS" } else { "✗ FAIL" }
    $Color = if ($Results[$Key]) { "Green" } else { "Red" }
    Write-Host "║  $Key : $Status" -ForegroundColor $Color
}

Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Total time: $([math]::Round($TotalDuration.TotalMinutes, 1)) minutes" -ForegroundColor White
Write-Host "║  Passed: $PassedSteps | Failed: $FailedSteps" -ForegroundColor $(if ($FailedSteps -gt 0) { "Red" } else { "Green" })
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan

if ($FailedSteps -eq 0 -and -not $WhatIf) {
    Write-Host ""
    Write-Host "  🎉 Deployment complete! Next steps:" -ForegroundColor Green
    Write-Host ""
    Write-Host "  1. Configure Action Group email/Teams in Azure Portal" -ForegroundColor White
    Write-Host "  2. Upload the generated client script to Intune:" -ForegroundColor White
    Write-Host "     $(Join-Path $PSScriptRoot 'Detect-DOStatus-READY.ps1')" -ForegroundColor Gray
    Write-Host "  3. Create Proactive Remediation in Intune (every 6 hours)" -ForegroundColor White
    Write-Host "  4. Assign to device group" -ForegroundColor White
    Write-Host ""
}
