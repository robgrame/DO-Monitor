#requires -Version 5.1
<#
.SYNOPSIS
    Saves Delivery Optimization telemetry locally, without Azure or network calls.
.DESCRIPTION
    Writes one UTF-8 JSON snapshot per run in a dedicated, restricted directory.
    Existing snapshots are never overwritten or automatically deleted.
    Exit codes: 0 = complete, 1 = failed, 2 = partial snapshot saved.
.PARAMETER OutputDirectory
    Dedicated directory on a fixed local drive. Its parent must already exist.
    An existing directory must have a protected ACL granting access only to the
    current account, SYSTEM and Administrators.
.NOTES
    Version: 2.7.4
    Run in 64-bit Windows PowerShell 5.1 or PowerShell 7, preferably as SYSTEM
    or an administrator. No certificate, Azure module or Intune license required.
#>
[CmdletBinding()]
param(
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory = "$env:ProgramData\DO-Monitor-Local"
)

$ErrorActionPreference = 'Stop'
$CollectorVersion = '2.7.4'
$TemporaryPath = $null
$OwnsTemporaryFile = $false
$StorageHandles = [Collections.Generic.List[IDisposable]]::new()

function Lock-StorageDirectory {
    param([string]$Path)

    $Handle = [DOMonitor.LocalStorage.NativeMethods]::CreateFile(
        $Path, 2147483648, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
    if ($Handle.IsInvalid) {
        $Code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        $Handle.Dispose()
        throw [ComponentModel.Win32Exception]::new($Code, "Cannot lock storage directory: $Path")
    }
    # No FILE_SHARE_DELETE: pin each ancestor before validating its next child.
    $StorageHandles.Add($Handle)
    $Item = Get-Item -LiteralPath $Path -Force
    if (-not $Item.PSIsContainer -or
        ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Storage path contains a file or reparse point: $Path"
    }
}

function Initialize-LocalStore {
    param([string]$Path)

    if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.IndexOf(':', 2) -ge 0) {
        throw 'OutputDirectory must be an absolute local drive path, without alternate data streams.'
    }
    $FullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $Root = [IO.Path]::GetPathRoot($FullPath)
    if ($FullPath -eq $Root.TrimEnd('\') -or
        ([IO.DriveInfo]::new($Root)).DriveType -ne [IO.DriveType]::Fixed) {
        throw 'OutputDirectory must be a dedicated directory on a fixed local drive, not a drive root.'
    }
    $Parent = Split-Path -Path $FullPath -Parent
    if (-not (Test-Path -LiteralPath $Parent -PathType Container)) {
        throw "OutputDirectory parent does not exist: $Parent"
    }
    $CurrentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $AllowedSids = @($CurrentSid.Value, 'S-1-5-18', 'S-1-5-32-544')
    $Ancestors = [Collections.Generic.List[string]]::new()
    $Ancestor = $Parent
    while ($Ancestor) {
        $Ancestors.Add($Ancestor)
        $Ancestor = Split-Path -Path $Ancestor -Parent
    }
    for ($Index = $Ancestors.Count - 1; $Index -ge 0; $Index--) {
        Lock-StorageDirectory -Path $Ancestors[$Index]
    }
    if (-not (Test-Path -LiteralPath $FullPath)) {
        $ParentAcl = Get-Acl -LiteralPath $Parent
        if ($ParentAcl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $AllowedSids) {
            throw "Storage parent has an untrusted owner: $Parent"
        }
        $Acl = [Security.AccessControl.DirectorySecurity]::new()
        $Acl.SetAccessRuleProtection($true, $false)
        $Acl.SetOwner($CurrentSid)
        foreach ($Sid in ($AllowedSids | Select-Object -Unique)) {
            $Rule = [Security.AccessControl.FileSystemAccessRule]::new(
                [Security.Principal.SecurityIdentifier]::new($Sid),
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow)
            $Acl.AddAccessRule($Rule)
        }
        # Create with the restricted ACL immediately, before any telemetry is written.
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            $null = [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($FullPath), $Acl)
        } else {
            $null = [IO.Directory]::CreateDirectory($FullPath, $Acl)
        }
    }
    Lock-StorageDirectory -Path $FullPath
    # Creation may have lost a race to another writer: validate the actual directory.
    $Acl = Get-Acl -LiteralPath $FullPath
    $Owner = $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value
    $Rules = $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])
    if (-not $Acl.AreAccessRulesProtected -or $Owner -notin $AllowedSids) {
        throw "Storage directory has an untrusted owner or inherited permissions: $FullPath"
    }
    foreach ($Rule in $Rules) {
        if ($Rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $Rule.IdentityReference.Value -notin $AllowedSids) {
            throw "Storage directory grants access to another account: $FullPath"
        }
    }
    Write-Verbose "Local storage: $FullPath; writer SID: $($CurrentSid.Value); allowed: $($AllowedSids -join ', ')"
    return $FullPath
}

