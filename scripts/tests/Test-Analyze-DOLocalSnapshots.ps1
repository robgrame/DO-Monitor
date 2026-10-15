#requires -Version 5.1
<#
.SYNOPSIS
    Deterministic offline analyzer checks. Version: 2.9.8.
#>
$ErrorActionPreference = 'Stop'
$Analyzer = Join-Path (Split-Path $PSScriptRoot -Parent) 'Analyze-DOLocalSnapshots.ps1'
$Root = Join-Path $env:TEMP ('DO-Analysis-Tests-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $Root
$Checks = 0
$Fields = @(
    'TotalBytesDownloaded', 'BytesFromPeers', 'BytesFromHttp', 'BytesFromCacheServer',
    'BytesFromLanPeers', 'BytesFromGroupPeers', 'BytesFromInternetPeers', 'BytesFromLinkLocalPeers',
    'BytesToLanPeers', 'BytesToGroupPeers', 'BytesToInternetPeers', 'BytesToLinkLocalPeers'
)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "Assertion failed: $Message" }
    $script:Checks++
}

function New-Job {
    param([string]$Id, [decimal]$Downloaded, [decimal]$Http, [decimal]$Peers = 0, [decimal]$Upload = 0, [decimal]$LinkUpload = 0, [string]$Status = 'Downloading')
    $Job = [ordered]@{
        FileId = $Id; Status = $Status; DownloadMode = 'LAN'
        SourceURL = 'https://example.invalid/content'; PredefinedCallerApplication = 'WindowsUpdate'
        FileSize = 1000; FileSizeInCache = 100
    }
    foreach ($Field in $Fields) { $Job[$Field] = 0 }
    $Job.TotalBytesDownloaded = if ([decimal]::Truncate($Downloaded) -eq $Downloaded) { [long]$Downloaded } else { $Downloaded }
    $Job.BytesFromHttp = if ([decimal]::Truncate($Http) -eq $Http) { [long]$Http } else { $Http }
    $Job.BytesFromPeers = $Peers
    $Job.BytesToLanPeers = $Upload; $Job.BytesToLinkLocalPeers = $LinkUpload
    return [pscustomobject]$Job
}

function New-Snapshot {
    param([int]$Minute, [array]$Jobs = @())
    [pscustomobject][ordered]@{
        SchemaVersion = '1.0.0'; CollectorVersion = '2.7.4'; SnapshotId = [Guid]::NewGuid().ToString('N')
        DeviceName = 'TEST-PC'; SerialNumber = 'TEST-SERIAL'
        CollectedAt = [DateTime]::new(2026, 10, 15, 10, 0, 0, [DateTimeKind]::Utc).AddMinutes($Minute).ToString('o')
        OSVersion = '10.0'; OSBuild = '26100'; Domain = 'TEST'; Manufacturer = 'TEST'; Model = 'TEST'
        CollectionStatus = 'Complete'; CollectionErrors = @()
        JobCount = $Jobs.Count; Jobs = $Jobs
        Policies = [pscustomobject]@{}; PerfSnap = [pscustomobject]@{}
    }
}

