<#
.SYNOPSIS
    DO-Monitor — Detection script for Intune Win32 app.
.DESCRIPTION
    Checks if DO-Monitor is installed and at the correct version.
    Returns exit 0 if installed (detected), exit 1 if not (triggers install).
#>

$InstallDir = "$env:ProgramData\DO-Monitor"
$TaskName = "DO-Monitor Collector"
$RequiredVersion = Get-Content "$PSScriptRoot\VERSION" -ErrorAction SilentlyContinue
if (-not $RequiredVersion) { $RequiredVersion = "1.0.0" }

# Check install directory exists
if (-not (Test-Path "$InstallDir\Detect-DOStatus.ps1")) {
    Write-Host "Not installed"
    exit 1
}

# Check version
$InstalledVersion = Get-Content "$InstallDir\VERSION" -ErrorAction SilentlyContinue
if ($InstalledVersion -ne $RequiredVersion) {
    Write-Host "Version mismatch: installed=$InstalledVersion required=$RequiredVersion"
    exit 1
}

# Check scheduled task exists
$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $Task) {
    Write-Host "Scheduled task missing"
    exit 1
}

Write-Host "DO-Monitor v$InstalledVersion detected"
exit 0
