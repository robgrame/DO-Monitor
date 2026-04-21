<#
.SYNOPSIS
    DO-Monitor — Uninstall script for Intune Win32 app.
.DESCRIPTION
    Removes the DO-Monitor collector:
    1. Removes the scheduled task
    2. Deletes the install directory
#>

$ErrorActionPreference = "SilentlyContinue"

$InstallDir = "$env:ProgramData\DO-Monitor"
$TaskName = "DO-Monitor Collector"

# === REMOVE SCHEDULED TASK ===
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

# === REMOVE INSTALL DIRECTORY ===
if (Test-Path $InstallDir) {
    Remove-Item -Path $InstallDir -Recurse -Force
}

Write-Host "DO-Monitor uninstalled successfully."
exit 0
