<#
.SYNOPSIS
    Builds the DO-Monitor IntuneWin package with embedded scripts.
.DESCRIPTION
    Generates a self-contained Install-DOMonitor.ps1 that embeds the collector
    script as a base64 payload. No external file dependencies at runtime.
    Then packages everything into an .intunewin file.
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

# Step 1: Generate embedded install script
Write-Host "`n[1/3] Generating self-contained scripts..." -ForegroundColor Yellow

$CollectorScript = Get-Content (Join-Path $RepoRoot "scripts\Detect-DOStatus.ps1") -Raw

# Replace placeholders
if ($FunctionUrl) {
    $CollectorScript = $CollectorScript -replace 'https://<YOUR-FUNCTION-APP>\.azurewebsites\.net/api/DOIngest', $FunctionUrl
    Write-Host "  Function URL set: $FunctionUrl" -ForegroundColor Green
}
if ($CertThumbprint) {
    $CollectorScript = $CollectorScript -replace '<YOUR-CLIENT-CERT-THUMBPRINT>', $CertThumbprint
    Write-Host "  Cert thumbprint set: $CertThumbprint" -ForegroundColor Green
}

# Encode collector script as base64
$CollectorBase64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($CollectorScript))

# Version
$Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()

# Generate the self-contained install script
$InstallScript = @"
<#
.SYNOPSIS
    DO-Monitor — Self-contained installer (v$Version).
    All dependent scripts are embedded. No external files required.
#>
`$ErrorActionPreference = "Stop"
`$InstallDir = "`$env:ProgramData\DO-Monitor"
`$TaskName = "DO-Monitor Collector"
`$Version = "$Version"

# === EMBEDDED COLLECTOR SCRIPT (base64) ===
`$CollectorBase64 = "$CollectorBase64"

try {
    # === CREATE INSTALL DIRECTORY ===
    if (-not (Test-Path `$InstallDir)) {
        New-Item -ItemType Directory -Path `$InstallDir -Force | Out-Null
    }

    # === EXTRACT EMBEDDED COLLECTOR SCRIPT ===
    `$CollectorBytes = [Convert]::FromBase64String(`$CollectorBase64)
    [System.IO.File]::WriteAllBytes("`$InstallDir\Detect-DOStatus.ps1", `$CollectorBytes)

    # === WRITE VERSION FILE ===
    `$Version | Out-File -FilePath "`$InstallDir\VERSION" -Encoding utf8 -NoNewline

    # === CREATE SCHEDULED TASK ===
    Unregister-ScheduledTask -TaskName `$TaskName -Confirm:`$false -ErrorAction SilentlyContinue

    `$Action = New-ScheduledTaskAction -Execute "powershell.exe" ``
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"`$InstallDir\Detect-DOStatus.ps1`""

    `$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).Date -RepetitionInterval (New-TimeSpan -Hours 6)

    `$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

    `$Settings = New-ScheduledTaskSettingsSet ``
        -AllowStartIfOnBatteries ``
        -DontStopIfGoingOnBatteries ``
        -StartWhenAvailable ``
        -RunOnlyIfNetworkAvailable ``
        -RestartCount 3 ``
        -RestartInterval (New-TimeSpan -Minutes 15) ``
        -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

    Register-ScheduledTask -TaskName `$TaskName -Action `$Action -Trigger `$Trigger ``
        -Principal `$Principal -Settings `$Settings -Force | Out-Null

    # === RUN FIRST COLLECTION ===
    Start-ScheduledTask -TaskName `$TaskName -ErrorAction SilentlyContinue

    Write-Host "DO-Monitor v`$Version installed successfully."
    exit 0
} catch {
    Write-Host "DO-Monitor installation failed: `$(`$_.Exception.Message)"
    exit 1
}
"@

# Generate the self-contained uninstall script
$UninstallScript = @"
<#
.SYNOPSIS
    DO-Monitor — Uninstaller (v$Version).
#>
`$ErrorActionPreference = "SilentlyContinue"
`$InstallDir = "`$env:ProgramData\DO-Monitor"
`$TaskName = "DO-Monitor Collector"

Unregister-ScheduledTask -TaskName `$TaskName -Confirm:`$false -ErrorAction SilentlyContinue
if (Test-Path `$InstallDir) { Remove-Item -Path `$InstallDir -Recurse -Force }

Write-Host "DO-Monitor uninstalled successfully."
exit 0
"@

# Generate the detection script
$DetectionScript = @"
<#
.SYNOPSIS
    DO-Monitor — Detection script for Intune Win32 app (v$Version).
#>
`$InstallDir = "`$env:ProgramData\DO-Monitor"
`$TaskName = "DO-Monitor Collector"
`$RequiredVersion = "$Version"

if (-not (Test-Path "`$InstallDir\Detect-DOStatus.ps1")) { Write-Host "Not installed"; exit 1 }

`$InstalledVersion = Get-Content "`$InstallDir\VERSION" -ErrorAction SilentlyContinue
if (`$InstalledVersion -ne `$RequiredVersion) { Write-Host "Version mismatch: `$InstalledVersion vs `$RequiredVersion"; exit 1 }

`$Task = Get-ScheduledTask -TaskName `$TaskName -ErrorAction SilentlyContinue
if (-not `$Task) { Write-Host "Scheduled task missing"; exit 1 }

Write-Host "DO-Monitor v`$InstalledVersion detected"
exit 0
"@

# Write all scripts to source dir
$InstallScript | Out-File -FilePath (Join-Path $SourceDir "Install-DOMonitor.ps1") -Encoding utf8 -Force
$UninstallScript | Out-File -FilePath (Join-Path $SourceDir "Uninstall-DOMonitor.ps1") -Encoding utf8 -Force
$DetectionScript | Out-File -FilePath (Join-Path $SourceDir "Detect-DOMonitor.ps1") -Encoding utf8 -Force
$Version | Out-File -FilePath (Join-Path $SourceDir "VERSION") -Encoding utf8 -NoNewline

# Remove the standalone collector from source (it's embedded now)
Remove-Item -Path (Join-Path $SourceDir "Detect-DOStatus.ps1") -Force -ErrorAction SilentlyContinue

Write-Host "  Version: $Version" -ForegroundColor White
Write-Host "  Install script: self-contained with embedded collector" -ForegroundColor Green
Write-Host "  Source files:" -ForegroundColor Gray
Get-ChildItem $SourceDir | ForEach-Object { Write-Host "    $($_.Name) ($([math]::Round($_.Length/1KB,1)) KB)" -ForegroundColor Gray }

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
$FileSizeMB = [math]::Round($IntuneWinFile.Length / 1MB, 2)
Write-Host "  Package created: $($IntuneWinFile.Name) ($FileSizeMB MB)" -ForegroundColor Green

# Step 3: Summary
Write-Host "`n[3/3] Intune Win32 App Configuration" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Package ready! (self-contained)" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  File: $($IntuneWinFile.FullName)" -ForegroundColor White
Write-Host "  Size: $FileSizeMB MB" -ForegroundColor White
Write-Host "  Version: $Version" -ForegroundColor White
Write-Host ""
Write-Host "  Install command:" -ForegroundColor Cyan
Write-Host "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DOMonitor.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Uninstall command:" -ForegroundColor Cyan
Write-Host "    powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DOMonitor.ps1" -ForegroundColor White
Write-Host ""
Write-Host "  Detection: Custom script (Detect-DOMonitor.ps1)" -ForegroundColor Cyan
Write-Host "  Install behavior: System | Restart: No action" -ForegroundColor White
Write-Host ""
