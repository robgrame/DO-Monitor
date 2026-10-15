#requires -Version 5.1
<#
.SYNOPSIS
    Builds the local-only DO collector IntuneWin package. Version: 2.9.8.
.PARAMETER ToolPath
    Microsoft IntuneWinAppUtil.exe. Defaults to the existing repository tool.
#>
[CmdletBinding()]
param(
    [string]$ToolPath
)
$ErrorActionPreference = 'Stop'
try {
    $RepoRoot = Split-Path $PSScriptRoot -Parent
    if (-not $ToolPath) {
        $ToolPath = Join-Path $RepoRoot 'deploy\tools\Microsoft-Win32-Content-Prep-Tool-1.8.6\IntuneWinAppUtil.exe'
    }
    $Version = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'local\VERSION') -Raw).Trim()
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "Invalid package version: $Version" }
    $SourceDir = Join-Path $PSScriptRoot 'local\source'
    $BuildDir = Join-Path $PSScriptRoot "local\build\$Version"
    $OutputDir = Join-Path $PSScriptRoot "output\local\$Version"
    $Collector = Join-Path $RepoRoot 'scripts\Collect-DOStatusLocal.ps1'
    $CollectorHash = (Get-FileHash -LiteralPath $Collector -Algorithm SHA256).Hash
    if (-not (Test-Path -LiteralPath $ToolPath -PathType Leaf)) {
        throw "Microsoft Win32 Content Prep Tool not found: $ToolPath. Supply -ToolPath."
    }
    $ToolPath = (Resolve-Path -LiteralPath $ToolPath).Path
    $Signature = Get-AuthenticodeSignature -LiteralPath $ToolPath
    if ($Signature.Status -ne 'Valid' -or $Signature.SignerCertificate.Subject -notmatch 'O=Microsoft Corporation(?:,|$)') {
        throw "Content Prep Tool must have a valid Microsoft signature: $ToolPath ($($Signature.Status))"
    }
    if (Test-Path -LiteralPath $BuildDir) { throw "Build directory already exists; use a new version: $BuildDir" }
    if (Test-Path -LiteralPath $OutputDir) { throw "Output directory already exists; use a new version: $OutputDir" }
    $null = New-Item -ItemType Directory -Path $BuildDir
    $null = New-Item -ItemType Directory -Path $OutputDir
    foreach ($Name in @('Install-DOMonitorLocal.ps1', 'Uninstall-DOMonitorLocal.ps1', 'Detect-DOMonitorLocal.ps1', 'LocalPackage.psm1')) {
        $Content = Get-Content -LiteralPath (Join-Path $SourceDir $Name) -Raw
        if ($Content -notmatch "Version: $([regex]::Escape($Version))") {
            throw "Package source version mismatch: $Name; expected $Version"
        }
        if ($Name -in @('Install-DOMonitorLocal.ps1', 'Detect-DOMonitorLocal.ps1') -and
            -not $Content.Contains('__PACKAGE_VERSION__')) {
            throw "Missing functional package version token: $Name"
        }
        $Content = $Content.Replace('__COLLECTOR_SHA256__', $CollectorHash).Replace('__PACKAGE_VERSION__', $Version)
        $Target = Join-Path $BuildDir $Name
        [IO.File]::WriteAllText($Target, $Content, [Text.UTF8Encoding]::new($false))
        $Tokens = $null; $ParseErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($Target, [ref]$Tokens, [ref]$ParseErrors)
        if ($ParseErrors.Count -gt 0) { throw "PowerShell syntax error in ${Name}: $($ParseErrors[0].Message)" }
    }
    Copy-Item -LiteralPath $Collector -Destination (Join-Path $BuildDir 'Collect-DOStatusLocal.ps1')
    foreach ($Name in @('Install-DOMonitorLocal.cmd', 'Uninstall-DOMonitorLocal.cmd')) {
        Copy-Item -LiteralPath (Join-Path $SourceDir $Name) -Destination $BuildDir
    }
    [IO.File]::WriteAllText((Join-Path $BuildDir 'VERSION'), $Version, [Text.UTF8Encoding]::new($false))
    Write-Output "Package version: $Version; collector SHA256: $CollectorHash; input: $BuildDir; tool: $ToolPath"
    & $ToolPath -c $BuildDir -s 'Install-DOMonitorLocal.cmd' -o $OutputDir -q
    if ($LASTEXITCODE -ne 0) { throw "IntuneWinAppUtil failed with exit code $LASTEXITCODE." }
    $Artifact = Join-Path $OutputDir 'Install-DOMonitorLocal.intunewin'
    if (-not (Test-Path -LiteralPath $Artifact -PathType Leaf) -or (Get-Item -LiteralPath $Artifact).Length -le 0) {
        throw 'Content Prep Tool did not produce a non-empty IntuneWin package.'
    }
    Copy-Item -LiteralPath (Join-Path $BuildDir 'Detect-DOMonitorLocal.ps1') -Destination $OutputDir
    $Manifest = [ordered]@{
        PackageVersion = $Version
        CollectorSHA256 = $CollectorHash
        PackageSHA256 = (Get-FileHash -LiteralPath $Artifact -Algorithm SHA256).Hash
        SetupFile = 'Install-DOMonitorLocal.cmd'
        TaskName = 'DO-Monitor Local Collector'
        Interval = 'PT5M'
        InstallCommand = 'Install-DOMonitorLocal.cmd'
        UninstallCommand = 'Uninstall-DOMonitorLocal.cmd'
        InstallBehavior = 'System'
        DetectionRunAs32Bit = $false
    }
    [IO.File]::WriteAllText((Join-Path $OutputDir 'package-info.json'),
        ($Manifest | ConvertTo-Json -Depth 4), [Text.UTF8Encoding]::new($false))
    Write-Output "Package ready: $Artifact"
    Write-Output "Detection script: $(Join-Path $OutputDir 'Detect-DOMonitorLocal.ps1')"
    exit 0
} catch {
    Write-Output "Local Intune package build failed: $($_.Exception.Message)"
    exit 1
}
