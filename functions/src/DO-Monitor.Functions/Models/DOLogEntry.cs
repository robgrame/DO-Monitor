namespace DOMonitor.Functions.Models;

/// <summary>
/// Flattened log entry for a single DO job, ready for Log Analytics ingestion.
/// Each job is enriched with device context. Includes all fields from
/// Get-DeliveryOptimizationStatus.
/// </summary>
public sealed class DOLogEntry
{
    // Timestamps
    public string TimeGenerated { get; set; } = string.Empty;

    // Device context
    public string DeviceName { get; set; } = string.Empty;
    public string OSVersion { get; set; } = string.Empty;
    public string OSBuild { get; set; } = string.Empty;
    public string SerialNumber { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string Manufacturer { get; set; } = string.Empty;
    public string Model { get; set; } = string.Empty;

    // Job identity
    public string FileId { get; set; } = string.Empty;
    public long FileSize_Bytes { get; set; }
    public long FileSizeInCache { get; set; }
    public long TotalBytesDownloaded { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Priority { get; set; } = string.Empty;
    public string DownloadMode { get; set; } = string.Empty;
    public double PercentPeerCaching { get; set; }

    // Bytes downloaded by source
    public long BytesFromPeers { get; set; }
    public long BytesFromHttp { get; set; }
    public long BytesFromCacheServer { get; set; }
    public long BytesFromLanPeers { get; set; }
    public long BytesFromGroupPeers { get; set; }
    public long BytesFromInternetPeers { get; set; }
    public long BytesFromLinkLocalPeers { get; set; }

    // Bytes uploaded by destination
    public long BytesToLanPeers { get; set; }
    public long BytesToGroupPeers { get; set; }
    public long BytesToInternetPeers { get; set; }
    public long BytesToLinkLocalPeers { get; set; }

    // Connection counts
    public int HttpConnectionCount { get; set; }
    public int LanConnectionCount { get; set; }
    public int GroupConnectionCount { get; set; }
    public int InternetConnectionCount { get; set; }
    public int LinkLocalConnectionCount { get; set; }
    public int CacheServerConnectionCount { get; set; }
    public int NumPeers { get; set; }

    // Metadata
    public string SourceURL { get; set; } = string.Empty;
    public string CacheHost { get; set; } = string.Empty;
    public string PredefinedCallerApplication { get; set; } = string.Empty;
    public double DownloadDuration { get; set; }
    public bool IsPinned { get; set; }
}
