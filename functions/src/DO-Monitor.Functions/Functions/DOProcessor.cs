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
            TimeGenerated        = payload.CollectedAt,
            DeviceName           = payload.DeviceName,
            OSVersion            = payload.OSVersion,
            SerialNumber         = payload.SerialNumber,
            Domain               = payload.Domain,
            FileId               = job.FileId,
            FileName             = job.FileName,
            FileSize_Bytes       = job.FileSize,
            Status               = job.Status,
            Priority             = job.Priority,
            BytesFromPeers       = job.BytesFromPeers,
            BytesFromHttp        = job.BytesFromHttp,
            BytesFromCacheServer = job.BytesFromCacheServer,
            BytesFromLanPeers    = job.BytesFromLanPeers,
            BytesFromGroupPeers  = job.BytesFromGroupPeers,
            BytesFromIntPeers    = job.BytesFromIntPeers,
            TotalBytesDownloaded = job.TotalBytesDownloaded,
            PercentPeerCaching   = job.PercentPeerCaching,
            DownloadMode         = job.DownloadMode,
            SourceURL            = job.SourceURL,
            IsPinned             = job.IsPinned
        }).ToList();

        await _ingestionService.IngestAsync(entries, cancellationToken);

        _logger.LogInformation("Successfully processed {Count} entries for {Device}.",
            entries.Count, payload.DeviceName);
    }
}
