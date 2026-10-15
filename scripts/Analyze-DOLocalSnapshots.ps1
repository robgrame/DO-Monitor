#requires -Version 5.1
<#
.SYNOPSIS
    Analyzes local Delivery Optimization snapshots for one device. Version: 2.9.8.
.DESCRIPTION
    Returns a report object with deduplicated job counters, policy changes,
    performance statistics, timeline and data-quality diagnostics. No network calls.
    Invalid input fails the analysis; no files are silently skipped.
.PARAMETER InputDirectory
    Directory containing DO-*.json snapshots. Defaults to the local collector store.
.PARAMETER OutputPath
    Optional NEW JSON report file. Its parent must exist. Existing files are never
    overwritten. The report contains the same sensitive identifiers/URLs as input.
.PARAMETER Recurse
    Include snapshots in child directories.
.PARAMETER ExpectedIntervalMinutes
    Expected sampling interval. Gaps greater than 1.5 times this value are flagged.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$InputDirectory = "$env:ProgramData\DO-Monitor-Local",
    [string]$OutputPath,
    [switch]$Recurse,
    [ValidateRange(1, 1440)]
    [int]$ExpectedIntervalMinutes = 5
)
$ErrorActionPreference = 'Stop'
$AnalyzerVersion = '2.9.8'
$TemporaryPath = $null
$OwnsTemporaryFile = $false
$CounterFields = @(
    'TotalBytesDownloaded', 'BytesFromPeers', 'BytesFromHttp', 'BytesFromCacheServer',
    'BytesFromLanPeers', 'BytesFromGroupPeers', 'BytesFromInternetPeers', 'BytesFromLinkLocalPeers',
    'BytesToLanPeers', 'BytesToGroupPeers', 'BytesToInternetPeers', 'BytesToLinkLocalPeers'
)

function ConvertTo-CanonicalValue {
    param($Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) { return $Value.ToUniversalTime().ToString('o') }
    if ($Value -is [Collections.IDictionary]) {
        $Object = [ordered]@{}
        foreach ($Key in ($Value.Keys | Sort-Object)) { $Object[$Key] = ConvertTo-CanonicalValue $Value[$Key] }
        return $Object
    }
    if ($Value -is [pscustomobject]) {
        $Object = [ordered]@{}
        foreach ($Property in ($Value.PSObject.Properties | Sort-Object Name)) {
            $Object[$Property.Name] = ConvertTo-CanonicalValue $Property.Value
        }
        return $Object
    }
    if ($Value -is [array]) {
        return ,@(foreach ($Item in $Value) { ConvertTo-CanonicalValue $Item })
    }
    return $Value
}

function Get-CanonicalJson {
    param($Value)
    ConvertTo-Json -InputObject (ConvertTo-CanonicalValue $Value) -Depth 32 -Compress
}

function New-Counters {
    $Counters = [ordered]@{}
    foreach ($Field in $CounterFields) { $Counters[$Field] = [decimal]0 }
    return $Counters
}

function Get-ByteCounter {
    param($Job, [string]$Field, [string]$File)
    $Value = $Job.$Field
    if ($null -eq $Value -or $Value -is [string] -or $Value -is [bool] -or
        $Value -is [array] -or $Value -is [pscustomobject]) {
        throw "Missing/non-numeric counter '$Field' for job '$($Job.FileId)' in $File"
    }
    if ($Value -is [double] -and [math]::Abs($Value) -ge 9007199254740992) {
        throw "Floating-point counter '$Field' exceeds exact integer precision in $File; retain integer JSON byte counters."
    }
    $Number = [decimal]$Value
    if ($Number -lt 0 -or $Number -gt [long]::MaxValue -or [decimal]::Truncate($Number) -ne $Number) {
        throw "Invalid byte counter '$Field' for job '$($Job.FileId)' in $File"
    }
    return $Number
}

function Get-PolicyValues {
    param($Policies, [string]$Source)
    $Values = [ordered]@{}
    foreach ($Property in ($Policies.PSObject.Properties | Sort-Object Name)) {
        if ($Property.Name.StartsWith("${Source}_", [StringComparison]::OrdinalIgnoreCase)) {
            $Values[$Property.Name] = $Property.Value
        }
    }
    return $Values
}

