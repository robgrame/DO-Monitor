namespace DOMonitor.Functions.Models;

/// <summary>
/// Flattened log entry for a single DO job, ready for Log Analytics ingestion.
/// Each job is enriched with device context.
/// </summary>
public sealed class DOLogEntry
{
    public string TimeGenerated { get; set; } = string.Empty;
    public string DeviceName { get; set; } = string.Empty;
    public string OSVersion { get; set; } = string.Empty;
    public string SerialNumber { get; set; } = string.Empty;
    public string Domain { get; set; } = string.Empty;
    public string FileId { get; set; } = string.Empty;
    public string FileName { get; set; } = string.Empty;
    public long FileSize_Bytes { get; set; }
    public string Status { get; set; } = string.Empty;
    public string Priority { get; set; } = string.Empty;
    public long BytesFromPeers { get; set; }
    public long BytesFromHttp { get; set; }
    public long BytesFromCacheServer { get; set; }
    public long BytesFromLanPeers { get; set; }
    public long BytesFromGroupPeers { get; set; }
    public long BytesFromIntPeers { get; set; }
    public long TotalBytesDownloaded { get; set; }
    public double PercentPeerCaching { get; set; }
    public string DownloadMode { get; set; } = string.Empty;
    public string SourceURL { get; set; } = string.Empty;
    public bool IsPinned { get; set; }
}
