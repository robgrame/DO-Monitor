#requires -Version 5.1
<#
.SYNOPSIS
    Offline regression checks for the local DO collector. Version: 2.7.4.
#>
$ErrorActionPreference = 'Stop'
$Collector = Join-Path (Split-Path $PSScriptRoot -Parent) 'Collect-DOStatusLocal.ps1'
$TestRoot = Join-Path $env:TEMP ("DO-Local-Tests-" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $TestRoot
$MockState = @{ Scenario = 'Complete'; JobCount = 1 }
$script:Checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:Checks++
}

function Get-CimInstance {
    [CmdletBinding()]
    param([string]$ClassName)
    if ($MockState.Scenario -eq 'DeviceFailure' -and $ClassName -eq 'Win32_BIOS') {
        throw 'Simulated CIM failure'
    }
    [pscustomobject]@{
        Version = '10.0'; BuildNumber = '26100'; SerialNumber = 'OFFLINE-TEST'
        Domain = 'TestDomain'; Manufacturer = 'TestVendor'; Model = 'TestModel'
    }
}

function Get-DeliveryOptimizationStatus {
    [CmdletBinding()]
    param()
    if ($MockState.Scenario -eq 'JobFailure') { throw 'Simulated DO query failure' }
    for ($Index = 0; $Index -lt $MockState.JobCount; $Index++) {
        $Data = @{
            FileId = "file-$Index"; Status = 'Downloading'; Priority = 'Foreground'
            DownloadMode = 'LAN'; SourceURL = 'https://example.invalid/file'
            CacheHost = 'test-cache'; PredefinedCallerApplication = 'WindowsUpdate'
            PercentPeerCaching = 25; DownloadDuration = [TimeSpan]::FromSeconds(12)
            ExpireOn = [DateTime]::new(2026, 10, 16, 0, 0, 0, [DateTimeKind]::Utc)
            IsPinned = $true
        }
        foreach ($Field in @(
            'FileSize', 'FileSizeInCache', 'TotalBytesDownloaded', 'BytesFromPeers',
            'BytesFromHttp', 'BytesFromCacheServer', 'BytesFromLanPeers', 'BytesFromGroupPeers',
            'BytesFromInternetPeers', 'BytesFromLinkLocalPeers', 'BytesToLanPeers',
            'BytesToGroupPeers', 'BytesToInternetPeers', 'BytesToLinkLocalPeers'
        )) { $Data[$Field] = [long]5000000001 }
        foreach ($Field in @(
            'HttpConnectionCount', 'LanConnectionCount', 'GroupConnectionCount',
            'InternetConnectionCount', 'LinkLocalConnectionCount', 'CacheServerConnectionCount', 'NumPeers'
        )) { $Data[$Field] = 2 }
        if ($MockState.Scenario -eq 'MissingProperties') {
            $Data.Remove('BytesFromLinkLocalPeers')
            $Data.Remove('Priority')
            $Data.Remove('PercentPeerCaching')
        }
        [pscustomobject]$Data
    }
}

function Get-DeliveryOptimizationPerfSnap {
    [CmdletBinding()]
    param()
    if ($MockState.Scenario -eq 'PerfFailure') { throw 'Simulated performance failure' }
    if ($MockState.Scenario -eq 'PerfEmpty') { return }
    [pscustomobject]@{ DownloadMode = 'LAN'; TotalBytesDownloaded = [long]9000000001; Files = 2 }
}

function Test-Path {
    [CmdletBinding(DefaultParameterSetName = 'Literal')]
    param(
        [Parameter(ParameterSetName = 'Literal')][string]$LiteralPath,
        [Parameter(ParameterSetName = 'Path')][string]$Path,
        [string]$PathType = 'Any'
    )
    $Target = if ($PSCmdlet.ParameterSetName -eq 'Literal') { $LiteralPath } else { $Path }
    if ($Target -like 'HKLM:\*') {
        if ($MockState.Scenario -eq 'PolicyMissing') { return $false }
        if ($MockState.Scenario -eq 'PolicyFailure' -and $Target -like '*PolicyManager*') {
            throw 'Simulated registry access failure'
        }
        return $true
    }
    if ($MockState.Scenario -eq 'CreationRace' -and $Target -eq (Join-Path $TestRoot 'CreationRace') -and
        -not [IO.Directory]::Exists($Target)) {
        # Simulate another writer creating an inherited-ACL directory after the check.
        $null = [IO.Directory]::CreateDirectory($Target)
        return $false
    }
    Microsoft.PowerShell.Management\Test-Path -LiteralPath $Target -PathType $PathType
}

