<#
.SYNOPSIS
    Intune Proactive Remediation - Detection Script
    Collects Delivery Optimization job details and sends them to Azure Function.
.DESCRIPTION
    Gathers DO status from Get-DeliveryOptimizationStatus, enriches with device info,
    and POSTs to the DOIngest Azure Function endpoint.
    Returns compliant (exit 0) on success, non-compliant (exit 1) on failure.
.NOTES
    Configure $FunctionUrl before deployment.
#>

# === CONFIGURATION ===
$FunctionUrl = "https://<YOUR-FUNCTION-APP>.azurewebsites.net/api/DOIngest?code=<YOUR-FUNCTION-KEY>"

# === COLLECT DEVICE INFO ===
try {
    $ComputerName = $env:COMPUTERNAME
    $OSVersion = (Get-CimInstance -ClassName Win32_OperatingSystem).Version
    $SerialNumber = (Get-CimInstance -ClassName Win32_BIOS).SerialNumber
    $Domain = (Get-CimInstance -ClassName Win32_ComputerSystem).Domain
} catch {
    $ComputerName = $env:COMPUTERNAME
    $OSVersion = "Unknown"
    $SerialNumber = "Unknown"
    $Domain = "Unknown"
}

# === COLLECT DO STATUS ===
try {
    $DOStatus = Get-DeliveryOptimizationStatus -ErrorAction Stop

    if (-not $DOStatus -or $DOStatus.Count -eq 0) {
        Write-Output "No DO jobs found."
        exit 0
    }

    $Jobs = @()
    foreach ($Job in $DOStatus) {
        $Jobs += @{
            FileId              = $Job.FileId
            FileName            = if ($Job.FileName) { [System.IO.Path]::GetFileName($Job.FileName) } else { "" }
            FileSize            = $Job.FileSize
            Status              = $Job.Status.ToString()
            Priority            = $Job.Priority.ToString()
            BytesFromPeers      = $Job.BytesFromPeers
            BytesFromHttp       = $Job.BytesFromHttp
            BytesFromCacheServer = $Job.BytesFromCacheServer
            BytesFromLanPeers   = $Job.BytesFromLanPeers
            BytesFromGroupPeers = $Job.BytesFromGroupPeers
            BytesFromIntPeers   = $Job.BytesFromIntPeers
            TotalBytesDownloaded = $Job.TotalBytesDownloaded
            PercentPeerCaching  = $Job.PercentPeerCaching
            DownloadMode        = $Job.DownloadMode.ToString()
            SourceURL           = if ($Job.SourceURL) { $Job.SourceURL } else { "" }
            ExpireOn            = if ($Job.ExpireOn) { $Job.ExpireOn.ToString("o") } else { "" }
            IsPinned            = $Job.IsPinned
        }
    }
} catch {
    Write-Output "Error collecting DO status: $($_.Exception.Message)"
    exit 1
}

# === BUILD PAYLOAD ===
$Payload = @{
    DeviceName    = $ComputerName
    OSVersion     = $OSVersion
    SerialNumber  = $SerialNumber
    Domain        = $Domain
    CollectedAt   = (Get-Date).ToUniversalTime().ToString("o")
    JobCount      = $Jobs.Count
    TotalFromPeers = ($Jobs | Measure-Object -Property BytesFromPeers -Sum).Sum
    TotalFromHttp  = ($Jobs | Measure-Object -Property BytesFromHttp -Sum).Sum
    TotalFromCache = ($Jobs | Measure-Object -Property BytesFromCacheServer -Sum).Sum
    Jobs          = $Jobs
} | ConvertTo-Json -Depth 5 -Compress

# === SEND TO AZURE FUNCTION ===
try {
    $Response = Invoke-RestMethod -Uri $FunctionUrl -Method POST -Body $Payload -ContentType "application/json" -TimeoutSec 30 -ErrorAction Stop
    Write-Output "Compliant - Sent $($Jobs.Count) DO jobs. Peers: $([math]::Round(($Jobs | Measure-Object -Property BytesFromPeers -Sum).Sum / 1MB, 2)) MB, HTTP: $([math]::Round(($Jobs | Measure-Object -Property BytesFromHttp -Sum).Sum / 1MB, 2)) MB"
    exit 0
} catch {
    Write-Output "Non-Compliant - Failed to send DO data: $($_.Exception.Message)"
    exit 1
}
