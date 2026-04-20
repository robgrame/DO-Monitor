using System.Security.Cryptography.X509Certificates;
using DOMonitor.Functions.Services;
using Microsoft.AspNetCore.Http;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Logging;

namespace DOMonitor.Functions.Middleware;

/// <summary>
/// Functions middleware that validates client certificates on incoming HTTP requests.
/// The Azure Function App is configured with clientCertEnabled=true and clientCertMode=Required,
/// so the platform handles TLS negotiation. This middleware validates the presented cert
/// against trusted CA chains configured in App Configuration.
///
/// Only applies to HTTP-triggered functions. Service Bus triggers are not affected.
/// </summary>
public sealed class ClientCertificateValidationMiddleware : IFunctionsWorkerMiddleware
{
    private readonly ICertificateValidationService _certValidation;
    private readonly ILogger<ClientCertificateValidationMiddleware> _logger;

    public ClientCertificateValidationMiddleware(
        ICertificateValidationService certValidation,
        ILogger<ClientCertificateValidationMiddleware> logger)
    {
        _certValidation = certValidation;
        _logger = logger;
    }

    public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
    {
        // Only validate HTTP-triggered functions
        var httpRequestData = await context.GetHttpRequestDataAsync();
        if (httpRequestData is null)
        {
            // Not an HTTP trigger (e.g., Service Bus trigger) — skip validation
            await next(context);
            return;
        }

        // Extract client certificate from the request
        X509Certificate2? clientCert = null;

        // Azure App Service forwards the client cert in the X-ARR-ClientCert header
        if (httpRequestData.Headers.TryGetValues("X-ARR-ClientCert", out var certHeaders))
        {
            var certHeader = certHeaders.FirstOrDefault();
            if (!string.IsNullOrEmpty(certHeader))
            {
                try
                {
                    var certBytes = Convert.FromBase64String(certHeader);
                    clientCert = new X509Certificate2(certBytes);
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Failed to parse client certificate from X-ARR-ClientCert header.");
                }
            }
        }

        // Validate
        if (!_certValidation.ValidateClientCertificate(clientCert))
        {
            _logger.LogWarning("Client certificate validation failed. Returning 403.");

            var response = httpRequestData.CreateResponse();
            response.StatusCode = System.Net.HttpStatusCode.Forbidden;
            await response.WriteAsJsonAsync(new
            {
                error = "Forbidden",
                message = "Client certificate is not trusted. The certificate must be issued by a configured trusted CA."
            });

            // Set the invocation result to the 403 response
            context.GetInvocationResult().Value = response;
            return;
        }

        _logger.LogDebug("Client certificate validated. Proceeding with request.");
        await next(context);
    }
}
