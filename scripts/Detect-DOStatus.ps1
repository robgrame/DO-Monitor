<#
.SYNOPSIS
    Intune Proactive Remediation - Detection Script
    Collects Delivery Optimization telemetry and policies from the client.
.DESCRIPTION
    Gathers all DO job details from Get-DeliveryOptimizationStatus,
    DO performance counters from Get-DeliveryOptimizationPerfSnap,
    and DO policies from registry (GPO + MDM).
    POSTs everything to the DOIngest Azure Function endpoint using client certificate (mTLS).
    Returns compliant (exit 0) on success, non-compliant (exit 1) on failure.
.NOTES
    Configure $FunctionUrl and $CertThumbprint before deployment.
    The client certificate must be installed in LocalMachine\My store.
#>

# === CONFIGURATION ===
$FunctionUrl = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/DOIngest"
$CertThumbprint = "<YOUR-CLIENT-CERT-THUMBPRINT>"

# === LOAD CLIENT CERTIFICATE ===
try {
    $Certificate = Get-ChildItem -Path "Cert:\LocalMachine\My\$CertThumbprint" -ErrorAction Stop
} catch {
    Write-Output "Non-Compliant - Client certificate not found: $CertThumbprint"
    exit 1
}

# === COLLECT DEVICE INFO ===
try {
    $ComputerName = $env:COMPUTERNAME
    $OS = Get-CimInstance -ClassName Win32_OperatingSystem
    $BIOS = Get-CimInstance -ClassName Win32_BIOS
    $CS = Get-CimInstance -ClassName Win32_ComputerSystem
    $OSVersion = $OS.Version
    $OSBuild = $OS.BuildNumber
    $SerialNumber = $BIOS.SerialNumber
    $Domain = $CS.Domain
    $Manufacturer = $CS.Manufacturer
    $Model = $CS.Model
} catch {
    $ComputerName = $env:COMPUTERNAME
    $OSVersion = "Unknown"; $OSBuild = "Unknown"
    $SerialNumber = "Unknown"; $Domain = "Unknown"
    $Manufacturer = "Unknown"; $Model = "Unknown"
}

# === COLLECT DO JOBS (all fields) ===
$Jobs = @()
try {
    $DOStatus = Get-DeliveryOptimizationStatus -ErrorAction Stop
    if ($DOStatus -and $DOStatus.Count -gt 0) {
        foreach ($Job in $DOStatus) {
            $Jobs += @{
                FileId                   = $Job.FileId
                FileSize                 = [long]$Job.FileSize
                FileSizeInCache          = [long]$Job.FileSizeInCache
                TotalBytesDownloaded     = [long]$Job.TotalBytesDownloaded
                Status                   = $Job.Status.ToString()
                Priority                 = $Job.Priority.ToString()
                DownloadMode             = $Job.DownloadMode.ToString()
                PercentPeerCaching       = $Job.PercentPeerCaching
                # Bytes downloaded by source
                BytesFromPeers           = [long]$Job.BytesFromPeers
                BytesFromHttp            = [long]$Job.BytesFromHttp
                BytesFromCacheServer     = [long]$Job.BytesFromCacheServer
                BytesFromLanPeers        = [long]$Job.BytesFromLanPeers
                BytesFromGroupPeers      = [long]$Job.BytesFromGroupPeers
                BytesFromInternetPeers   = [long]$Job.BytesFromInternetPeers
                BytesFromLinkLocalPeers  = [long]$Job.BytesFromLinkLocalPeers
                # Bytes uploaded by destination
                BytesToLanPeers          = [long]$Job.BytesToLanPeers
                BytesToGroupPeers        = [long]$Job.BytesToGroupPeers
                BytesToInternetPeers     = [long]$Job.BytesToInternetPeers
                BytesToLinkLocalPeers    = [long]$Job.BytesToLinkLocalPeers
                # Connection counts
                HttpConnectionCount      = [int]$Job.HttpConnectionCount
                LanConnectionCount       = [int]$Job.LanConnectionCount
                GroupConnectionCount     = [int]$Job.GroupConnectionCount
                InternetConnectionCount  = [int]$Job.InternetConnectionCount
                LinkLocalConnectionCount = [int]$Job.LinkLocalConnectionCount
                CacheServerConnectionCount = [int]$Job.CacheServerConnectionCount
                NumPeers                 = [int]$Job.NumPeers
                # Metadata
                SourceURL                = if ($Job.SourceURL) { $Job.SourceURL.ToString() } else { "" }
                CacheHost                = if ($Job.CacheHost) { $Job.CacheHost.ToString() } else { "" }
                PredefinedCallerApplication = if ($Job.PredefinedCallerApplication) { $Job.PredefinedCallerApplication } else { "" }
                DownloadDuration         = if ($Job.DownloadDuration) { $Job.DownloadDuration.TotalSeconds } else { 0 }
                ExpireOn                 = if ($Job.ExpireOn) { $Job.ExpireOn.ToString("o") } else { "" }
                IsPinned                 = [bool]$Job.IsPinned
            }
        }
    }
} catch {
    Write-Output "Error collecting DO status: $($_.Exception.Message)"
    exit 1
}

