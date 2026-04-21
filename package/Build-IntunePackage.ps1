<#
.SYNOPSIS
    Builds the DO-Monitor IntuneWin package.
.DESCRIPTION
    Copies the collection script into the package source folder,
    then runs IntuneWinAppUtil to create the .intunewin package.
.EXAMPLE
    .\Build-IntunePackage.ps1
    .\Build-IntunePackage.ps1 -CertThumbprint "A1B2C3..."
#>

[CmdletBinding()]
param(
    [string]$CertThumbprint,
    [string]$FunctionUrl
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot | Split-Path
$SourceDir = Join-Path $RepoRoot "package\source"
$OutputDir = Join-Path $RepoRoot "package\output"
$ToolPath = Join-Path $RepoRoot "deploy\tools\Microsoft-Win32-Content-Prep-Tool-1.8.6\IntuneWinAppUtil.exe"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Build IntuneWin Package" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Load deployment outputs for FunctionUrl if not provided
if (-not $FunctionUrl) {
    $OutputsFile = Join-Path $RepoRoot "deploy\deployment-outputs.json"
    if (Test-Path $OutputsFile) {
        $Outputs = Get-Content $OutputsFile -Raw | ConvertFrom-Json
        $FunctionUrl = $Outputs.functionAppUrl.value
        Write-Host "  Function URL from outputs: $FunctionUrl" -ForegroundColor Gray
    }
}

# Step 1: Copy collection script
Write-Host "`n[1/3] Preparing source files..." -ForegroundColor Yellow

$CollectorScript = Join-Path $RepoRoot "scripts\Detect-DOStatus.ps1"
$TargetScript = Join-Path $SourceDir "Detect-DOStatus.ps1"

$ScriptContent = Get-Content $CollectorScript -Raw

# Replace placeholders if values provided
if ($FunctionUrl) {
    $ScriptContent = $ScriptContent -replace 'https://<YOUR-FUNCTION-APP>\.azurewebsites\.net/api/DOIngest', $FunctionUrl
    Write-Host "  Function URL set: $FunctionUrl" -ForegroundColor Green
}
if ($CertThumbprint) {
    $ScriptContent = $ScriptContent -replace '<YOUR-CLIENT-CERT-THUMBPRINT>', $CertThumbprint
    Write-Host "  Cert thumbprint set: $CertThumbprint" -ForegroundColor Green
}

$ScriptContent | Out-File -FilePath $TargetScript -Encoding utf8 -Force

# Copy VERSION
$VersionFile = Join-Path $RepoRoot "VERSION"
Copy-Item -Path $VersionFile -Destination (Join-Path $SourceDir "VERSION") -Force
$Version = (Get-Content $VersionFile -Raw).Trim()
Write-Host "  Version: $Version" -ForegroundColor White

Write-Host "  Source files:" -ForegroundColor Gray
Get-ChildItem $SourceDir | ForEach-Object { Write-Host "    $($_.Name)" -ForegroundColor Gray }

# Step 2: Build IntuneWin
Write-Host "`n[2/3] Building .intunewin package..." -ForegroundColor Yellow

if (-not (Test-Path $ToolPath)) {
    Write-Error "IntuneWinAppUtil.exe not found at: $ToolPath"
    exit 1
}

if (Test-Path $OutputDir) { Remove-Item $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null

& $ToolPath -c $SourceDir -s "Install-DOMonitor.ps1" -o $OutputDir -q

if ($LASTEXITCODE -ne 0) {
    Write-Error "IntuneWinAppUtil failed!"
    exit 1
}

$IntuneWinFile = Get-ChildItem $OutputDir -Filter "*.intunewin" | Select-Object -First 1
if (-not $IntuneWinFile) {
    Write-Error "No .intunewin file generated!"
    exit 1
}

$FileSizeMB = [math]::Round($IntuneWinFile.Length / 1MB, 2)
Write-Host "  Package created: $($IntuneWinFile.Name) ($FileSizeMB MB)" -ForegroundColor Green

# Step 3: Summary
Write-Host "`n[3/3] Intune Win32 App Configuration" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Package ready!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  File: $($IntuneWinFile.FullName)" -ForegroundColor White
Write-Host "  Size: $FileSizeMB MB" -ForegroundColor White
Write-Host "  Version: $Version" -ForegroundColor White
Write-Host ""
Write-Host "  Intune Win32 App settings:" -ForegroundColor Yellow
Write-Host "  ─────────────────────────────────────────" -ForegroundColor DarkGray
Write-Host "  Name:              DO-Monitor Collector" -ForegroundColor White
Write-Host "  Version:           $Version" -ForegroundColor White
Write-Host "  Publisher:         IT Operations" -ForegroundColor White
Write-Host ""
Write-Host "  Install command:" -ForegroundColor Cyan
Write-Host "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DOMonitor.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Uninstall command:" -ForegroundColor Cyan
Write-Host "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DOMonitor.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Detection rule:" -ForegroundColor Cyan
Write-Host "    Type:            Custom detection script" -ForegroundColor White
Write-Host "    Script:          Detect-DOMonitor.ps1" -ForegroundColor White
Write-Host "    Run as 64-bit:   Yes" -ForegroundColor White
Write-Host "    Run as:          SYSTEM" -ForegroundColor White
Write-Host ""
Write-Host "  Requirements:" -ForegroundColor Cyan
Write-Host "    OS:              Windows 10 21H2+" -ForegroundColor White
Write-Host "    Architecture:    64-bit" -ForegroundColor White
Write-Host "    Disk space:      1 MB" -ForegroundColor White
Write-Host ""
Write-Host "  Install behavior:  System" -ForegroundColor White
Write-Host "  Restart behavior:  No action" -ForegroundColor White
Write-Host ""
