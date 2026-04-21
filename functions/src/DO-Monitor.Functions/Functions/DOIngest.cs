using System.Text.Json;
using DOMonitor.Functions.Models;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;

namespace DOMonitor.Functions.Functions;

/// <summary>
/// HTTP Trigger function that receives DO telemetry from Intune clients
/// and forwards the payload to a Service Bus queue for async processing.
/// </summary>
public sealed class DOIngest
{
    private readonly ILogger<DOIngest> _logger;

    public DOIngest(ILogger<DOIngest> logger)
    {
        _logger = logger;
    }

    [Function("DOIngest")]
    public async Task<DOIngestResult> Run(
        [HttpTrigger(AuthorizationLevel.Anonymous, "post")] HttpRequest req)
    {
        DOTelemetryPayload? payload;
        try
        {
            payload = await JsonSerializer.DeserializeAsync<DOTelemetryPayload>(req.Body);
        }
        catch (JsonException ex)
        {
            _logger.LogWarning(ex, "Invalid JSON payload received.");
            return new DOIngestResult
            {
                HttpResponse = new BadRequestObjectResult(new { error = "Invalid JSON payload." }),
                ServiceBusMessage = null
            };
        }

        if (payload is null || string.IsNullOrWhiteSpace(payload.DeviceName))
        {
            return new DOIngestResult
            {
                HttpResponse = new BadRequestObjectResult(new { error = "DeviceName is required." }),
                ServiceBusMessage = null
            };
        }

        // Enrich with ingestion timestamp
        payload.IngestedAt = DateTime.UtcNow.ToString("o");

        _logger.LogInformation("Received DO data from {Device} with {JobCount} jobs.",
            payload.DeviceName, payload.JobCount);

        var message = JsonSerializer.Serialize(payload);

        return new DOIngestResult
        {
            HttpResponse = new AcceptedResult(string.Empty, new
            {
                status = "accepted",
                device = payload.DeviceName,
                jobs = payload.JobCount
            }),
            ServiceBusMessage = message
        };
    }
}

/// <summary>
/// Multi-output binding result for DOIngest.
/// Returns HTTP response and optionally sends a Service Bus message.
/// Authentication is handled at transport level via client certificates (mTLS).
/// </summary>
public sealed class DOIngestResult
{
    [HttpResult]
    public IActionResult HttpResponse { get; set; } = new OkResult();

    [ServiceBusOutput("%ServiceBusQueueName%", Connection = "ServiceBusConnection")]
    public string? ServiceBusMessage { get; set; }
}
