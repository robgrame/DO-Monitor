namespace DOMonitor.Functions.Models;

/// <summary>
/// Represents a trusted CA chain with Root CA and one or more Sub CA thumbprints.
/// Multiple chains can be configured to support certificate rotation and
/// multiple issuing CAs.
/// </summary>
public sealed class TrustedCaChain
{
    /// <summary>Friendly name for this chain (e.g., "Production CA 2026").</summary>
    public string Name { get; set; } = string.Empty;

    /// <summary>Thumbprint of the Root CA certificate.</summary>
    public string RootCaThumbprint { get; set; } = string.Empty;

    /// <summary>Thumbprints of the Subordinate/Issuing CA certificates in this chain.</summary>
    public List<string> SubCaThumbprints { get; set; } = [];
}

/// <summary>
/// Configuration section holding all trusted CA chains.
/// Bound from App Configuration key "DO-Monitor:TrustedCaChains".
/// </summary>
public sealed class CertificateValidationOptions
{
    public const string SectionName = "CertificateValidation";

    /// <summary>List of trusted CA chains. A client cert is valid if its chain
    /// matches ANY of these entries.</summary>
    public List<TrustedCaChain> TrustedChains { get; set; } = [];

    /// <summary>If true, validation is bypassed (for development only).</summary>
    public bool DisableValidation { get; set; }
}
