#requires -Version 5.1
<#
.SYNOPSIS
    Standalone Intune Win32 detection for local collector package. Version: 2.8.6.
    Upload the generated copy from package\output\local\<version>, not this template.
#>
$ErrorActionPreference = 'Stop'
$RequiredVersion = '2.8.6'
$ExpectedCollectorHash = '814756250ECE1B8812EE6CA4EE9056846360B8D5D3D6E26C65310016BFCF74F1'
$InstallDir = Join-Path $env:ProgramFiles 'DO-Monitor-Local'
$CollectorPath = Join-Path $InstallDir 'Collect-DOStatusLocal.ps1'
$TaskName = 'DO-Monitor Local Collector'

try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) { throw '64-bit Windows PowerShell required.' }
    foreach ($Path in @($InstallDir, $CollectorPath, (Join-Path $InstallDir 'VERSION'))) {
        $Item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Reparse point: $Path" }
        $Acl = Get-Acl -LiteralPath $Path
        if ($Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin @('S-1-5-18', 'S-1-5-32-544')) {
            throw "Untrusted owner: $Path"
        }
        foreach ($Rule in $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($Rule.AccessControlType -eq 'Allow' -and
                $Rule.IdentityReference.Value -notin @('S-1-5-18', 'S-1-5-32-544')) {
                throw "Unexpected access principal: $Path"
            }
        }
    }
    if ((Get-Content -LiteralPath (Join-Path $InstallDir 'VERSION') -Raw).Trim() -ne $RequiredVersion) {
        throw 'Installed package version does not match.'
    }
    if ((Get-FileHash -LiteralPath $CollectorPath -Algorithm SHA256).Hash -ne $ExpectedCollectorHash) {
        throw 'Collector hash does not match the packaged script.'
    }
    $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction Stop
    $ExpectedArguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$CollectorPath`""
    if (@($Task.Actions).Count -ne 1 -or
        $Task.Actions[0].Execute -ne "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -or
        $Task.Actions[0].Arguments -ne $ExpectedArguments) { throw 'Scheduled task action mismatch.' }
    if ($Task.Principal.UserId -notin @('SYSTEM', 'S-1-5-18', 'NT AUTHORITY\SYSTEM') -or
        [string]$Task.Principal.LogonType -ne 'ServiceAccount' -or
        [string]$Task.Principal.RunLevel -ne 'Highest') { throw 'Scheduled task must run elevated as SYSTEM.' }
    if (@($Task.Triggers).Count -ne 1 -or
        $Task.Triggers[0].CimClass.CimClassName -ne 'MSFT_TaskDailyTrigger' -or
        -not $Task.Triggers[0].Enabled -or $Task.Triggers[0].DaysInterval -ne 1 -or
        $Task.Triggers[0].Repetition.Interval -ne 'PT5M' -or
        $Task.Triggers[0].Repetition.Duration -ne 'P1D') { throw 'Scheduled task must repeat every five minutes daily.' }
    if ($Task.State -eq 'Disabled' -or -not $Task.Settings.Enabled -or
        -not $Task.Settings.StartWhenAvailable -or $Task.Settings.RunOnlyIfNetworkAvailable -or
        $Task.Settings.DisallowStartIfOnBatteries -or $Task.Settings.StopIfGoingOnBatteries -or
        [string]$Task.Settings.MultipleInstances -ne 'IgnoreNew' -or
        $Task.Settings.ExecutionTimeLimit -ne 'PT4M') { throw 'Scheduled task settings mismatch.' }
    Write-Output "DO-Monitor Local v$RequiredVersion detected; task: \$TaskName; SYSTEM; interval: PT5M."
    exit 0
} catch {
    Write-Output "DO-Monitor Local not detected: $($_.Exception.Message)"
    exit 1
}
