<#
.SYNOPSIS
    DO-Monitor — Install script for Intune Win32 app deployment.
.DESCRIPTION
    Installs the DO-Monitor collector by:
    1. Copying the collection script to a persistent location
    2. Creating a scheduled task that runs every 6 hours
    The scheduled task runs as SYSTEM and collects DO telemetry.
#>

$ErrorActionPreference = "Stop"

$InstallDir = "$env:ProgramData\DO-Monitor"
$ScriptName = "Detect-DOStatus.ps1"
$TaskName = "DO-Monitor Collector"

# === CREATE INSTALL DIRECTORY ===
if (-not (Test-Path $InstallDir)) {
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
}

# === COPY SCRIPT ===
Copy-Item -Path "$PSScriptRoot\$ScriptName" -Destination "$InstallDir\$ScriptName" -Force

# === CREATE SCHEDULED TASK ===
# Remove existing task if present
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$InstallDir\$ScriptName`""

# Trigger: every 6 hours, starting now
$Trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration ([TimeSpan]::MaxValue)

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest

$Settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable `
    -RestartCount 3 `
    -RestartInterval (New-TimeSpan -Minutes 15) `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 30)

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings -Force | Out-Null

# === WRITE VERSION FILE ===
$Version = Get-Content "$PSScriptRoot\VERSION" -ErrorAction SilentlyContinue
if (-not $Version) { $Version = "1.0.0" }
$Version | Out-File -FilePath "$InstallDir\VERSION" -Encoding utf8 -NoNewline

# === RUN FIRST COLLECTION ===
Start-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue

Write-Host "DO-Monitor installed successfully. Version: $Version"
exit 0
