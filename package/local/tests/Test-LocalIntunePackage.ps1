#requires -Version 5.1
<#
.SYNOPSIS
    Verifies the real IntuneWin payload and mocked package lifecycle. Version: 2.8.6.
    Does not install tasks, elevate, or modify real Program Files/ProgramData.
#>
$ErrorActionPreference = 'Stop'
$RepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$Version = (Get-Content -LiteralPath (Join-Path $RepoRoot 'VERSION') -Raw).Trim()
$PayloadDir = Join-Path $RepoRoot "package\local\build\$Version"
$OutputDir = Join-Path $RepoRoot "package\output\local\$Version"
$TestRoot = Join-Path $env:TEMP ('DO-Local-Package-Tests-' + [Guid]::NewGuid().ToString('N'))
$OriginalProgramFiles = $env:ProgramFiles
$OriginalProgramData = $env:ProgramData
$Checks = 0
$MockState = @{ Task = $null; Started = 0; Unregistered = 0; Failure = ''; UnsafeAcl = $false }

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:Checks++
}

function Read-ZipEntry {
    param($Entry)
    $InputStream = $Entry.Open()
    $Memory = [IO.MemoryStream]::new()
    try {
        $InputStream.CopyTo($Memory)
        return ,$Memory.ToArray()
    } finally {
        $InputStream.Dispose()
        $Memory.Dispose()
    }
}

function Test-IntuneWinPayload {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $Archive = [IO.Compression.ZipFile]::OpenRead((Join-Path $OutputDir 'Install-DOMonitorLocal.intunewin'))
    try {
        $MetadataEntry = $Archive.Entries | Where-Object FullName -like '*Detection.xml'
        [xml]$Metadata = [Text.Encoding]::UTF8.GetString((Read-ZipEntry $MetadataEntry))
        Assert-True ($Metadata.ApplicationInfo.SetupFile -eq 'Install-DOMonitorLocal.cmd') 'Intune metadata selects the 64-bit bootstrapper'
        $EncryptedEntry = $Archive.Entries | Where-Object FullName -like '*Contents*'
        $Encrypted = Read-ZipEntry $EncryptedEntry
        $Encryption = $Metadata.ApplicationInfo.EncryptionInfo
        $Aes = [Security.Cryptography.Aes]::Create()
        $Aes.Key = [Convert]::FromBase64String($Encryption.EncryptionKey)
        $Aes.IV = [Convert]::FromBase64String($Encryption.InitializationVector)
        $Decryptor = $Aes.CreateDecryptor()
        try {
            $Plain = $Decryptor.TransformFinalBlock($Encrypted, 48, $Encrypted.Length - 48)
        } finally {
            $Decryptor.Dispose()
            $Aes.Dispose()
        }
        $Sha = [Security.Cryptography.SHA256]::Create()
        try {
            $Digest = [Convert]::ToBase64String($Sha.ComputeHash($Plain))
            Assert-True ($Digest -eq $Encryption.FileDigest) 'Decrypted Intune payload SHA256 matches metadata'
        } finally { $Sha.Dispose() }
        $Memory = [IO.MemoryStream]::new($Plain, $false)
        $Inner = [IO.Compression.ZipArchive]::new($Memory, [IO.Compression.ZipArchiveMode]::Read)
        try {
            $Expected = @('Install-DOMonitorLocal.cmd', 'Uninstall-DOMonitorLocal.cmd',
                'Install-DOMonitorLocal.ps1', 'Uninstall-DOMonitorLocal.ps1',
                'Detect-DOMonitorLocal.ps1', 'LocalPackage.psm1', 'Collect-DOStatusLocal.ps1', 'VERSION')
            Assert-True ($Inner.Entries.Count -eq $Expected.Count) 'Payload contains only the eight local-package files'
            foreach ($Name in $Expected) {
                $Entry = $Inner.Entries | Where-Object FullName -eq $Name
                Assert-True ($null -ne $Entry) "Packaged file: $Name"
                $Bytes = Read-ZipEntry $Entry
                $SourceBytes = [IO.File]::ReadAllBytes((Join-Path $PayloadDir $Name))
                Assert-True ([Convert]::ToBase64String($Bytes) -eq [Convert]::ToBase64String($SourceBytes)) "Packaged bytes match build input: $Name"
            }
        } finally {
            $Inner.Dispose()
            $Memory.Dispose()
        }
    } finally { $Archive.Dispose() }
}