try {
    $InputDirectory = (Resolve-Path -LiteralPath $InputDirectory).ProviderPath
    if (-not (Test-Path -LiteralPath $InputDirectory -PathType Container)) { throw 'InputDirectory is not a directory.' }
    $Files = @(Get-ChildItem -LiteralPath $InputDirectory -Filter 'DO-*.json' -File -Recurse:$Recurse | Sort-Object FullName)
    if ($Files.Count -eq 0) { throw "No DO-*.json snapshots found in $InputDirectory" }
    Write-Verbose "Input: $InputDirectory; files: $($Files.Count); recursive: $Recurse"
    $Snapshots = [Collections.Generic.List[object]]::new()
    $ById = @{}
    $Duplicates = [Collections.Generic.List[object]]::new()
    $DeviceNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $SerialNumbers = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $UseDateKind = (Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')
    foreach ($File in $Files) {
        try {
            $Text = Get-Content -LiteralPath $File.FullName -Raw -Encoding UTF8
            $Data = if ($UseDateKind) { $Text | ConvertFrom-Json -DateKind String } else { $Text | ConvertFrom-Json }
            if ($Data -isnot [pscustomobject] -or $Data.SchemaVersion -ne '1.0.0') {
                throw 'Expected one collector snapshot object with SchemaVersion 1.0.0.'
            }
            if ($Data.DeviceName -isnot [string] -or [string]::IsNullOrWhiteSpace($Data.DeviceName)) { throw 'Missing DeviceName.' }
            $null = $DeviceNames.Add($Data.DeviceName.Trim())
            if (-not [string]::IsNullOrWhiteSpace([string]$Data.SerialNumber) -and $Data.SerialNumber -ne 'Unknown') {
                $null = $SerialNumbers.Add(([string]$Data.SerialNumber).Trim())
            }
            $Id = [Guid]::Empty
            if (-not [Guid]::TryParse([string]$Data.SnapshotId, [ref]$Id)) { throw 'Invalid SnapshotId.' }
            $IdText = $Id.ToString('N')
            if ($Data.CollectedAt -is [DateTime]) {
                if ($Data.CollectedAt.Kind -eq [DateTimeKind]::Unspecified) { throw 'Invalid CollectedAt; timezone required.' }
                $Time = [DateTimeOffset]::new($Data.CollectedAt.ToUniversalTime())
            } else {
                $Time = [DateTimeOffset]::MinValue
                if ([string]$Data.CollectedAt -notmatch '(Z|[+-]\d{2}:\d{2})$' -or
                    -not [DateTimeOffset]::TryParse([string]$Data.CollectedAt, [Globalization.CultureInfo]::InvariantCulture,
                        [Globalization.DateTimeStyles]::None, [ref]$Time)) { throw 'Invalid CollectedAt; timezone required.' }
            }
            if ($Data.Jobs -isnot [array] -or $Data.JobCount -ne $Data.Jobs.Count) { throw 'Jobs must be an array matching JobCount.' }
            if ($Data.Policies -isnot [pscustomobject] -or $Data.PerfSnap -isnot [pscustomobject]) {
                throw 'Policies and PerfSnap must be JSON objects.'
            }
            if ($Data.CollectionStatus -notin @('Complete', 'Partial') -or $Data.CollectionErrors -isnot [array] -or
                (($Data.CollectionErrors.Count -gt 0) -ne ($Data.CollectionStatus -eq 'Partial'))) {
                throw 'Invalid CollectionStatus/CollectionErrors.'
            }
            foreach ($Issue in $Data.CollectionErrors) {
                if ([string]::IsNullOrWhiteSpace([string]$Issue.Stage) -or
                    [string]::IsNullOrWhiteSpace([string]$Issue.Message)) { throw 'Invalid collection error entry.' }
            }
            $JobIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($Job in $Data.Jobs) {
                if ($Job -isnot [pscustomobject] -or $Job.FileId -isnot [string] -or
                    [string]::IsNullOrWhiteSpace($Job.FileId) -or -not $JobIds.Add($Job.FileId)) {
                    throw 'Jobs must have nonempty, distinct FileId values within a snapshot.'
                }
                foreach ($Field in $CounterFields) { $null = Get-ByteCounter $Job $Field $File.FullName }
            }
            $Canonical = Get-CanonicalJson $Data
            if ($ById.ContainsKey($IdText)) {
                if ($ById[$IdText].Canonical -ne $Canonical) { throw "Conflicting content for SnapshotId $IdText" }
                $Duplicates.Add([pscustomobject]@{ Path = $File.FullName; SnapshotId = $IdText; OriginalPath = $ById[$IdText].Path })
                Write-Verbose "Duplicate snapshot excluded: $($File.FullName); ID: $IdText"
                continue
            }
            $Entry = [pscustomobject]@{ Data = $Data; Time = $Time.ToUniversalTime(); Path = $File.FullName; Id = $IdText; Canonical = $Canonical }
            $ById[$IdText] = $Entry
            $Snapshots.Add($Entry)
            Write-Verbose "Validated: $($File.FullName); ID: $IdText; jobs: $($Data.JobCount); status: $($Data.CollectionStatus)"
        } catch {
            throw "Invalid snapshot '$($File.FullName)': $($_.Exception.Message)"
        }
    }
    if ($DeviceNames.Count -ne 1 -or $SerialNumbers.Count -gt 1) {
        throw 'Input contains multiple devices or serial numbers. Analyze each machine separately.'
    }
    $Ordered = @($Snapshots | Sort-Object Time, Id)
    $JobsById = @{}
    $Timeline = [Collections.Generic.List[object]]::new()
    $Resets = [Collections.Generic.List[object]]::new()
    $Gaps = [Collections.Generic.List[object]]::new()
    $CollectionIssues = [Collections.Generic.List[object]]::new()
    $PolicyChanges = [Collections.Generic.List[object]]::new()
    $PolicyState = @{}
    $PolicyBaselines = [Collections.Generic.List[object]]::new()
    $PolicyAvailability = [ordered]@{}
    $PerfHistory = [Collections.Generic.List[object]]::new()
    $PerfStats = @{}
    $PreviousTime = $null
    $IntervalSum = [double]0
    $MaxInterval = [double]0
    foreach ($Snapshot in $Ordered) {
        $Data = $Snapshot.Data
        $At = $Snapshot.Time.ToString('o')
        if ($null -ne $PreviousTime) {
            $Minutes = ($Snapshot.Time - $PreviousTime).TotalMinutes
            if ($Minutes -eq 0) { throw "Distinct snapshots share CollectedAt $At; counter order is ambiguous." }
            $IntervalSum += $Minutes
            $MaxInterval = [math]::Max($MaxInterval, $Minutes)
            if ($Minutes -gt $ExpectedIntervalMinutes * 1.5) {
                $Gaps.Add([pscustomobject]@{ From = $PreviousTime.ToString('o'); To = $At; Minutes = $Minutes })
            }
        }
        $PreviousTime = $Snapshot.Time
        foreach ($Issue in $Data.CollectionErrors) {
            $CollectionIssues.Add([pscustomobject]@{ SnapshotId = $Snapshot.Id; CollectedAt = $At; Stage = $Issue.Stage; Message = $Issue.Message })
        }
        $SnapshotCounters = New-Counters
        foreach ($Job in $Data.Jobs) {
            $First = -not $JobsById.ContainsKey($Job.FileId)
            if ($First) {
                $JobsById[$Job.FileId] = [pscustomobject]@{
                    FileId = $Job.FileId; FirstSeen = $At; LastSeen = $At; ObservationCount = 0; ResetCount = 0
                    FirstObservedCounters = New-Counters; SubsequentObservedCounters = New-Counters
                    ObservedCounters = New-Counters; PreviousCounters = New-Counters; LatestJob = $Job
                    StatusHistory = [Collections.Generic.List[object]]::new()
                }
            }
            $State = $JobsById[$Job.FileId]
            $ResetFields = [Collections.Generic.List[object]]::new()
            foreach ($Field in $CounterFields) {
                $Current = Get-ByteCounter $Job $Field $Snapshot.Path
                $Previous = $State.PreviousCounters[$Field]
                $Delta = if ($First -or $Current -lt $Previous) { $Current } else { $Current - $Previous }
                if (-not $First -and $Current -lt $Previous) {
                    $ResetFields.Add([pscustomobject]@{ Field = $Field; PreviousValue = $Previous; CurrentValue = $Current })
                }
                if ($First) { $State.FirstObservedCounters[$Field] = $Current } else { $State.SubsequentObservedCounters[$Field] += $Delta }
                $State.ObservedCounters[$Field] += $Delta
                $State.PreviousCounters[$Field] = $Current
                $SnapshotCounters[$Field] += $Current
            }
            if ($ResetFields.Count -gt 0) {
                $State.ResetCount++
                $Resets.Add([pscustomobject]@{ FileId = $Job.FileId; CollectedAt = $At; Fields = @($ResetFields.ToArray()) })
            }
            if ($First -or $State.LatestJob.Status -ne $Job.Status) {
                $State.StatusHistory.Add([pscustomobject]@{ CollectedAt = $At; Status = $Job.Status })
            }
            $State.ObservationCount++
            $State.LastSeen = $At
            $State.LatestJob = $Job
        }
        $Timeline.Add([pscustomobject]@{
            SnapshotId = $Snapshot.Id; CollectedAt = $At; JobCount = $Data.JobCount
            CollectionStatus = $Data.CollectionStatus; CollectorVersion = $Data.CollectorVersion
            CurrentJobCounters = $SnapshotCounters; SourcePath = $Snapshot.Path
        })
        foreach ($Source in @('GPO', 'MDM', 'Local')) {
            $Failed = @($Data.CollectionErrors | Where-Object Stage -eq "Policies:$Source").Count -gt 0
            $PolicyAvailability[$Source] = if ($Failed) { 'Unavailable' } else { 'Known' }
            if ($Failed) { continue }
            $Values = Get-PolicyValues $Data.Policies $Source
            if ($PolicyState.ContainsKey($Source)) {
                $Old = $PolicyState[$Source].Values
                $Keys = @(@($Old.Keys) + @($Values.Keys) | Sort-Object -Unique)
                foreach ($Key in $Keys) {
                    $Had = $Old.Contains($Key)
                    $Has = $Values.Contains($Key)
                    if ($Had -and $Has -and (Get-CanonicalJson $Old[$Key]) -eq (Get-CanonicalJson $Values[$Key])) { continue }
                    $Change = if (-not $Had) { 'Added' } elseif (-not $Has) { 'Removed' } else { 'Changed' }
                    $PolicyChanges.Add([pscustomobject]@{
                        CollectedAt = $At; Source = $Source; Name = $Key; Change = $Change
                        PreviousValue = $Old[$Key]; CurrentValue = $Values[$Key]
                    })
                }
            } else {
                $PolicyBaselines.Add([pscustomobject]@{ Source = $Source; CollectedAt = $At; Values = $Values })
            }
            $PolicyState[$Source] = [pscustomobject]@{ LastSuccessfulAt = $At; Values = $Values }
        }
        $PerfFailed = @($Data.CollectionErrors | Where-Object Stage -eq 'PerfSnap').Count -gt 0
        $PerfHistory.Add([pscustomobject]@{ CollectedAt = $At; Available = -not $PerfFailed; Values = $Data.PerfSnap })
        if (-not $PerfFailed) {
            foreach ($Property in $Data.PerfSnap.PSObject.Properties) {
                $Value = $Property.Value
                if ($null -eq $Value -or $Property.Name -eq 'DownloadMode') { continue }
                if ($Value -isnot [ValueType] -or $Value -is [bool] -or $Value -is [DateTime]) {
                    throw "Non-numeric performance property '$($Property.Name)' in $($Snapshot.Path)"
                }
                $Number = [decimal]$Value
                if (-not $PerfStats.ContainsKey($Property.Name)) {
                    $PerfStats[$Property.Name] = [pscustomobject]@{ SampleCount = 0; Minimum = $Number; Maximum = $Number; Sum = [decimal]0; LastValue = $Number; LastCollectedAt = $At }
                }
                $Stat = $PerfStats[$Property.Name]
                $Stat.SampleCount++; $Stat.Sum += $Number
                $Stat.Minimum = [math]::Min([decimal]$Stat.Minimum, $Number)
                $Stat.Maximum = [math]::Max([decimal]$Stat.Maximum, $Number)
                $Stat.LastValue = $Number; $Stat.LastCollectedAt = $At
            }
        }
    }
    $AllJobs = @($JobsById.Values | Sort-Object FileId)
    $Observed = New-Counters; $Initial = New-Counters; $Subsequent = New-Counters
    foreach ($Job in $AllJobs) {
        foreach ($Field in $CounterFields) {
            $Observed[$Field] += $Job.ObservedCounters[$Field]
            $Initial[$Field] += $Job.FirstObservedCounters[$Field]
            $Subsequent[$Field] += $Job.SubsequentObservedCounters[$Field]
        }
        $Job.PSObject.Properties.Remove('PreviousCounters')
        $Job.StatusHistory = @($Job.StatusHistory.ToArray())
    }
    $Accounted = $Observed.BytesFromPeers + $Observed.BytesFromHttp + $Observed.BytesFromCacheServer
    $PerfSummary = [ordered]@{}
    foreach ($Name in ($PerfStats.Keys | Sort-Object)) {
        $Stat = $PerfStats[$Name]
        $PerfSummary[$Name] = [pscustomobject]@{
            SampleCount = $Stat.SampleCount; Minimum = $Stat.Minimum; Maximum = $Stat.Maximum
            Average = $Stat.Sum / $Stat.SampleCount; LastValue = $Stat.LastValue; LastCollectedAt = $Stat.LastCollectedAt
        }
    }
    $Distributions = [ordered]@{}
    foreach ($Field in @('Status', 'DownloadMode', 'PredefinedCallerApplication')) {
        $Distributions[$Field] = @($AllJobs | Group-Object { [string]$_.LatestJob.$Field } |
            Sort-Object Count -Descending | ForEach-Object { [pscustomobject]@{ Value = $_.Name; UniqueJobs = $_.Count } })
    }
    $Latest = $Ordered[-1].Data
    $Report = [pscustomobject][ordered]@{
        ReportSchemaVersion = '1.0.0'; AnalyzerVersion = $AnalyzerVersion; GeneratedAt = [DateTime]::UtcNow.ToString('o')
        Device = [ordered]@{
            DeviceName = $Latest.DeviceName; SerialNumber = @($SerialNumbers | Sort-Object) | Select-Object -First 1
            LatestContext = [ordered]@{
                OSVersion = $Latest.OSVersion; OSBuild = $Latest.OSBuild; Domain = $Latest.Domain
                Manufacturer = $Latest.Manufacturer; Model = $Latest.Model
            }
        }
        Summary = [ordered]@{
            InputFileCount = $Files.Count; SnapshotCount = $Ordered.Count; DuplicateFileCount = $Duplicates.Count
            FirstCollectedAt = $Ordered[0].Time.ToString('o'); LastCollectedAt = $Ordered[-1].Time.ToString('o')
            UniqueJobCount = $AllJobs.Count; LatestJobCount = $Latest.JobCount
            PartialSnapshotCount = @($Ordered | Where-Object { $_.Data.CollectionStatus -eq 'Partial' }).Count
            ExpectedIntervalMinutes = $ExpectedIntervalMinutes
            AverageIntervalMinutes = if ($Ordered.Count -gt 1) { $IntervalSum / ($Ordered.Count - 1) } else { $null }
            MaximumIntervalMinutes = if ($Ordered.Count -gt 1) { $MaxInterval } else { $null }
        }
        Traffic = [ordered]@{
            ObservedCounters = $Observed; FirstObservedCounters = $Initial; SubsequentObservedCounters = $Subsequent
            AccountedDownloadSourceBytes = $Accounted
            PeerShareOfAccountedSourcesPct = if ($Accounted -gt 0) { [math]::Round(100 * $Observed.BytesFromPeers / $Accounted, 2) } else { $null }
            PeerAndCacheShareOfAccountedSourcesPct = if ($Accounted -gt 0) { [math]::Round(100 * ($Observed.BytesFromPeers + $Observed.BytesFromCacheServer) / $Accounted, 2) } else { $null }
            UploadedBytes = $Observed.BytesToLanPeers + $Observed.BytesToGroupPeers + $Observed.BytesToInternetPeers + $Observed.BytesToLinkLocalPeers
        }
        Jobs = $AllJobs
        TopJobsByObservedDownload = @($AllJobs | Sort-Object { $_.ObservedCounters.TotalBytesDownloaded } -Descending | Select-Object -First 10 |
            ForEach-Object { [pscustomobject]@{ FileId = $_.FileId; DownloadedBytes = $_.ObservedCounters.TotalBytesDownloaded; Status = $_.LatestJob.Status; CallerApplication = $_.LatestJob.PredefinedCallerApplication } })
        JobDistributions = $Distributions
        Policies = [ordered]@{
            LatestSnapshot = $Latest.Policies; LatestSnapshotAvailability = $PolicyAvailability
            LatestKnownBySource = $PolicyState; Baselines = @($PolicyBaselines.ToArray()); Changes = @($PolicyChanges.ToArray())
        }
        Performance = [ordered]@{ Summary = $PerfSummary; Samples = @($PerfHistory.ToArray()) }
        Timeline = @($Timeline.ToArray())
        DataQuality = [ordered]@{
            DuplicateFiles = @($Duplicates.ToArray()); CounterResets = @($Resets.ToArray())
            SamplingGaps = @($Gaps.ToArray()); CollectionErrors = @($CollectionIssues.ToArray())
        }
        Interpretation = @(
            'Counters are deduplicated by FileId, not summed across snapshots.'
            'ObservedCounters = first observed counters per job + subsequent positive deltas; a decreasing counter contributes its new value and is flagged as a reset.'
            'FirstObservedCounters can include traffic before the analysis window. SubsequentObservedCounters exclude each job''s first sample.'
            'These are observed counters, not an exact network-traffic ledger: jobs/resets between samples and repeated downloads with unchanged counters cannot be recovered.'
            'Peer subtypes are subsets of BytesFromPeers; do not add them to that total. Performance averages are unweighted sample averages, never traffic sums.'
            'A failed policy source retains its last known values with a timestamp; it does not imply removal. GPO/MDM precedence is not inferred.'
        )
    }
    if ($OutputPath) {
        $OutputPath = [IO.Path]::GetFullPath($OutputPath)
        $Parent = Split-Path -Path $OutputPath -Parent
        if (-not (Test-Path -LiteralPath $Parent -PathType Container)) { throw "Report parent directory does not exist: $Parent" }
        if (Test-Path -LiteralPath $OutputPath) { throw "Report already exists; choose a new OutputPath: $OutputPath" }
        if ([IO.Path]::GetFileName($OutputPath) -like 'DO-*.json') { throw 'Report name must not match the collector DO-*.json input pattern.' }
        $TemporaryPath = Join-Path $Parent ('DOAnalysis-' + [Guid]::NewGuid().ToString('N') + '.tmp')
        $Bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Report | ConvertTo-Json -Depth 40))
        $Stream = [IO.FileStream]::new($TemporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        $OwnsTemporaryFile = $true
        try { $Stream.Write($Bytes, 0, $Bytes.Length); $Stream.Flush($true) } finally { $Stream.Dispose() }
        [IO.File]::Move($TemporaryPath, $OutputPath)
        $TemporaryPath = $null
        Write-Verbose "JSON report saved: $OutputPath; bytes: $($Bytes.Length)"
    }
    Write-Verbose "Analysis complete: device $($Report.Device.DeviceName); snapshots $($Ordered.Count); unique jobs $($AllJobs.Count); resets $($Resets.Count); gaps $($Gaps.Count)"
    Write-Output $Report
    exit 0
} catch {
    if ($OwnsTemporaryFile -and $TemporaryPath -and [IO.File]::Exists($TemporaryPath)) {
        try { [IO.File]::Delete($TemporaryPath) } catch { Write-Warning "Could not clean incomplete report ${TemporaryPath}: $($_.Exception.Message)" }
    }
    Write-Error "DO snapshot analysis failed: $($_.Exception.Message)" -ErrorAction Continue
    exit 1
}
