using System.Text.Json.Serialization;

namespace DOMonitor.Functions.Models;

/// <summary>
/// Payload received from the client detection script.
/// Contains device info and a list of Delivery Optimization jobs.
/// </summary>
public sealed class DOTelemetryPayload
{
    [JsonPropertyName("DeviceName")]
    public string DeviceName { get; set; } = string.Empty;

    [JsonPropertyName("OSVersion")]
    public string OSVersion { get; set; } = string.Empty;

    [JsonPropertyName("SerialNumber")]
    public string SerialNumber { get; set; } = string.Empty;

    [JsonPropertyName("Domain")]
    public string Domain { get; set; } = string.Empty;

    [JsonPropertyName("CollectedAt")]
    public string CollectedAt { get; set; } = string.Empty;

    [JsonPropertyName("JobCount")]
    public int JobCount { get; set; }

    [JsonPropertyName("TotalFromPeers")]
    public long TotalFromPeers { get; set; }

    [JsonPropertyName("TotalFromHttp")]
    public long TotalFromHttp { get; set; }

    [JsonPropertyName("TotalFromCache")]
    public long TotalFromCache { get; set; }

    [JsonPropertyName("Jobs")]
    public List<DOJobDetail> Jobs { get; set; } = [];

    [JsonPropertyName("IngestedAt")]
    public string? IngestedAt { get; set; }
}

/// <summary>
/// Details of a single Delivery Optimization job.
/// </summary>
public sealed class DOJobDetail
{
    [JsonPropertyName("FileId")]
    public string FileId { get; set; } = string.Empty;

    [JsonPropertyName("FileName")]
    public string FileName { get; set; } = string.Empty;

    [JsonPropertyName("FileSize")]
    public long FileSize { get; set; }

    [JsonPropertyName("Status")]
    public string Status { get; set; } = string.Empty;

    [JsonPropertyName("Priority")]
    public string Priority { get; set; } = string.Empty;

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

    [JsonPropertyName("BytesFromIntPeers")]
    public long BytesFromIntPeers { get; set; }

    [JsonPropertyName("TotalBytesDownloaded")]
    public long TotalBytesDownloaded { get; set; }

    [JsonPropertyName("PercentPeerCaching")]
    public double PercentPeerCaching { get; set; }

    [JsonPropertyName("DownloadMode")]
    public string DownloadMode { get; set; } = string.Empty;

    [JsonPropertyName("SourceURL")]
    public string SourceURL { get; set; } = string.Empty;

    [JsonPropertyName("ExpireOn")]
    public string? ExpireOn { get; set; }

    [JsonPropertyName("IsPinned")]
    public bool IsPinned { get; set; }
}
