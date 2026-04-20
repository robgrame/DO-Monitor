using System.Security.Cryptography.X509Certificates;
using DOMonitor.Functions.Models;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;

namespace DOMonitor.Functions.Services;

public interface ICertificateValidationService
{
    /// <summary>
    /// Validates that the client certificate was issued by a trusted CA chain.
    /// Returns true if the certificate chain matches any configured trusted chain.
    /// </summary>
    bool ValidateClientCertificate(X509Certificate2? certificate);
}

/// <summary>
/// Validates client certificates against configured trusted CA chains.
/// Reads Root CA and Sub CA thumbprints from App Configuration via IOptionsMonitor
/// to support hot-reload without Function App restart.
/// </summary>
public sealed class CertificateValidationService : ICertificateValidationService
{
    private readonly IOptionsMonitor<CertificateValidationOptions> _options;
    private readonly ILogger<CertificateValidationService> _logger;

    public CertificateValidationService(
        IOptionsMonitor<CertificateValidationOptions> options,
        ILogger<CertificateValidationService> logger)
    {
        _options = options;
        _logger = logger;
    }

    public bool ValidateClientCertificate(X509Certificate2? certificate)
    {
        if (certificate is null)
        {
            _logger.LogWarning("No client certificate presented.");
            return false;
        }

        var config = _options.CurrentValue;

        if (config.DisableValidation)
        {
            _logger.LogWarning("Certificate validation is DISABLED. Allowing all certificates.");
            return true;
        }

        if (config.TrustedChains.Count == 0)
        {
            _logger.LogError("No trusted CA chains configured. Rejecting all certificates.");
            return false;
        }

        _logger.LogInformation(
            "Validating certificate Subject='{Subject}', Thumbprint='{Thumbprint}' against {ChainCount} trusted chain(s).",
            certificate.Subject, certificate.Thumbprint, config.TrustedChains.Count);

        // Build the certificate chain
        using var chain = new X509Chain();
        chain.ChainPolicy.RevocationMode = X509RevocationMode.NoCheck;
        chain.ChainPolicy.VerificationFlags = X509VerificationFlags.AllowUnknownCertificateAuthority;

        if (!chain.Build(certificate))
        {
            var errors = string.Join(", ", chain.ChainStatus.Select(s => s.StatusInformation));
            _logger.LogWarning("Certificate chain build failed: {Errors}", errors);
            // Continue anyway — we validate by thumbprint matching, not Windows trust store
        }

        // Extract thumbprints from the chain (excluding the leaf cert)
        var chainThumbprints = chain.ChainElements
            .Skip(1) // skip leaf
            .Select(e => e.Certificate.Thumbprint.ToUpperInvariant())
            .ToList();

        _logger.LogDebug("Certificate chain has {Count} CA element(s): {Thumbprints}",
            chainThumbprints.Count, string.Join(", ", chainThumbprints));

        // Check against each trusted chain configuration
        foreach (var trustedChain in config.TrustedChains)
        {
            if (MatchesTrustedChain(chainThumbprints, trustedChain))
            {
                _logger.LogInformation(
                    "Certificate validated successfully against trusted chain '{ChainName}'.",
                    trustedChain.Name);
                return true;
            }
        }

        _logger.LogWarning(
            "Certificate Subject='{Subject}', Thumbprint='{Thumbprint}' did not match any trusted CA chain.",
            certificate.Subject, certificate.Thumbprint);
        return false;
    }

    private bool MatchesTrustedChain(List<string> chainThumbprints, TrustedCaChain trustedChain)
    {
        var rootThumbprint = trustedChain.RootCaThumbprint.ToUpperInvariant();
        var subThumbprints = trustedChain.SubCaThumbprints
            .Select(t => t.ToUpperInvariant())
            .ToHashSet();

        // Verify Root CA is in the chain
        var hasRoot = chainThumbprints.Contains(rootThumbprint);
        if (!hasRoot)
        {
            _logger.LogDebug("Root CA '{Root}' not found in chain for '{ChainName}'.",
                rootThumbprint, trustedChain.Name);
            return false;
        }

        // Verify at least one Sub CA is in the chain
        var matchedSub = chainThumbprints.Any(t => subThumbprints.Contains(t));
        if (!matchedSub && subThumbprints.Count > 0)
        {
            _logger.LogDebug("No matching Sub CA found in chain for '{ChainName}'.",
                trustedChain.Name);
            return false;
        }

        return true;
    }
}
