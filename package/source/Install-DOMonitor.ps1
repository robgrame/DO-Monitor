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

try {
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

    # Trigger: daily, repeating every 6 hours for the full day
    $Trigger = New-ScheduledTaskTrigger -Daily -At "00:00"
    $Trigger.Repetition.Interval = "PT6H"
    $Trigger.Repetition.Duration = "P1D"

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
} catch {
    Write-Host "DO-Monitor installation failed: $($_.Exception.Message)"
    exit 1
}
