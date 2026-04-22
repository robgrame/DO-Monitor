<#
.SYNOPSIS
    DO-Monitor — Create a self-signed PKI for client certificate authentication.
.DESCRIPTION
    Creates a Root CA and issues a client certificate for testing.
    In production, use an enterprise CA (AD CS) or a third-party CA
    and deploy client certs via Intune SCEP or PKCS profiles.

    This script creates:
    1. Root CA certificate (LocalMachine\Root)
    2. Client certificate signed by the Root CA (LocalMachine\My)
    3. Exports Root CA .cer (for App Configuration trust chain)
    4. Exports Client cert .pfx (for testing / Intune PKCS import)

    Must be run as Administrator.
.EXAMPLE
    .\Setup-ClientPKI.ps1
    .\Setup-ClientPKI.ps1 -RootCAName "DO-Monitor Root CA" -ClientCertName "DO-Monitor Client"
#>

[CmdletBinding()]
param(
    [string]$RootCAName = "DO-Monitor Root CA",
    [string]$ClientCertName = "DO-Monitor Client",
    [string]$OutputDir = "$PSScriptRoot\certs",
    [int]$RootCAValidityYears = 5,
    [int]$ClientCertValidityYears = 2
)

$ErrorActionPreference = "Stop"

# Check admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Error "Run as Administrator."
    exit 1
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Setup Client PKI" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Create output dir
if (-not (Test-Path $OutputDir)) { New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null }

# ---- 1. Create Root CA ----
Write-Host "`n[1/4] Creating Root CA: $RootCAName" -ForegroundColor Yellow

$RootCA = New-SelfSignedCertificate `
    -Subject "CN=$RootCAName" `
    -KeyUsage CertSign, CRLSign, DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 4096 `
    -HashAlgorithm SHA256 `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -NotAfter (Get-Date).AddYears($RootCAValidityYears) `
    -KeyExportPolicy Exportable `
    -TextExtension @("2.5.29.19={text}CA=true&pathlength=1")

# Move Root CA to Trusted Root store
$RootCABytes = $RootCA.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
$TrustedRootStore = New-Object System.Security.Cryptography.X509Certificates.X509Store("Root", "LocalMachine")
$TrustedRootStore.Open("ReadWrite")
$TrustedRootStore.Add($RootCA)
$TrustedRootStore.Close()

Write-Host "  Thumbprint: $($RootCA.Thumbprint)" -ForegroundColor Green
Write-Host "  Validity:   $($RootCA.NotBefore.ToString('yyyy-MM-dd')) to $($RootCA.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

# ---- 2. Create Client Certificate signed by Root CA ----
Write-Host "`n[2/4] Creating Client Certificate: $ClientCertName" -ForegroundColor Yellow

$ClientCert = New-SelfSignedCertificate `
    -Subject "CN=$ClientCertName" `
    -KeyUsage DigitalSignature `
    -KeyAlgorithm RSA `
    -KeyLength 2048 `
    -HashAlgorithm SHA256 `
    -CertStoreLocation "Cert:\LocalMachine\My" `
    -NotAfter (Get-Date).AddYears($ClientCertValidityYears) `
    -KeyExportPolicy Exportable `
    -Signer $RootCA `
    -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.2")  # Client Authentication EKU

Write-Host "  Thumbprint: $($ClientCert.Thumbprint)" -ForegroundColor Green
Write-Host "  Issuer:     $($ClientCert.Issuer)" -ForegroundColor Gray
Write-Host "  Validity:   $($ClientCert.NotBefore.ToString('yyyy-MM-dd')) to $($ClientCert.NotAfter.ToString('yyyy-MM-dd'))" -ForegroundColor Gray

# ---- 3. Export Root CA public key (.cer) ----
Write-Host "`n[3/4] Exporting certificates..." -ForegroundColor Yellow

$RootCACerPath = Join-Path $OutputDir "DO-Monitor-RootCA.cer"
Export-Certificate -Cert $RootCA -FilePath $RootCACerPath -Type CERT | Out-Null
Write-Host "  Root CA:     $RootCACerPath" -ForegroundColor White

# Export client cert as PFX (for testing or Intune PKCS import)
$ClientPfxPath = Join-Path $OutputDir "DO-Monitor-Client.pfx"
$PfxPassword = ConvertTo-SecureString -String "DOMonitor2026!" -Force -AsPlainText
Export-PfxCertificate -Cert $ClientCert -FilePath $ClientPfxPath -Password $PfxPassword -ChainOption BuildChain | Out-Null
Write-Host "  Client PFX:  $ClientPfxPath (password: DOMonitor2026!)" -ForegroundColor White

# Export client cert public key (.cer)
$ClientCerPath = Join-Path $OutputDir "DO-Monitor-Client.cer"
Export-Certificate -Cert $ClientCert -FilePath $ClientCerPath -Type CERT | Out-Null
Write-Host "  Client CER:  $ClientCerPath" -ForegroundColor White

# ---- 4. Summary ----
Write-Host "`n[4/4] Summary" -ForegroundColor Yellow
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " PKI created successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Root CA" -ForegroundColor Cyan
Write-Host "    Subject:    CN=$RootCAName" -ForegroundColor White
Write-Host "    Thumbprint: $($RootCA.Thumbprint)" -ForegroundColor White
Write-Host "    Store:      LocalMachine\Root + LocalMachine\My" -ForegroundColor Gray
Write-Host ""
Write-Host "  Client Certificate" -ForegroundColor Cyan
Write-Host "    Subject:    CN=$ClientCertName" -ForegroundColor White
Write-Host "    Thumbprint: $($ClientCert.Thumbprint)" -ForegroundColor White
Write-Host "    Store:      LocalMachine\My" -ForegroundColor Gray
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Yellow
Write-Host "  1. Add Root CA thumbprint to App Configuration:" -ForegroundColor White
Write-Host "     .\deploy\Manage-TrustedCAChains.ps1 -Action Add ``" -ForegroundColor Gray
Write-Host "         -ChainName `"DO-Monitor PKI`" ``" -ForegroundColor Gray
Write-Host "         -RootCaThumbprint `"$($RootCA.Thumbprint)`" ``" -ForegroundColor Gray
Write-Host "         -SubCaThumbprints `"$($RootCA.Thumbprint)`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  2. Rebuild package with new client cert thumbprint:" -ForegroundColor White
Write-Host "     .\package\Build-IntunePackage.ps1 -CertThumbprint `"$($ClientCert.Thumbprint)`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  3. For production: deploy client certs via Intune SCEP/PKCS profile" -ForegroundColor White
Write-Host ""

# Save thumbprints for easy reference
@{
    RootCA = @{
        Subject    = "CN=$RootCAName"
        Thumbprint = $RootCA.Thumbprint
        NotAfter   = $RootCA.NotAfter.ToString("o")
    }
    ClientCert = @{
        Subject    = "CN=$ClientCertName"
        Thumbprint = $ClientCert.Thumbprint
        Issuer     = $ClientCert.Issuer
        NotAfter   = $ClientCert.NotAfter.ToString("o")
    }
} | ConvertTo-Json -Depth 3 | Out-File (Join-Path $OutputDir "pki-info.json") -Encoding utf8
