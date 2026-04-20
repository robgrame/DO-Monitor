using Azure.Monitor.Ingestion;
using DOMonitor.Functions.Models;
using Microsoft.Extensions.Logging;

namespace DOMonitor.Functions.Services;

public interface ILogAnalyticsIngestionService
{
    Task IngestAsync(IReadOnlyList<DOLogEntry> entries, CancellationToken cancellationToken = default);
}

/// <summary>
/// Sends flattened DO log entries to Azure Log Analytics
/// via the Logs Ingestion API (Data Collection Rule / Endpoint).
/// Uses Managed Identity via DefaultAzureCredential.
/// </summary>
public sealed class LogAnalyticsIngestionService : ILogAnalyticsIngestionService
{
    private readonly LogsIngestionClient _client;
    private readonly string _dcrImmutableId;
    private readonly string _streamName;
    private readonly ILogger<LogAnalyticsIngestionService> _logger;

    private const int BatchSize = 500;

    public LogAnalyticsIngestionService(
        LogsIngestionClient client,
        ILogger<LogAnalyticsIngestionService> logger)
    {
        _client = client;
        _logger = logger;
        _dcrImmutableId = Environment.GetEnvironmentVariable("LogAnalyticsDCR_ImmutableId")
            ?? throw new InvalidOperationException("LogAnalyticsDCR_ImmutableId is not configured.");
        _streamName = Environment.GetEnvironmentVariable("LogAnalyticsStreamName")
            ?? "Custom-DOStatus_CL";
    }

    public async Task IngestAsync(IReadOnlyList<DOLogEntry> entries, CancellationToken cancellationToken = default)
    {
        if (entries.Count == 0)
        {
            _logger.LogInformation("No entries to ingest.");
            return;
        }

        // Send in batches
        var totalSent = 0;
        foreach (var batch in entries.Chunk(BatchSize))
        {
            var batchList = batch.ToList();

            await _client.UploadAsync(
                _dcrImmutableId,
                _streamName,
                batchList,
                cancellationToken: cancellationToken);

            totalSent += batchList.Count;
            _logger.LogInformation("Sent batch of {Count} entries to Log Analytics ({Total}/{Grand} total).",
                batchList.Count, totalSent, entries.Count);
        }

        _logger.LogInformation("Successfully ingested {Total} DO job entries.", entries.Count);
    }
}
