<#
.SYNOPSIS
    DO-Monitor — Detection script for Intune Win32 app (v2.5.0).
#>
$InstallDir = "$env:ProgramData\DO-Monitor"
$TaskName = "DO-Monitor Collector"
$RequiredVersion = "2.5.0"

if (-not (Test-Path "$InstallDir\Detect-DOStatus.ps1")) { Write-Host "Not installed"; exit 1 }

$InstalledVersion = Get-Content "$InstallDir\VERSION" -ErrorAction SilentlyContinue
if ($InstalledVersion -ne $RequiredVersion) { Write-Host "Version mismatch: $InstalledVersion vs $RequiredVersion"; exit 1 }

$Task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if (-not $Task) { Write-Host "Scheduled task missing"; exit 1 }

Write-Host "DO-Monitor v$InstalledVersion detected"
exit 0
