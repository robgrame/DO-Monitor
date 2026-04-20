using Azure.Identity;
using Azure.Monitor.Ingestion;
using DOMonitor.Functions.Middleware;
using DOMonitor.Functions.Models;
using DOMonitor.Functions.Services;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

// Azure App Configuration (hot-reload enabled)
var appConfigEndpoint = Environment.GetEnvironmentVariable("AppConfigEndpoint");
if (!string.IsNullOrEmpty(appConfigEndpoint))
{
    builder.Configuration.AddAzureAppConfiguration(options =>
    {
        options.Connect(new Uri(appConfigEndpoint), new DefaultAzureCredential())
            .Select("DO-Monitor:*")
            .ConfigureRefresh(refresh =>
            {
                refresh.Register("DO-Monitor:Sentinel", refreshAll: true)
                       .SetRefreshInterval(TimeSpan.FromMinutes(5));
            });
    });

    builder.Services.AddAzureAppConfiguration();
}

// Bind certificate validation options from App Configuration
builder.Services.Configure<CertificateValidationOptions>(
    builder.Configuration.GetSection("DO-Monitor:CertificateValidation"));

// Application Insights
builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

// Register services
builder.Services.AddSingleton<ICertificateValidationService, CertificateValidationService>();

builder.Services.AddSingleton(sp =>
{
    var dceEndpoint = Environment.GetEnvironmentVariable("LogAnalyticsDCE")
        ?? throw new InvalidOperationException("LogAnalyticsDCE is not configured.");
    return new LogsIngestionClient(new Uri(dceEndpoint), new DefaultAzureCredential());
});

builder.Services.AddSingleton<ILogAnalyticsIngestionService, LogAnalyticsIngestionService>();

// Register client certificate validation middleware
builder.UseMiddleware<ClientCertificateValidationMiddleware>();

builder.Build().Run();