try {
    Test-IntuneWinPayload
    foreach ($Name in @('Install-DOMonitorLocal.ps1', 'Detect-DOMonitorLocal.ps1')) {
        $Built = Get-Content -LiteralPath (Join-Path $PayloadDir $Name) -Raw
        Assert-True (-not $Built.Contains('__PACKAGE_VERSION__')) "Functional version token resolved: $Name"
        $VersionPattern = '(?m)^\$(?:RequiredVersion|Version) = ''{0}''\r?$' -f [regex]::Escape($Version)
        Assert-True ($Built -match $VersionPattern) "Functional version matches repository version: $Name"
    }
    $null = New-Item -ItemType Directory -Path $TestRoot
    Import-Module (Join-Path $PayloadDir 'LocalPackage.psm1')
    $Unsafe = Join-Path $TestRoot 'Unsafe'
    $null = New-Item -ItemType Directory -Path $Unsafe
    $Refused = $false
    try { $null = Open-DOLocalPackageDirectory -Path $Unsafe } catch { $Refused = $true }
    Assert-True $Refused 'Real security helper refuses user-owned inherited-ACL directories'
    Remove-Item -LiteralPath $Unsafe
    $Module = Get-Module LocalPackage
    & $Module {
        function script:Assert-DOLocalPackageHost {}
        function script:Open-DOLocalPackageDirectory {
            param([string]$Path, [switch]$Create)
            if (-not (Test-Path -LiteralPath $Path)) {
                if (-not $Create) { throw "Missing test directory: $Path" }
                $null = New-Item -ItemType Directory -Path $Path
            }
            [pscustomobject]@{ Path = $Path; Handles = [Collections.Generic.List[IDisposable]]::new() }
        }
    }
    $env:ProgramFiles = Join-Path $TestRoot 'Program Files'
    $env:ProgramData = Join-Path $TestRoot 'ProgramData'
    $null = New-Item -ItemType Directory -Path $env:ProgramFiles, $env:ProgramData
    Import-Module ScheduledTasks

    function Get-Acl {
        [CmdletBinding()]
        param([string]$LiteralPath)
        $Acl = [Security.AccessControl.DirectorySecurity]::new()
        $Acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
        $Acl.SetAccessRuleProtection($true, $false)
        $Sid = if ($MockState.UnsafeAcl) { 'S-1-1-0' } else { 'S-1-5-18' }
        $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
            [Security.Principal.SecurityIdentifier]::new($Sid), 'FullControl', 'Allow'))
        return $Acl
    }
    function Get-ScheduledTask {
        [CmdletBinding()]
        param([string]$TaskName, [string]$TaskPath)
        if ($MockState.Failure -eq 'Query') { throw 'Simulated Task Scheduler access failure' }
        if ($MockState.Task -and (-not $TaskName -or $TaskName -eq $MockState.Task.TaskName)) { return $MockState.Task }
        if ($TaskName) { throw 'Task not found' }
    }
    function Register-ScheduledTask {
        [CmdletBinding()]
        param($TaskName, $TaskPath, $Action, $Trigger, $Principal, $Settings, $Description, [switch]$Force)
        if ($MockState.Failure -eq 'Register') { throw 'Simulated registration failure' }
        $MockState.Task = [pscustomobject]@{
            TaskName = $TaskName; TaskPath = $TaskPath; Actions = @($Action); Triggers = @($Trigger)
            Principal = $Principal; Settings = $Settings; Description = $Description; State = 'Ready'
        }
    }
    function Disable-ScheduledTask {
        [CmdletBinding()]
        param($TaskName, $TaskPath)
        $MockState.Task.State = 'Disabled'
        $MockState.Task.Settings.Enabled = $false
    }
    function Stop-ScheduledTask {
        [CmdletBinding()]
        param($TaskName, $TaskPath)
        if ($MockState.Failure -eq 'Stop') { throw 'Simulated stop failure' }
    }
    function Start-ScheduledTask {
        [CmdletBinding()]
        param($TaskName, $TaskPath)
        $MockState.Started++
    }
    function Unregister-ScheduledTask {
        [CmdletBinding(SupportsShouldProcess)]
        param($TaskName, $TaskPath)
        $MockState.Task = $null
        $MockState.Unregistered++
    }
    function Invoke-Detection {
        $Messages = & (Join-Path $OutputDir 'Detect-DOMonitorLocal.ps1')
        [pscustomobject]@{ Code = $LASTEXITCODE; Messages = $Messages }
    }
    $ModuleMocks = @{}
    foreach ($Name in @('Get-ScheduledTask', 'Disable-ScheduledTask', 'Stop-ScheduledTask')) {
        $ModuleMocks[$Name] = (Get-Command $Name).ScriptBlock
    }
    & $Module {
        param($State, $Commands)
        $script:MockState = $State
        foreach ($Name in $Commands.Keys) { Set-Item -Path "Function:script:$Name" -Value $Commands[$Name] }
    } $MockState $ModuleMocks

    $Messages = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) "Fresh install succeeds: $Messages"
    Assert-True ($MockState.Started -eq 1) 'Installation requests an immediate first collection'
    Assert-True ($MockState.Task.Triggers[0].Repetition.Interval -eq 'PT5M') 'Actual scheduled task interval is exactly five minutes'
    Assert-True ($MockState.Task.Triggers[0].Repetition.Duration -eq 'P1D') 'Actual scheduled task repeats for a full day'
    Assert-True ($MockState.Task.Settings.ExecutionTimeLimit -eq 'PT4M') 'Actual task limit is below five minutes'
    Assert-True ((Invoke-Detection).Code -eq 0) 'Standalone Intune detection succeeds after install'
    $DataDir = Join-Path $env:ProgramData 'DO-Monitor-Local'
    $Snapshot = Join-Path $DataDir 'DO-preserve.json'
    [IO.File]::WriteAllText($Snapshot, '{"preserve":true}')
    $Messages = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) "Idempotent reinstall succeeds: $Messages"
    Assert-True ((Get-Content -LiteralPath $Snapshot -Raw) -eq '{"preserve":true}') 'Reinstall preserves snapshots'

    $MockState.Task.Settings.Enabled = $false
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses a disabled task'
    $MockState.Task.Settings.Enabled = $true
    $MockState.Task.Triggers[0].Repetition.Interval = 'PT15M'
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses an incorrect interval'
    $MockState.Task.Triggers[0].Repetition.Interval = 'PT5M'
    $MockState.Task.Settings.RunOnlyIfNetworkAvailable = $true
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses network-dependent collection'
    $MockState.Task.Settings.RunOnlyIfNetworkAvailable = $false
    $MockState.Task.Principal.UserId = 'OtherUser'
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses another execution account'
    $MockState.Task.Principal.UserId = 'SYSTEM'
    $MockState.UnsafeAcl = $true
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses unsafe file permissions'
    $MockState.UnsafeAcl = $false
    $CollectorPath = Join-Path $env:ProgramFiles 'DO-Monitor-Local\Collect-DOStatusLocal.ps1'
    Add-Content -LiteralPath $CollectorPath -Value '# changed'
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection refuses modified collector bytes'
    $Messages = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) "Reinstall repairs modified script: $Messages"

    $MockState.Failure = 'Query'
    $Messages = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 1) "Task Scheduler query errors are surfaced: $Messages"
    $MockState.Failure = 'Register'
    $Messages = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 1) "Task registration errors are surfaced: $Messages"
    $MockState.Failure = ''
    $null = & (Join-Path $PayloadDir 'Install-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'Installation recovers after registration failure'
    $Unrelated = Join-Path $env:ProgramFiles 'DO-Monitor-Local\unrelated.txt'
    Set-Content -LiteralPath $Unrelated -Value 'preserve'
    $MockState.Failure = 'Stop'
    $Messages = & (Join-Path $PayloadDir 'Uninstall-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 1) "Uninstall stop errors are surfaced: $Messages"
    $MockState.Failure = ''
    $Messages = & (Join-Path $PayloadDir 'Uninstall-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) "Uninstall succeeds: $Messages"
    Assert-True ($null -eq $MockState.Task -and $MockState.Unregistered -eq 1) 'Only local task is removed'
    Assert-True (-not (Test-Path -LiteralPath $CollectorPath)) 'Uninstall removes installed collector'
    Assert-True (Test-Path -LiteralPath $Snapshot) 'Uninstall preserves collected snapshots'
    Assert-True (Test-Path -LiteralPath $Unrelated) 'Uninstall preserves unrelated installation files'
    Assert-True ((Invoke-Detection).Code -eq 1) 'Detection reports uninstalled'
    $null = & (Join-Path $PayloadDir 'Uninstall-DOMonitorLocal.ps1')
    Assert-True ($LASTEXITCODE -eq 0) 'Repeated uninstall succeeds'
    Write-Output "PASS: $Checks package/lifecycle checks on PowerShell $($PSVersionTable.PSVersion); no real scheduled tasks modified."
} finally {
    $env:ProgramFiles = $OriginalProgramFiles
    $env:ProgramData = $OriginalProgramData
    Remove-Module LocalPackage -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $TestRoot) { Remove-Item -LiteralPath $TestRoot -Recurse -Force }
}
