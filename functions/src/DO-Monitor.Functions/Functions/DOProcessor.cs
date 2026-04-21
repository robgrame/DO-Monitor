using System.Text.Json;
using Azure.Messaging.ServiceBus;
using DOMonitor.Functions.Models;
using DOMonitor.Functions.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DOMonitor.Functions.Functions;

/// <summary>
/// Service Bus Trigger function that processes DO telemetry messages
/// and writes flattened job entries to Log Analytics via the Logs Ingestion API.
/// </summary>
public sealed class DOProcessor
{
    private readonly ILogAnalyticsIngestionService _ingestionService;
    private readonly ILogger<DOProcessor> _logger;

    public DOProcessor(
        ILogAnalyticsIngestionService ingestionService,
        ILogger<DOProcessor> logger)
    {
        _ingestionService = ingestionService;
        _logger = logger;
    }

    [Function("DOProcessor")]
    public async Task Run(
        [ServiceBusTrigger("%ServiceBusQueueName%", Connection = "ServiceBusConnection")]
        ServiceBusReceivedMessage message,
        CancellationToken cancellationToken)
    {
        DOTelemetryPayload? payload;
        try
        {
            payload = JsonSerializer.Deserialize<DOTelemetryPayload>(message.Body);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to deserialize Service Bus message {MessageId}.", message.MessageId);
            throw; // Let SB retry / dead-letter
        }

        if (payload is null)
        {
            _logger.LogWarning("Null payload in message {MessageId}. Skipping.", message.MessageId);
            return;
        }

        _logger.LogInformation("Processing DO data from {Device} — {JobCount} jobs.",
            payload.DeviceName, payload.JobCount);

        if (payload.Jobs.Count == 0)
        {
            _logger.LogInformation("No jobs in payload for {Device}. Nothing to ingest.", payload.DeviceName);
            return;
        }

        // Flatten each job into a log entry with device context
        var entries = payload.Jobs.Select(job => new DOLogEntry
        {
            TimeGenerated              = payload.CollectedAt,
            DeviceName                 = payload.DeviceName,
            OSVersion                  = payload.OSVersion,
            OSBuild                    = payload.OSBuild,
            SerialNumber               = payload.SerialNumber,
            Domain                     = payload.Domain,
            Manufacturer               = payload.Manufacturer,
            Model                      = payload.Model,
            FileId                     = job.FileId,
            FileSize_Bytes             = job.FileSize,
            FileSizeInCache            = job.FileSizeInCache,
            TotalBytesDownloaded       = job.TotalBytesDownloaded,
            Status                     = job.Status,
            Priority                   = job.Priority,
            DownloadMode               = job.DownloadMode,
            PercentPeerCaching         = job.PercentPeerCaching,
            BytesFromPeers             = job.BytesFromPeers,
            BytesFromHttp              = job.BytesFromHttp,
            BytesFromCacheServer       = job.BytesFromCacheServer,
            BytesFromLanPeers          = job.BytesFromLanPeers,
            BytesFromGroupPeers        = job.BytesFromGroupPeers,
            BytesFromInternetPeers     = job.BytesFromInternetPeers,
            BytesFromLinkLocalPeers    = job.BytesFromLinkLocalPeers,
            BytesToLanPeers            = job.BytesToLanPeers,
            BytesToGroupPeers          = job.BytesToGroupPeers,
            BytesToInternetPeers       = job.BytesToInternetPeers,
            BytesToLinkLocalPeers      = job.BytesToLinkLocalPeers,
            HttpConnectionCount        = job.HttpConnectionCount,
            LanConnectionCount         = job.LanConnectionCount,
            GroupConnectionCount       = job.GroupConnectionCount,
            InternetConnectionCount    = job.InternetConnectionCount,
            LinkLocalConnectionCount   = job.LinkLocalConnectionCount,
            CacheServerConnectionCount = job.CacheServerConnectionCount,
            NumPeers                   = job.NumPeers,
            SourceURL                  = job.SourceURL,
            CacheHost                  = job.CacheHost,
            PredefinedCallerApplication = job.PredefinedCallerApplication,
            DownloadDuration           = job.DownloadDuration,
            IsPinned                   = job.IsPinned
        }).ToList();

        await _ingestionService.IngestAsync(entries, cancellationToken);

        _logger.LogInformation("Successfully processed {Count} entries for {Device}.",
            entries.Count, payload.DeviceName);
    }
}