try {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit PowerShell on Windows to access Delivery Optimization and the machine policy registry.'
    }
    if (-not ('DOMonitor.LocalStorage.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace DOMonitor.LocalStorage {
    public static class NativeMethods {
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(
            string path, uint access, uint share, IntPtr security,
            uint disposition, uint flags, IntPtr template);
    }
}
'@ -ErrorAction Stop
    }
    $OutputDirectory = Initialize-LocalStore -Path $OutputDirectory
    $CollectionErrors = [Collections.Generic.List[object]]::new()
    $CollectedAt = [DateTime]::UtcNow
    $Payload = [ordered]@{
        SchemaVersion = '1.0.0'
        CollectorVersion = $CollectorVersion
        SnapshotId = [Guid]::NewGuid().ToString('N')
        DeviceName = $env:COMPUTERNAME
        CollectedAt = $CollectedAt.ToString('o')
        CollectionStatus = 'Complete'
        CollectionErrors = @()
        OSVersion = $null
        OSBuild = $null
        SerialNumber = $null
        Domain = $null
        Manufacturer = $null
        Model = $null
        JobCount = 0
        TotalFromPeers = [long]0
        TotalFromHttp = [long]0
        TotalFromCache = [long]0
        TotalUploaded = [long]0
        Jobs = @()
        PerfSnap = @{}
        Policies = @{}
    }
    foreach ($Class in @('Win32_OperatingSystem', 'Win32_BIOS', 'Win32_ComputerSystem')) {
        try {
            $Info = Get-CimInstance -ClassName $Class -ErrorAction Stop
            if (-not $Info) { throw "No instance returned for $Class." }
            switch ($Class) {
                'Win32_OperatingSystem' { $Payload.OSVersion = $Info.Version; $Payload.OSBuild = $Info.BuildNumber }
                'Win32_BIOS' { $Payload.SerialNumber = $Info.SerialNumber }
                'Win32_ComputerSystem' {
                    $Payload.Domain = $Info.Domain
                    $Payload.Manufacturer = $Info.Manufacturer
                    $Payload.Model = $Info.Model
                }
            }
            Write-Verbose "Device information collected from $Class"
        } catch {
            $CollectionErrors.Add(@{ Stage = $Class; Message = $_.Exception.Message })
            Write-Warning "Device information failed ($Class): $($_.Exception.Message)"
        }
    }

    $ByteFields = @(
        'FileSize', 'FileSizeInCache', 'TotalBytesDownloaded', 'BytesFromPeers',
        'BytesFromHttp', 'BytesFromCacheServer', 'BytesFromLanPeers', 'BytesFromGroupPeers',
        'BytesFromInternetPeers', 'BytesFromLinkLocalPeers', 'BytesToLanPeers',
        'BytesToGroupPeers', 'BytesToInternetPeers', 'BytesToLinkLocalPeers'
    )
    $ConnectionFields = @(
        'HttpConnectionCount', 'LanConnectionCount', 'GroupConnectionCount',
        'InternetConnectionCount', 'LinkLocalConnectionCount', 'CacheServerConnectionCount', 'NumPeers'
    )
    $Jobs = @(
        foreach ($Job in @(Get-DeliveryOptimizationStatus -ErrorAction Stop)) {
            $Record = [ordered]@{ FileId = [string]$Job.FileId }
            foreach ($Field in $ByteFields) { $Record[$Field] = [long]$Job.$Field }
            foreach ($Field in $ConnectionFields) { $Record[$Field] = [int]$Job.$Field }
            foreach ($Field in @('Status', 'Priority', 'DownloadMode', 'SourceURL', 'CacheHost', 'PredefinedCallerApplication')) {
                $Record[$Field] = [string]$Job.$Field
            }
            $Record.PercentPeerCaching = [double]$Job.PercentPeerCaching
            $Record.DownloadDuration = if ($Job.DownloadDuration) { $Job.DownloadDuration.TotalSeconds } else { 0 }
            $Record.ExpireOn = if ($Job.ExpireOn) { $Job.ExpireOn.ToString('o') } else { '' }
            $Record.IsPinned = [bool]$Job.IsPinned
            $Payload.TotalFromPeers += $Record.BytesFromPeers
            $Payload.TotalFromHttp += $Record.BytesFromHttp
            $Payload.TotalFromCache += $Record.BytesFromCacheServer
            $Payload.TotalUploaded += $Record.BytesToLanPeers + $Record.BytesToGroupPeers +
                $Record.BytesToInternetPeers + $Record.BytesToLinkLocalPeers
            $Record
        }
    )
    $Payload.Jobs = $Jobs
    $Payload.JobCount = $Jobs.Count
    Write-Verbose "Get-DeliveryOptimizationStatus: $($Jobs.Count) jobs; peer bytes: $($Payload.TotalFromPeers); HTTP bytes: $($Payload.TotalFromHttp)"

    try {
        $Perf = Get-DeliveryOptimizationPerfSnap -ErrorAction Stop
        if (-not $Perf) { throw 'No performance snapshot returned.' }
        foreach ($Field in @(
            'DownloadMode', 'Files', 'FilesDownloaded', 'FilesUploaded', 'TotalBytesDownloaded',
            'TotalBytesUploaded', 'NumberOfPeers', 'CacheSizeBytes', 'TotalDiskBytes',
            'AvailableDiskBytes', 'CpuUsagePct', 'MemUsageKB', 'DownlinkBps', 'DownlinkUsageBps',
            'UplinkBps', 'UplinkUsageBps', 'BackgroundDownloadRatePct', 'ForegroundDownloadRatePct',
            'UploadRatePct', 'BackgroundDownloadCount', 'ForegroundDownloadCount',
            'BackgroundDownloadsPending', 'ForegroundDownloadsPending', 'UploadCount',
            'AverageDownloadSize', 'AverageUploadSize', 'LanConnections', 'GroupConnections',
            'InternetConnections', 'LinkLocalConnections', 'CdnConnections', 'CacheHostConnections'
        )) {
            $Payload.PerfSnap[$Field] = $Perf.$Field
        }
        Write-Verbose 'Performance snapshot collected from Get-DeliveryOptimizationPerfSnap'
    } catch {
        $CollectionErrors.Add(@{ Stage = 'PerfSnap'; Message = $_.Exception.Message })
        Write-Warning "DO performance collection failed: $($_.Exception.Message)"
    }

    $PolicyPaths = [ordered]@{
        GPO = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'
        MDM = 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization'
        Local = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config'
    }
    foreach ($Source in $PolicyPaths.Keys) {
        $Path = $PolicyPaths[$Source]
        try {
            if (Test-Path -LiteralPath $Path -ErrorAction Stop) {
                $Properties = Get-ItemProperty -LiteralPath $Path -ErrorAction Stop
                foreach ($Property in $Properties.PSObject.Properties) {
                    if ($Property.Name -notmatch '^PS') {
                        $Payload.Policies["${Source}_$($Property.Name)"] = $Property.Value
                    }
                }
                Write-Verbose "Policies collected: $Source from $Path"
            } else {
                Write-Verbose "Policy key not configured: $Source at $Path"
            }
        } catch {
            $CollectionErrors.Add(@{ Stage = "Policies:$Source"; Message = $_.Exception.Message })
            Write-Warning "Policy collection failed ($Path): $($_.Exception.Message)"
        }
    }
    if ($CollectionErrors.Count -gt 0) { $Payload.CollectionStatus = 'Partial' }
    $Payload.CollectionErrors = @($CollectionErrors.ToArray())
    $Json = $Payload | ConvertTo-Json -Depth 8 -Compress
    $Name = 'DO-{0}-{1}.json' -f $CollectedAt.ToString('yyyyMMddTHHmmssfffffffZ'), $Payload.SnapshotId
    $FinalPath = Join-Path -Path $OutputDirectory -ChildPath $Name
    $TemporaryPath = "$FinalPath.tmp"
    $Bytes = [Text.UTF8Encoding]::new($false).GetBytes($Json)
    $Stream = [IO.FileStream]::new($TemporaryPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $OwnsTemporaryFile = $true
    try {
        $Stream.Write($Bytes, 0, $Bytes.Length)
        $Stream.Flush($true)
    } finally {
        $Stream.Dispose()
    }
    # Consumers only see .json after a fully flushed write on the same volume.
    [IO.File]::Move($TemporaryPath, $FinalPath)
    $TemporaryPath = $null
    Write-Output "DO snapshot saved: $FinalPath; status: $($Payload.CollectionStatus); jobs: $($Jobs.Count); bytes: $($Bytes.Length); version: $CollectorVersion"
    if ($CollectionErrors.Count -gt 0) { exit 2 }
    exit 0
} catch {
    Write-Output "DO local collection failed: $($_.Exception.Message)"
    if ($OwnsTemporaryFile -and $TemporaryPath -and [IO.File]::Exists($TemporaryPath)) {
        try {
            [IO.File]::Delete($TemporaryPath)
        } catch {
            Write-Warning "Could not remove incomplete snapshot ${TemporaryPath}: $($_.Exception.Message)"
        }
    }
    exit 1
} finally {
    for ($Index = $StorageHandles.Count - 1; $Index -ge 0; $Index--) {
        $StorageHandles[$Index].Dispose()
    }
}
