param($SBMessage, $TriggerMetadata)

<#
.SYNOPSIS
    Service Bus Trigger - Processes DO telemetry messages and writes to Log Analytics
    via the Azure Monitor Data Collection API (Logs Ingestion API).
#>

# === CONFIGURATION ===
$DCE = $env:LogAnalyticsDCE
$DCR_ImmutableId = $env:LogAnalyticsDCR_ImmutableId
$StreamName = $env:LogAnalyticsStreamName

# === PARSE MESSAGE ===
$Data = $SBMessage | ConvertFrom-Json -ErrorAction Stop

Write-Host "Processing DO data from $($Data.DeviceName) - $($Data.JobCount) jobs"

# === BUILD LOG ENTRIES ===
# Flatten each job into a separate log entry with device context
$LogEntries = @()

foreach ($Job in $Data.Jobs) {
    $LogEntries += @{
        TimeGenerated        = $Data.CollectedAt
        DeviceName           = $Data.DeviceName
        OSVersion            = $Data.OSVersion
        SerialNumber         = $Data.SerialNumber
        Domain               = $Data.Domain
        FileId               = $Job.FileId
        FileName             = $Job.FileName
        FileSize_Bytes       = $Job.FileSize
        Status               = $Job.Status
        Priority             = $Job.Priority
        BytesFromPeers       = $Job.BytesFromPeers
        BytesFromHttp        = $Job.BytesFromHttp
        BytesFromCacheServer = $Job.BytesFromCacheServer
        BytesFromLanPeers    = $Job.BytesFromLanPeers
        BytesFromGroupPeers  = $Job.BytesFromGroupPeers
        BytesFromIntPeers    = $Job.BytesFromIntPeers
        TotalBytesDownloaded = $Job.TotalBytesDownloaded
        PercentPeerCaching   = $Job.PercentPeerCaching
        DownloadMode         = $Job.DownloadMode
        SourceURL            = $Job.SourceURL
        IsPinned             = $Job.IsPinned
    }
}

if ($LogEntries.Count -eq 0) {
    Write-Host "No job entries to process for $($Data.DeviceName)"
    return
}

# === SEND TO LOG ANALYTICS via Data Collection API ===
# Uses Managed Identity for authentication
try {
    # Get access token via Managed Identity
    $TokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=https://monitor.azure.com/"
    $TokenResponse = Invoke-RestMethod -Uri $TokenUri -Headers @{ "Metadata" = "true" } -ErrorAction Stop
    $AccessToken = $TokenResponse.access_token

    # Build the ingestion URI
    $IngestUri = "$DCE/dataCollectionRules/$DCR_ImmutableId/streams/${StreamName}?api-version=2023-01-01"

    # Send data in batches of 500
    $BatchSize = 500
    for ($i = 0; $i -lt $LogEntries.Count; $i += $BatchSize) {
        $Batch = $LogEntries[$i..([math]::Min($i + $BatchSize - 1, $LogEntries.Count - 1))]
        $JsonBody = $Batch | ConvertTo-Json -Depth 5 -Compress -AsArray

        Invoke-RestMethod -Uri $IngestUri -Method POST -Body $JsonBody -ContentType "application/json" -Headers @{
            "Authorization" = "Bearer $AccessToken"
        } -ErrorAction Stop

        Write-Host "Sent batch of $($Batch.Count) entries to Log Analytics"
    }

    Write-Host "Successfully ingested $($LogEntries.Count) DO job entries for $($Data.DeviceName)"
} catch {
    Write-Error "Failed to send to Log Analytics: $($_.Exception.Message)"
    throw
}
