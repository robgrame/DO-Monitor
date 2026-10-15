#requires -Version 5.1
<#
.SYNOPSIS
    Prepares loose USB installation files, without ZIP or Intune. Version: 2.10.12.
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
try {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
    $Version = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid version: $Version" }
    $OutputDir = Join-Path $PSScriptRoot "usb\output\DO-Monitor-Local-USB-$Version"
    if (Test-Path -LiteralPath $OutputDir) {
        throw 'This USB version already exists. Increment the Build before rebuilding.'
    }
    $Payload = $OutputDir
    $null = New-Item -ItemType Directory -Path $OutputDir -Force
    $Collector = Join-Path $RepoRoot 'scripts\Collect-DOStatusLocal.ps1'
    foreach ($Name in @('Install-DOMonitorLocal.ps1', 'Uninstall-DOMonitorLocal.ps1', 'Detect-DOMonitorLocal.ps1', 'LocalPackage.psm1')) {
        $Text = Get-Content -LiteralPath (Join-Path $PSScriptRoot "local\source\$Name") -Raw
        if ($Name -eq 'Detect-DOMonitorLocal.ps1') {
            $Tokens = $null; $Errors = $null
            $Ast = [Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$Errors)
            if ($Errors.Count) { throw 'Invalid detection template.' }
            $ChecksumStatements = @($Ast.FindAll({
                param($Node)
                ($Node -is [Management.Automation.Language.AssignmentStatementAst] -and
                    $Node.Left.Extent.Text -eq '$ExpectedCollectorHash') -or
                ($Node -is [Management.Automation.Language.IfStatementAst] -and
                    $Node.Extent.Text -like 'if ((Get-FileHash -LiteralPath $CollectorPath*')
            }, $true) | Sort-Object { $_.Extent.StartOffset } -Descending)
            if ($ChecksumStatements.Count -ne 2) { throw 'Detection template changed; cannot isolate USB checksum checks.' }
            foreach ($Statement in $ChecksumStatements) {
                $Text = $Text.Remove($Statement.Extent.StartOffset, $Statement.Extent.EndOffset - $Statement.Extent.StartOffset)
            }
            $Text = [regex]::Replace($Text, '(?m)^[ \t]+(?=\r?$)', '')
        }
        $Text = $Text.Replace('__PACKAGE_VERSION__', $Version)
        [IO.File]::WriteAllText((Join-Path $Payload $Name), $Text, [Text.UTF8Encoding]::new($false))
    }
    Copy-Item -LiteralPath $Collector -Destination $Payload
    [IO.File]::WriteAllText((Join-Path $Payload 'VERSION'), $Version, [Text.UTF8Encoding]::new($false))
    foreach ($Name in @('USB-Launcher.ps1', 'Installa.cmd', 'Disinstalla.cmd', 'LEGGIMI.txt')) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "usb\source\$Name") -Destination $OutputDir
    }
    Copy-Item -LiteralPath (Join-Path $RepoRoot 'LICENSE') -Destination (Join-Path $OutputDir 'LICENSE.txt')
    foreach ($Script in @(Get-ChildItem -LiteralPath $OutputDir -File | Where-Object Extension -in @('.ps1', '.psm1'))) {
        $Tokens = $null; $Errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($Script.FullName, [ref]$Tokens, [ref]$Errors)
        if ($Errors.Count) { throw "Invalid script $($Script.Name): $($Errors[0].Message)" }
        if ((Get-Content -LiteralPath $Script.FullName -Raw) -match '__PACKAGE_VERSION__|__COLLECTOR_SHA256__') {
            throw "Unresolved token: $($Script.Name)"
        }
    }
    Write-Output "USB files ready: $OutputDir"
    Write-Output 'Copy all files to the USB drive, then double-click Installa.cmd.'
    exit 0
} catch {
    Write-Output "USB package build failed: $($_.Exception.Message)"
    exit 1
}