function Save-Snapshot {
    param($Data, [string]$Directory, [string]$Name)
    if (-not (Test-Path -LiteralPath $Directory)) { $null = New-Item -ItemType Directory -Path $Directory }
    [IO.File]::WriteAllText((Join-Path $Directory $Name), ($Data | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}

function Assert-Rejected {
    param([string]$Name, $Data, $Second)
    $Directory = Join-Path $Root $Name
    Save-Snapshot $Data $Directory 'DO-one.json'
    if ($null -ne $Second) { Save-Snapshot $Second $Directory 'DO-two.json' }
    $Output = Join-Path $Root "$Name-report.json"
    $Messages = & $Analyzer -InputDirectory $Directory -OutputPath $Output 2>&1
    Assert-True ($LASTEXITCODE -eq 1) "$Name rejects input: $Messages"
    Assert-True (-not (Test-Path -LiteralPath $Output)) "$Name publishes no report"
}

try {
    $InputDir = Join-Path $Root 'Main'
    $First = New-Snapshot 0 @((New-Job 'A' 100 80 20 10 5))
    $First.Policies = [pscustomobject]@{ GPO_DODownloadMode = 1; MDM_DODownloadMode = 2 }
    $First.PerfSnap = [pscustomobject]@{ CpuUsagePct = 10; TotalBytesDownloaded = 100; CacheSizeBytes = $null }
    $Middle = New-Snapshot 5 @((New-Job 'A' 150 100 50 12 7 'Complete'), (New-Job 'B' 40 40))
    $Middle.CollectionStatus = 'Partial'
    $Middle.CollectionErrors = @(
        [pscustomobject]@{ Stage = 'Policies:MDM'; Message = 'Simulated registry access failure' },
        [pscustomobject]@{ Stage = 'PerfSnap'; Message = 'Simulated performance failure' }
    )
    $Middle.Policies = [pscustomobject]@{ GPO_DODownloadMode = 2; Local_TestPolicy = @(1, 2) }
    $Last = New-Snapshot 15 @((New-Job 'A' 30 20 10 3 1))
    $Last.Policies = [pscustomobject]@{ MDM_DODownloadMode = 3; Local_TestPolicy = @(1, 2) }
    $Last.PerfSnap = [pscustomobject]@{ CpuUsagePct = 30; TotalBytesDownloaded = 180; CacheSizeBytes = $null }
    Save-Snapshot $First $InputDir 'DO-z-first.json'
    Save-Snapshot $Middle $InputDir 'DO-b-middle.json'
    Save-Snapshot $Last $InputDir 'DO-a-last.json'
    Save-Snapshot $Middle $InputDir 'DO-duplicate.json'
    Set-Content -LiteralPath (Join-Path $InputDir 'DO-incomplete.json.tmp') -Value '{'
    $OutputPath = Join-Path $Root 'report.json'
    $Report = & $Analyzer -InputDirectory $InputDir -OutputPath $OutputPath
    Assert-True ($LASTEXITCODE -eq 0) 'Analysis succeeds'
    Assert-True ($Report.Summary.InputFileCount -eq 4 -and $Report.Summary.SnapshotCount -eq 3) 'Snapshot deduplication and tmp exclusion'
    Assert-True ($Report.Summary.DuplicateFileCount -eq 1) 'Duplicate file recorded'
    Assert-True ($Report.Summary.UniqueJobCount -eq 2 -and $Report.Summary.LatestJobCount -eq 1) 'Historical distinct jobs versus latest jobs'
    Assert-True ($Report.Traffic.ObservedCounters.TotalBytesDownloaded -eq 220) 'No repeated cumulative download sum'
    Assert-True ($Report.Traffic.ObservedCounters.BytesFromHttp -eq 160) 'HTTP deltas and resets'
    Assert-True ($Report.Traffic.ObservedCounters.BytesFromPeers -eq 60) 'Peer deltas and resets'
    Assert-True ($Report.Traffic.FirstObservedCounters.TotalBytesDownloaded -eq 140) 'Each job baseline separated'
    Assert-True ($Report.Traffic.SubsequentObservedCounters.TotalBytesDownloaded -eq 80) 'Subsequent increments exclude first samples'
    Assert-True ($Report.Traffic.UploadedBytes -eq 23) 'All upload destinations including link-local'
    Assert-True ($Report.Traffic.PeerShareOfAccountedSourcesPct -eq 27.27) 'Measured peer percentage'
    Assert-True ($Report.DataQuality.CounterResets.Count -eq 1) 'One reset event per job observation'
    Assert-True ($Report.DataQuality.SamplingGaps.Count -eq 1 -and $Report.DataQuality.SamplingGaps[0].Minutes -eq 10) 'Gap threshold uses actual timestamps'
    Assert-True ($Report.Summary.AverageIntervalMinutes -eq 7.5) 'Sampling interval statistics'
    Assert-True ($Report.DataQuality.CollectionErrors.Count -eq 2) 'Partial collection errors preserved'
    $A = $Report.Jobs | Where-Object FileId -eq 'A'
    Assert-True ($A.ObservationCount -eq 3 -and $A.StatusHistory.Count -eq 3) 'Job observations and status history'
    Assert-True ($A.LatestJob.SourceURL -eq 'https://example.invalid/content') 'Latest raw job details preserved'
    Assert-True ($Report.Policies.Changes.Count -eq 4) 'Expected policy additions, removals and changes'
    Assert-True (@($Report.Policies.Changes | Where-Object { $_.Source -eq 'MDM' -and $_.Change -eq 'Removed' }).Count -eq 0) 'Unavailable source does not imply removed policy'
    Assert-True ($Report.Policies.LatestKnownBySource.MDM.Values.MDM_DODownloadMode -eq 3) 'Latest known MDM value'
    Assert-True ($Report.Performance.Summary.CpuUsagePct.Average -eq 20 -and
        $Report.Performance.Summary.CpuUsagePct.SampleCount -eq 2) 'Performance skips unavailable samples'
    Assert-True ($Report.Performance.Summary.TotalBytesDownloaded.Average -eq 140) 'Performance cumulative counters not treated as traffic'
    Assert-True (-not $Report.Performance.Summary.Contains('CacheSizeBytes')) 'Null performance is not a zero sample'
    $Export = Get-Content -LiteralPath $OutputPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-True ($Export.Traffic.ObservedCounters.TotalBytesDownloaded -eq 220 -and $Export.Jobs.Count -eq 2) 'Persisted JSON report contains details and exact totals'
    Assert-True ([IO.File]::ReadAllBytes($OutputPath)[0] -eq 123) 'Export is UTF-8 without BOM'
    $OriginalBytes = [IO.File]::ReadAllText($OutputPath)
    $null = & $Analyzer -InputDirectory $InputDir -OutputPath $OutputPath 2>&1
    Assert-True ($LASTEXITCODE -eq 1 -and [IO.File]::ReadAllText($OutputPath) -eq $OriginalBytes) 'Existing reports never overwritten'
    Assert-True (@(Get-ChildItem -LiteralPath $Root -Filter '*.tmp').Count -eq 0) 'No incomplete export remains'

    $Reappearing = Join-Path $Root 'ReappearingJobs'
    Save-Snapshot (New-Snapshot 0 @((New-Job 'C' 100 100), (New-Job 'D' 100 100))) $Reappearing 'DO-one.json'
    Save-Snapshot (New-Snapshot 5) $Reappearing 'DO-two.json'
    Save-Snapshot (New-Snapshot 10 @((New-Job 'C' 150 150), (New-Job 'D' 20 20))) $Reappearing 'DO-three.json'
    $Again = & $Analyzer -InputDirectory $Reappearing
    $C = $Again.Jobs | Where-Object FileId -eq 'C'
    $D = $Again.Jobs | Where-Object FileId -eq 'D'
    Assert-True ($LASTEXITCODE -eq 0 -and $C.ObservedCounters.TotalBytesDownloaded -eq 150 -and
        $C.ObservationCount -eq 2 -and $C.ResetCount -eq 0) 'Reappearing job increase uses its previous baseline'
    Assert-True ($D.ObservedCounters.TotalBytesDownloaded -eq 120 -and
        $D.ObservationCount -eq 2 -and $D.ResetCount -eq 1) 'Reappearing job decrease flags a reset'
    Assert-True ($Again.Traffic.FirstObservedCounters.TotalBytesDownloaded -eq 200 -and
        $Again.Traffic.SubsequentObservedCounters.TotalBytesDownloaded -eq 70) 'Disappearance never re-baselines a job'
    $UnavailableDir = Join-Path $Root 'LatestPolicyUnavailable'
    Save-Snapshot $First $UnavailableDir 'DO-one.json'
    Save-Snapshot $Middle $UnavailableDir 'DO-two.json'
    $Unavailable = & $Analyzer -InputDirectory $UnavailableDir
    Assert-True ($Unavailable.Policies.LatestSnapshotAvailability.MDM -eq 'Unavailable' -and
        $Unavailable.Policies.LatestKnownBySource.MDM.Values.MDM_DODownloadMode -eq 2) 'Latest failed policy sample retains timestamped last-known values'
    $Reordered = [ordered]@{}
    $Properties = @($First.PSObject.Properties)
    for ($Index = $Properties.Count - 1; $Index -ge 0; $Index--) { $Reordered[$Properties[$Index].Name] = $Properties[$Index].Value }
    $CanonicalDir = Join-Path $Root 'CanonicalDuplicates'
    Save-Snapshot $First $CanonicalDir 'DO-one.json'
    Save-Snapshot ([pscustomobject]$Reordered) $CanonicalDir 'DO-two.json'
    $Canonical = & $Analyzer -InputDirectory $CanonicalDir
    Assert-True ($LASTEXITCODE -eq 0 -and $Canonical.Summary.SnapshotCount -eq 1 -and
        $Canonical.Summary.DuplicateFileCount -eq 1) 'Object property order does not change snapshot identity'

    $Empty = New-Snapshot 0
    Save-Snapshot $Empty (Join-Path $Root 'EmptyJobs') 'DO-one.json'
    $Zero = & $Analyzer -InputDirectory (Join-Path $Root 'EmptyJobs')
    Assert-True ($LASTEXITCODE -eq 0 -and $Zero.Jobs.Count -eq 0 -and $null -eq $Zero.Traffic.PeerShareOfAccountedSourcesPct) 'Zero jobs and zero traffic have no fabricated percentage'
    $BigDir = Join-Path $Root 'LargeCounters'
    Save-Snapshot (New-Snapshot 0 @((New-Job 'A' 9007199254740992 9007199254740992))) $BigDir 'DO-one.json'
    Save-Snapshot (New-Snapshot 5 @((New-Job 'A' 9007199254740993 9007199254740993))) $BigDir 'DO-two.json'
    $Big = & $Analyzer -InputDirectory $BigDir
    Assert-True ($LASTEXITCODE -eq 0 -and $Big.Traffic.SubsequentObservedCounters.TotalBytesDownloaded -eq 1) 'Byte precision beyond double exact range'
    $HugeDir = Join-Path $Root 'LargeTotals'
    Save-Snapshot (New-Snapshot 0 @((New-Job 'A' ([long]::MaxValue) 0), (New-Job 'B' ([long]::MaxValue) 0))) $HugeDir 'DO-one.json'
    $Huge = & $Analyzer -InputDirectory $HugeDir
    Assert-True ($LASTEXITCODE -eq 0 -and $Huge.Traffic.ObservedCounters.TotalBytesDownloaded -eq [decimal]'18446744073709551614') 'Aggregate totals do not overflow Int64'

    $Bad = New-Snapshot 0
    $Bad.DeviceName = 'OTHER-PC'
    Assert-Rejected 'MixedDevices' $Empty $Bad
    $Bad = New-Snapshot 5
    $Bad.SerialNumber = 'OTHER-SERIAL'
    Assert-Rejected 'MixedSerials' $Empty $Bad
    $Bad = New-Snapshot 0
    $Bad.SchemaVersion = '2.0.0'
    Assert-Rejected 'FutureSchema' $Bad
    $Bad = New-Snapshot 0
    $Bad.CollectedAt = '2026-10-15'
    Assert-Rejected 'MissingTimezone' $Bad
    $Bad = New-Snapshot 0 @((New-Job 'A' -1 0))
    Assert-Rejected 'NegativeCounter' $Bad
    $Bad = New-Snapshot 0 @((New-Job 'A' 1.5 0))
    Assert-Rejected 'FractionalCounter' $Bad
    $Bad = New-Snapshot 0 @((New-Job 'A' 1 0))
    $Bad.Jobs[0].BytesFromPeers = '1'
    Assert-Rejected 'StringCounter' $Bad
    $Bad = New-Snapshot 0 @((New-Job 'A' 1 0))
    $Bad.JobCount = 2
    Assert-Rejected 'JobCountMismatch' $Bad
    $Bad = New-Snapshot 5
    $Bad.SnapshotId = $Empty.SnapshotId
    Assert-Rejected 'ConflictingSnapshotId' $Empty $Bad
    Assert-Rejected 'AmbiguousTime' $Empty (New-Snapshot 0)
    $Corrupt = Join-Path $Root 'Corrupt'
    $null = New-Item -ItemType Directory -Path $Corrupt
    Set-Content -LiteralPath (Join-Path $Corrupt 'DO-broken.json') -Value '{'
    $null = & $Analyzer -InputDirectory $Corrupt 2>&1
    Assert-True ($LASTEXITCODE -eq 1) 'Corrupt JSON fails rather than silently skipping'
    function ConvertFrom-Json {
        [CmdletBinding()]
        param([Parameter(ValueFromPipeline)][string]$InputObject)
        process {
            $Value = Microsoft.PowerShell.Utility\ConvertFrom-Json -InputObject $InputObject
            $Value.CollectedAt = [DateTime]::SpecifyKind([DateTime]'2026-10-15T10:00:00', [DateTimeKind]::Unspecified)
            return $Value
        }
    }
    try {
        $Bad = New-Snapshot 0
        $Bad.CollectedAt = '2026-10-15T10:00:00'
        Assert-Rejected 'LegacyReaderUnspecifiedTimezone' $Bad
    } finally {
        Remove-Item Function:\ConvertFrom-Json
    }
    Write-Output "PASS: $Checks analyzer checks on PowerShell $($PSVersionTable.PSVersion)."
} finally {
    Remove-Item -LiteralPath $Root -Recurse -Force
}
