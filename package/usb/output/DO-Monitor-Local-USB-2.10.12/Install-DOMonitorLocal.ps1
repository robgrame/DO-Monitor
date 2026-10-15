#requires -Version 5.1
<#
.SYNOPSIS
    Installs the offline DO collector and a five-minute SYSTEM task. Version: 2.8.6.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$Version = '2.10.12'
$TaskName = 'DO-Monitor Local Collector'
$InstallDir = Join-Path $env:ProgramFiles 'DO-Monitor-Local'
$DataDir = Join-Path $env:ProgramData 'DO-Monitor-Local'
$InstallLock = $null
$DataLock = $null

try {
    Import-Module (Join-Path $PSScriptRoot 'LocalPackage.psm1') -ErrorAction Stop
    Assert-DOLocalPackageHost
    $InstallLock = Open-DOLocalPackageDirectory -Path $InstallDir -Create
    $DataLock = Open-DOLocalPackageDirectory -Path $DataDir -Create
    Write-Output "Installing DO-Monitor Local v$Version; scripts: $InstallDir; snapshots: $DataDir"
    $null = Stop-DOLocalPackageTask
    $CollectorPath = Join-Path $InstallDir 'Collect-DOStatusLocal.ps1'
    foreach ($Name in @('Collect-DOStatusLocal.ps1', 'VERSION')) {
        $Target = Join-Path $InstallDir $Name
        if (Test-Path -LiteralPath $Target) {
            $Item = Get-Item -LiteralPath $Target -Force
            if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing unsafe installed file: $Target"
            }
            # Unlink rather than overwrite an existing file that might be a hard link.
            Remove-Item -LiteralPath $Target -Force
        }
    }
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'Collect-DOStatusLocal.ps1') -Destination $CollectorPath
    [IO.File]::WriteAllText((Join-Path $InstallDir 'VERSION'), $Version, [Text.UTF8Encoding]::new($false))
    $Action = New-ScheduledTaskAction `
        -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$CollectorPath`""
    $Trigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).Date
    $Repeating = New-ScheduledTaskTrigger -Once -At (Get-Date).Date `
        -RepetitionInterval (New-TimeSpan -Minutes 5) -RepetitionDuration (New-TimeSpan -Days 1)
    $Trigger.Repetition = $Repeating.Repetition
    $Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' -LogonType ServiceAccount -RunLevel Highest
    $Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew `
        -ExecutionTimeLimit (New-TimeSpan -Minutes 4)
    Register-ScheduledTask -TaskName $TaskName -TaskPath '\' -Action $Action -Trigger $Trigger `
        -Principal $Principal -Settings $Settings -Description "DO-Monitor Local v$Version; every 5 minutes; local JSON only" `
        -Force | Out-Null
    $Detection = & (Join-Path $PSScriptRoot 'Detect-DOMonitorLocal.ps1')
    if ($LASTEXITCODE -ne 0) { throw "Post-install detection failed: $Detection" }
    Write-Output $Detection
    Start-ScheduledTask -TaskName $TaskName -TaskPath '\'
    Write-Output "Installed v$Version; task: \$TaskName; interval: PT5M; account: SYSTEM; first run requested; no restart required."
    exit 0
} catch {
    Write-Output "DO-Monitor Local installation failed: $($_.Exception.Message)"
    exit 1
} finally {
    if (Get-Command Close-DOLocalPackageDirectory -ErrorAction SilentlyContinue) {
        Close-DOLocalPackageDirectory $DataLock
        Close-DOLocalPackageDirectory $InstallLock
    }
}
