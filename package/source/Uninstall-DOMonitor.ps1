<#
.SYNOPSIS
    DO-Monitor — Uninstaller (v2.5.0).
#>
$ErrorActionPreference = "SilentlyContinue"
$InstallDir = "$env:ProgramData\DO-Monitor"
$TaskName = "DO-Monitor Collector"

Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
if (Test-Path $InstallDir) { Remove-Item -Path $InstallDir -Recurse -Force }

Write-Host "DO-Monitor uninstalled successfully."
exit 0