function Get-ItemProperty {
    [CmdletBinding()]
    param([string]$LiteralPath)
    [pscustomobject]@{ DODownloadMode = 1; PSPath = $LiteralPath }
}

function Invoke-Case {
    param([string]$Name, [int]$ExpectedExit, [int]$Count = 1)
    $MockState.Scenario = $Name
    $MockState.JobCount = $Count
    $Directory = Join-Path $TestRoot $Name
    $Messages = & $Collector -OutputDirectory $Directory 3>&1
    Assert-True ($LASTEXITCODE -eq $ExpectedExit) "$Name exit code: $LASTEXITCODE; $Messages"
    $Files = @(Get-ChildItem -LiteralPath $Directory -Filter 'DO-*.json')
    if ($ExpectedExit -eq 1) {
        Assert-True ($Files.Count -eq 0) "$Name must not publish a JSON snapshot"
        return
    }
    Assert-True ($Files.Count -eq 1) "$Name writes exactly one snapshot"
    Assert-True (@(Get-ChildItem -LiteralPath $Directory -Filter '*.tmp').Count -eq 0) "$Name leaves no temporary files"
    $Bytes = [IO.File]::ReadAllBytes($Files[0].FullName)
    Assert-True ($Bytes[0] -eq 123) "$Name uses UTF-8 JSON without BOM"
    $RawJson = Get-Content -LiteralPath $Files[0].FullName -Raw -Encoding UTF8
    $Snapshot = $RawJson | ConvertFrom-Json
    Assert-True ($Snapshot.JobCount -eq $Count -and $Snapshot.Jobs -is [array]) "$Name preserves Jobs array shape: count=$($Snapshot.JobCount), expected=$Count, type=$($Snapshot.Jobs.GetType().FullName)"
    Assert-True ($Snapshot.CollectorVersion -eq '2.7.4' -and $Snapshot.SchemaVersion -eq '1.0.0') "$Name versions"
    Assert-True ($RawJson -match '"CollectedAt":"[^"]+Z"') "$Name UTC timestamp"
    Assert-True ($Snapshot.TotalFromHttp -eq ([long]5000000001 * $Count)) "$Name preserves 64-bit counters"
    Assert-True ($Snapshot.TotalUploaded -eq ([long]5000000001 * 4 * $Count)) "$Name includes all upload destinations"
    $ExpectedStatus = if ($ExpectedExit -eq 2) { 'Partial' } else { 'Complete' }
    Assert-True ($Snapshot.CollectionStatus -eq $ExpectedStatus) "$Name status"
    Assert-True (($Snapshot.CollectionErrors.Count -gt 0) -eq ($ExpectedExit -eq 2)) "$Name explicit errors"
    return $Snapshot
}

