#requires -Version 5.1
<#
.SYNOPSIS
    Removes only the local collector task and installed code. Version: 2.8.6.
    Collected snapshots are deliberately preserved.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$TaskName = 'DO-Monitor Local Collector'
$InstallDir = Join-Path $env:ProgramFiles 'DO-Monitor-Local'
$InstallLock = $null
try {
    Import-Module (Join-Path $PSScriptRoot 'LocalPackage.psm1') -ErrorAction Stop
    Assert-DOLocalPackageHost
    if (Test-Path -LiteralPath $InstallDir) {
        $InstallLock = Open-DOLocalPackageDirectory -Path $InstallDir
    }
    if (Stop-DOLocalPackageTask) {
        Unregister-ScheduledTask -TaskName $TaskName -TaskPath '\' -Confirm:$false
    }
    if ($InstallLock) {
        foreach ($Name in @('Collect-DOStatusLocal.ps1', 'VERSION')) {
            $Path = Join-Path $InstallDir $Name
            if (Test-Path -LiteralPath $Path) {
                $Item = Get-Item -LiteralPath $Path -Force
                if ($Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    throw "Refusing unsafe installed file: $Path"
                }
                Remove-Item -LiteralPath $Path -Force
            }
        }
    }
    # Keep the empty protected directory; never recurse into installation or data folders.
    Write-Output "DO-Monitor Local uninstalled. Snapshots preserved in $env:ProgramData\DO-Monitor-Local. Azure collector unchanged."
    exit 0
} catch {
    Write-Output "DO-Monitor Local uninstallation failed: $($_.Exception.Message)"
    exit 1
} finally {
    if (Get-Command Close-DOLocalPackageDirectory -ErrorAction SilentlyContinue) {
        Close-DOLocalPackageDirectory $InstallLock
    }
}
