using System.Text.Json.Serialization;

namespace DOMonitor.Functions.Models;

/// <summary>
/// Payload received from the client detection script.
/// Contains device info, DO jobs, performance snapshot, and applied policies.
/// </summary>
public sealed class DOTelemetryPayload
{
    // Device identity
    [JsonPropertyName("DeviceName")]
    public string DeviceName { get; set; } = string.Empty;

    [JsonPropertyName("OSVersion")]
    public string OSVersion { get; set; } = string.Empty;

    [JsonPropertyName("OSBuild")]
    public string OSBuild { get; set; } = string.Empty;

    [JsonPropertyName("SerialNumber")]
    public string SerialNumber { get; set; } = string.Empty;

    [JsonPropertyName("Domain")]
    public string Domain { get; set; } = string.Empty;

    [JsonPropertyName("Manufacturer")]
    public string Manufacturer { get; set; } = string.Empty;

    [JsonPropertyName("Model")]
    public string Model { get; set; } = string.Empty;

    // Collection metadata
    [JsonPropertyName("CollectedAt")]
    public string CollectedAt { get; set; } = string.Empty;

    [JsonPropertyName("JobCount")]
    public int JobCount { get; set; }

    // Aggregate totals
    [JsonPropertyName("TotalFromPeers")]
    public long TotalFromPeers { get; set; }

    [JsonPropertyName("TotalFromHttp")]
    public long TotalFromHttp { get; set; }

    [JsonPropertyName("TotalFromCache")]
    public long TotalFromCache { get; set; }

    [JsonPropertyName("TotalUploaded")]
    public long TotalUploaded { get; set; }

    // Job details
    [JsonPropertyName("Jobs")]
    public List<DOJobDetail> Jobs { get; set; } = [];

    // Performance snapshot
    [JsonPropertyName("PerfSnap")]
    public Dictionary<string, object>? PerfSnap { get; set; }

    // Applied DO policies (GPO + MDM + Local)
    [JsonPropertyName("Policies")]
    public Dictionary<string, object>? Policies { get; set; }

    [JsonPropertyName("IngestedAt")]
    public string? IngestedAt { get; set; }
}

/// <summary>
/// All fields from Get-DeliveryOptimizationStatus for a single DO job.
/// </summary>
public sealed class DOJobDetail
{
    [JsonPropertyName("FileId")]
    public string FileId { get; set; } = string.Empty;

    [JsonPropertyName("FileSize")]
    public long FileSize { get; set; }

    [JsonPropertyName("FileSizeInCache")]
    public long FileSizeInCache { get; set; }

    [JsonPropertyName("TotalBytesDownloaded")]
    public long TotalBytesDownloaded { get; set; }

    [JsonPropertyName("Status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("Priority")]
    public string Priority { get; set; } = string.Empty;

    [JsonPropertyName("DownloadMode")]
    public string DownloadMode { get; set; } = string.Empty;

    [JsonPropertyName("PercentPeerCaching")]
    public double PercentPeerCaching { get; set; }

    // Bytes downloaded by source
    [JsonPropertyName("BytesFromPeers")]
    public long BytesFromPeers { get; set; }

    [JsonPropertyName("BytesFromHttp")]
    public long BytesFromHttp { get; set; }

    [JsonPropertyName("BytesFromCacheServer")]
    public long BytesFromCacheServer { get; set; }

    [JsonPropertyName("BytesFromLanPeers")]
    public long BytesFromLanPeers { get; set; }

    [JsonPropertyName("BytesFromGroupPeers")]
    public long BytesFromGroupPeers { get; set; }

    [JsonPropertyName("BytesFromInternetPeers")]
    public long BytesFromInternetPeers { get; set; }

    [JsonPropertyName("BytesFromLinkLocalPeers")]
    public long BytesFromLinkLocalPeers { get; set; }

    // Bytes uploaded by destination
    [JsonPropertyName("BytesToLanPeers")]
    public long BytesToLanPeers { get; set; }

    [JsonPropertyName("BytesToGroupPeers")]
    public long BytesToGroupPeers { get; set; }

    [JsonPropertyName("BytesToInternetPeers")]
    public long BytesToInternetPeers { get; set; }

    [JsonPropertyName("BytesToLinkLocalPeers")]
    public long BytesToLinkLocalPeers { get; set; }

    // Connection counts
    [JsonPropertyName("HttpConnectionCount")]
    public int HttpConnectionCount { get; set; }

    [JsonPropertyName("LanConnectionCount")]
    public int LanConnectionCount { get; set; }

    [JsonPropertyName("GroupConnectionCount")]
    public int GroupConnectionCount { get; set; }

    [JsonPropertyName("InternetConnectionCount")]
    public int InternetConnectionCount { get; set; }

    [JsonPropertyName("LinkLocalConnectionCount")]
    public int LinkLocalConnectionCount { get; set; }

    [JsonPropertyName("CacheServerConnectionCount")]
    public int CacheServerConnectionCount { get; set; }

    [JsonPropertyName("NumPeers")]
    public int NumPeers { get; set; }

    // Metadata
    [JsonPropertyName("SourceURL")]
    public string SourceURL { get; set; } = string.Empty;

    [JsonPropertyName("CacheHost")]
    public string CacheHost { get; set; } = string.Empty;

    [JsonPropertyName("PredefinedCallerApplication")]
    public string PredefinedCallerApplication { get; set; } = string.Empty;

    [JsonPropertyName("DownloadDuration")]
    public double DownloadDuration { get; set; }

    [JsonPropertyName("ExpireOn")]
    public string? ExpireOn { get; set; }

    [JsonPropertyName("IsPinned")]
    public bool IsPinned { get; set; }
}