try {
    $Tokens = $null
    $ParseErrors = $null
    $Ast = [Management.Automation.Language.Parser]::ParseFile($Collector, [ref]$Tokens, [ref]$ParseErrors)
    Assert-True ($ParseErrors.Count -eq 0) 'Collector parses'
    $Commands = $Ast.FindAll({
        param($Node)
        $Node -is [Management.Automation.Language.CommandAst]
    }, $true) | ForEach-Object { $_.GetCommandName() }
    Assert-True (-not ($Commands -match 'Invoke-(RestMethod|WebRequest)|^Connect-|^az$')) 'No network/Azure commands'

    $Complete = Invoke-Case 'Complete' 0
    Assert-True ($Complete.Jobs[0].DownloadDuration -eq 12) 'Duration normalized to seconds'
    Assert-True ($Complete.Policies.GPO_DODownloadMode -eq 1 -and
        $Complete.Policies.MDM_DODownloadMode -eq 1 -and
        $Complete.Policies.Local_DODownloadMode -eq 1) 'All policy sources'
    $Original = Get-Content (Join-Path (Split-Path $PSScriptRoot -Parent) 'Detect-DOStatus.ps1') -Raw
    $OriginalFields = [regex]::Matches($Original, '(?m)^\s*(\w+)\s*=\s*(?:if\s*\(\$Job\.|(?:\[\w+\])?\$Job\.)') |
        ForEach-Object { $_.Groups[1].Value }
    foreach ($Field in $OriginalFields) {
        Assert-True ($Field -in $Complete.Jobs[0].PSObject.Properties.Name) "Existing job field retained: $Field"
    }
    $CompleteDirectory = Join-Path $TestRoot 'Complete'
    $First = Get-ChildItem -LiteralPath $CompleteDirectory -Filter 'DO-*.json'
    $Before = [IO.File]::ReadAllText($First.FullName)
    $null = & $Collector -OutputDirectory $CompleteDirectory
    Assert-True ($LASTEXITCODE -eq 0) 'Repeated run succeeds'
    Assert-True (@(Get-ChildItem -LiteralPath $CompleteDirectory -Filter 'DO-*.json').Count -eq 2) 'Repeated run does not overwrite'
    Assert-True ([IO.File]::ReadAllText($First.FullName) -eq $Before) 'Existing snapshot unchanged'
    $Acl = Get-Acl -LiteralPath $CompleteDirectory
    Assert-True $Acl.AreAccessRulesProtected 'Storage ACL disables inheritance'
    $Allowed = @([Security.Principal.WindowsIdentity]::GetCurrent().User.Value, 'S-1-5-18', 'S-1-5-32-544')
    foreach ($Rule in $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        Assert-True ($Rule.IdentityReference.Value -in $Allowed) 'Storage ACL principals restricted'
    }
    $null = Invoke-Case 'Empty' 0 0
    $null = Invoke-Case 'Multiple' 0 2
    $Missing = Invoke-Case 'MissingProperties' 0
    Assert-True ($Missing.Jobs[0].PercentPeerCaching -eq 0) 'Missing numeric ratio normalized to zero'
    $Partial = Invoke-Case 'DeviceFailure' 2
    Assert-True ($null -eq $Partial.SerialNumber -and $Partial.Model -eq 'TestModel') 'CIM failures isolated'
    $null = Invoke-Case 'PerfFailure' 2
    $null = Invoke-Case 'PerfEmpty' 2
    $Partial = Invoke-Case 'PolicyFailure' 2
    Assert-True ($Partial.Policies.Local_DODownloadMode -eq 1) 'Registry failure does not skip other sources'
    $NoPolicy = Invoke-Case 'PolicyMissing' 0
    Assert-True ($NoPolicy.Policies.PSObject.Properties.Name.Count -eq 0) 'Missing policies are normal'
    $null = Invoke-Case 'JobFailure' 1
    $null = Invoke-Case 'CreationRace' 1
    Assert-True (-not (Get-Acl -LiteralPath (Join-Path $TestRoot 'CreationRace')).AreAccessRulesProtected) 'Raced directory rejected without modifying its ACL'

    $Unsafe = Join-Path $TestRoot 'Unsafe'
    $null = New-Item -ItemType Directory -Path $Unsafe
    $Sentinel = Join-Path $Unsafe 'existing.txt'
    Set-Content -LiteralPath $Sentinel -Value 'preserve'
    foreach ($Path in @($Unsafe, '\\server\share\DO', 'relative', 'C:\', "$TestRoot\DO:stream", "$TestRoot\missing\DO")) {
        $Messages = & $Collector -OutputDirectory $Path 3>&1
        Assert-True ($LASTEXITCODE -eq 1) "Reject unsafe path: $Path; $Messages"
    }
    Assert-True ((Get-Content -LiteralPath $Sentinel) -eq 'preserve') 'Existing unsafe directory is untouched'
    $LockedDirectory = Join-Path $TestRoot 'Locked'
    $null = New-Item -ItemType Directory -Path $LockedDirectory
    $Handle = [DOMonitor.LocalStorage.NativeMethods]::CreateFile(
        $LockedDirectory, 2147483648, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
    try {
        Assert-True (-not $Handle.IsInvalid) 'Native storage directory handle acquired'
        $ReplacementBlocked = $false
        try { [IO.Directory]::Move($LockedDirectory, "$LockedDirectory-renamed") } catch [IO.IOException] {
            $ReplacementBlocked = $true
        }
        Assert-True $ReplacementBlocked 'Directory pin blocks rename/replacement'
    } finally {
        $Handle.Dispose()
    }
    $Junction = Join-Path $TestRoot 'Junction'
    $null = New-Item -ItemType Junction -Path $Junction -Target $CompleteDirectory
    try {
        $null = & $Collector -OutputDirectory "$Junction\Child"
        Assert-True ($LASTEXITCODE -eq 1) 'Reject reparse point ancestors'
    } finally {
        [IO.Directory]::Delete($Junction)
    }
    Write-Output "PASS: $script:Checks offline checks on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    Remove-Item -LiteralPath $TestRoot -Recurse -Force
}
