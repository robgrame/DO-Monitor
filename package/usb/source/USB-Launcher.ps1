#requires -Version 5.1
<#
.SYNOPSIS
    Offline USB installer/uninstaller with UAC. Version: 2.10.12.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('Install', 'Uninstall')][string]$Action)
$ErrorActionPreference = 'Stop'
try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
        throw 'Avvia Installa.cmd o Disinstalla.cmd per utilizzare PowerShell a 64 bit.'
    }
    $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $Principal = [Security.Principal.WindowsPrincipal]::new($Identity)
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        $Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Action $Action"
        $Process = Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
            -ArgumentList $Arguments -Verb RunAs -WorkingDirectory $PSScriptRoot -Wait -PassThru
        exit $Process.ExitCode
    }
    $Name = if ($Action -eq 'Install') { 'Install-DOMonitorLocal.ps1' } else { 'Uninstall-DOMonitorLocal.ps1' }
    & (Join-Path $PSScriptRoot $Name)
    exit $LASTEXITCODE
} catch {
    Write-Output "Operazione USB non riuscita: $($_.Exception.Message)"
    exit 1
}