# === COLLECT DO PERFORMANCE SNAPSHOT ===
$PerfSnap = @{}
try {
    $Perf = Get-DeliveryOptimizationPerfSnap -ErrorAction SilentlyContinue
    if ($Perf) {
        $PerfSnap = @{
            DownloadMode                = $Perf.DownloadMode
            Files                       = [int]$Perf.Files
            FilesDownloaded             = [int]$Perf.FilesDownloaded
            FilesUploaded               = [int]$Perf.FilesUploaded
            TotalBytesDownloaded        = [long]$Perf.TotalBytesDownloaded
            TotalBytesUploaded          = [long]$Perf.TotalBytesUploaded
            NumberOfPeers               = [int]$Perf.NumberOfPeers
            CacheSizeBytes              = [long]$Perf.CacheSizeBytes
            TotalDiskBytes              = [long]$Perf.TotalDiskBytes
            AvailableDiskBytes          = [long]$Perf.AvailableDiskBytes
            CpuUsagePct                 = $Perf.CpuUsagePct
            MemUsageKB                  = [long]$Perf.MemUsageKB
            DownlinkBps                 = [long]$Perf.DownlinkBps
            DownlinkUsageBps            = [long]$Perf.DownlinkUsageBps
            UplinkBps                   = [long]$Perf.UplinkBps
            UplinkUsageBps              = [long]$Perf.UplinkUsageBps
            BackgroundDownloadRatePct   = $Perf.BackgroundDownloadRatePct
            ForegroundDownloadRatePct   = $Perf.ForegroundDownloadRatePct
            UploadRatePct               = $Perf.UploadRatePct
            BackgroundDownloadCount     = [int]$Perf.BackgroundDownloadCount
            ForegroundDownloadCount     = [int]$Perf.ForegroundDownloadCount
            BackgroundDownloadsPending  = [int]$Perf.BackgroundDownloadsPending
            ForegroundDownloadsPending  = [int]$Perf.ForegroundDownloadsPending
            UploadCount                 = [int]$Perf.UploadCount
            AverageDownloadSize         = [long]$Perf.AverageDownloadSize
            AverageUploadSize           = [long]$Perf.AverageUploadSize
            LanConnections              = [int]$Perf.LanConnections
            GroupConnections            = [int]$Perf.GroupConnections
            InternetConnections         = [int]$Perf.InternetConnections
            LinkLocalConnections        = [int]$Perf.LinkLocalConnections
            CdnConnections              = [int]$Perf.CdnConnections
            CacheHostConnections        = [int]$Perf.CacheHostConnections
        }
    }
} catch { }

# === COLLECT DO POLICIES (GPO + MDM) ===
$Policies = @{}
try {
    # GPO policies
    $gpoPath = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization"
    if (Test-Path $gpoPath) {
        $gpoProps = Get-ItemProperty -Path $gpoPath -ErrorAction SilentlyContinue
        $gpoProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $Policies["GPO_$($_.Name)"] = $_.Value
        }
    }

    # MDM policies (Intune)
    $mdmPath = "HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\DeliveryOptimization"
    if (Test-Path $mdmPath) {
        $mdmProps = Get-ItemProperty -Path $mdmPath -ErrorAction SilentlyContinue
        $mdmProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $Policies["MDM_$($_.Name)"] = $_.Value
        }
    }

    # Local DO config
    $localPath = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\DeliveryOptimization\Config"
    if (Test-Path $localPath) {
        $localProps = Get-ItemProperty -Path $localPath -ErrorAction SilentlyContinue
        $localProps.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
            $Policies["Local_$($_.Name)"] = $_.Value
        }
    }
} catch { }

# === BUILD PAYLOAD ===
$TotalPeers = ($Jobs | Measure-Object -Property BytesFromPeers -Sum).Sum
$TotalHttp  = ($Jobs | Measure-Object -Property BytesFromHttp -Sum).Sum
$TotalCache = ($Jobs | Measure-Object -Property BytesFromCacheServer -Sum).Sum
$TotalUploaded = ($Jobs | Measure-Object -Property BytesToLanPeers -Sum).Sum +
                 ($Jobs | Measure-Object -Property BytesToGroupPeers -Sum).Sum +
                 ($Jobs | Measure-Object -Property BytesToInternetPeers -Sum).Sum

$Payload = @{
    DeviceName     = $ComputerName
    OSVersion      = $OSVersion
    OSBuild        = $OSBuild
    SerialNumber   = $SerialNumber
    Domain         = $Domain
    Manufacturer   = $Manufacturer
    Model          = $Model
    CollectedAt    = (Get-Date).ToUniversalTime().ToString("o")
    JobCount       = $Jobs.Count
    TotalFromPeers = if ($TotalPeers) { [long]$TotalPeers } else { 0 }
    TotalFromHttp  = if ($TotalHttp) { [long]$TotalHttp } else { 0 }
    TotalFromCache = if ($TotalCache) { [long]$TotalCache } else { 0 }
    TotalUploaded  = if ($TotalUploaded) { [long]$TotalUploaded } else { 0 }
    Jobs           = $Jobs
    PerfSnap       = $PerfSnap
    Policies       = $Policies
} | ConvertTo-Json -Depth 5 -Compress

# === SEND TO AZURE FUNCTION (mTLS) ===
try {
    $Response = Invoke-RestMethod -Uri $FunctionUrl -Method POST -Body $Payload -ContentType "application/json" -Certificate $Certificate -TimeoutSec 30 -ErrorAction Stop
    $PeerMB = [math]::Round($TotalPeers / 1MB, 2)
    $HttpMB = [math]::Round($TotalHttp / 1MB, 2)
    $UpMB   = [math]::Round($TotalUploaded / 1MB, 2)
    Write-Output "Compliant - Jobs: $($Jobs.Count), Peer: ${PeerMB}MB, HTTP: ${HttpMB}MB, Upload: ${UpMB}MB, Policies: $($Policies.Count)"
    exit 0
} catch {
    Write-Output "Non-Compliant - Failed to send DO data: $($_.Exception.Message)"
    exit 1
}
