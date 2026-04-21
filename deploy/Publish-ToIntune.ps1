<#
.SYNOPSIS
    DO-Monitor — Publish Win32 app to Intune and assign to All Devices.
.DESCRIPTION
    Connects to Microsoft Graph, creates the Win32 app in Intune,
    uploads the .intunewin package, configures detection/install/uninstall,
    and assigns to All Devices as Required.
.EXAMPLE
    .\Publish-ToIntune.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot | Split-Path
$PackagePath = Join-Path $RepoRoot "package\output\Install-DOMonitor.intunewin"
$DetectionScript = Join-Path $RepoRoot "package\source\Detect-DOMonitor.ps1"
$Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
$TenantId = "3ce9df6b-61dd-472e-a028-528aee6b48de"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Publish to Intune" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Version: $Version" -ForegroundColor White
Write-Host "  Package: $PackagePath" -ForegroundColor Gray

# ---- Verify package exists ----
if (-not (Test-Path $PackagePath)) {
    Write-Error "Package not found. Run .\package\Build-IntunePackage.ps1 first."
    exit 1
}

# ---- Connect to Graph ----
Write-Host "`n[1/4] Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All,Group.Read.All" -TenantId $TenantId -UseDeviceCode -NoWelcome
$ctx = Get-MgContext
if (-not $ctx.Account) {
    Write-Error "Graph authentication failed."
    exit 1
}
Write-Host "  Connected as: $($ctx.Account)" -ForegroundColor Green

# ---- Create Win32 App ----
Write-Host "`n[2/4] Creating Win32 app in Intune..." -ForegroundColor Yellow

Import-Module IntuneWin32App -Force

# Detection rule: custom script
$DetectionRule = New-IntuneWin32AppDetectionRuleScript `
    -ScriptFile $DetectionScript `
    -EnforceSignatureCheck $false `
    -RunAs32Bit $false

# Requirement rule
$RequirementRule = New-IntuneWin32AppRequirementRule `
    -Architecture "x64" `
    -MinimumSupportedWindowsRelease "W10_21H2"

# Create the app
$App = Add-IntuneWin32App `
    -FilePath $PackagePath `
    -DisplayName "DO-Monitor Collector" `
    -Description "Delivery Optimization telemetry collector. Collects DO job details, performance stats, and applied policies from Windows clients and sends to Azure Log Analytics via Azure Functions. v$Version" `
    -Publisher "IT Operations" `
    -AppVersion $Version `
    -InstallCommandLine "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DOMonitor.ps1" `
    -UninstallCommandLine "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DOMonitor.ps1" `
    -InstallExperience "system" `
    -RestartBehavior "suppress" `
    -DetectionRule $DetectionRule `
    -RequirementRule $RequirementRule `
    -Verbose

if (-not $App) {
    Write-Error "Failed to create Win32 app in Intune."
    exit 1
}

Write-Host "  App created: $($App.displayName) (ID: $($App.id))" -ForegroundColor Green

# ---- Assign to All Devices ----
Write-Host "`n[3/4] Assigning to All Devices (Required)..." -ForegroundColor Yellow

Add-IntuneWin32AppAssignmentAllDevices `
    -ID $App.id `
    -Intent "required" `
    -Notification "hideAll" `
    -Verbose

Write-Host "  Assigned to All Devices as Required." -ForegroundColor Green

# ---- Summary ----
Write-Host "`n[4/4] Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Published to Intune successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App Name:     DO-Monitor Collector" -ForegroundColor White
Write-Host "  App ID:       $($App.id)" -ForegroundColor White
Write-Host "  Version:      $Version" -ForegroundColor White
Write-Host "  Assignment:   All Devices (Required)" -ForegroundColor White
Write-Host "  Notification: Hidden" -ForegroundColor White
Write-Host ""
Write-Host "  The app will start deploying to devices at the next Intune sync." -ForegroundColor Yellow
Write-Host ""

# Save app ID for reference
$App.id | Out-File -FilePath (Join-Path $PSScriptRoot "intune-app-id.txt") -Encoding utf8
