<#
.SYNOPSIS
    Manage trusted CA chains in App Configuration for client certificate validation.
.DESCRIPTION
    Add, list, or remove trusted CA chains used by the Function App middleware
    to validate client certificates (mTLS). Multiple chains are supported
    to allow certificate rotation and multi-CA scenarios.

    After modifying chains, update the Sentinel key to trigger hot-reload
    in the Function App (no restart needed).
.EXAMPLE
    # List current chains
    .\Manage-TrustedCAChains.ps1 -Action List

    # Add a new CA chain
    .\Manage-TrustedCAChains.ps1 -Action Add -ChainName "Production CA 2026" `
        -RootCaThumbprint "A1B2C3..." `
        -SubCaThumbprints "D4E5F6...", "G7H8I9..."

    # Remove a chain by index
    .\Manage-TrustedCAChains.ps1 -Action Remove -ChainIndex 1

    # Enable certificate validation (disable bypass)
    .\Manage-TrustedCAChains.ps1 -Action Enable

    # Disable certificate validation (for development)
    .\Manage-TrustedCAChains.ps1 -Action Disable
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("List", "Add", "Remove", "Enable", "Disable")]
    [string]$Action,

    [string]$ChainName,
    [string]$RootCaThumbprint,
    [string[]]$SubCaThumbprints,
    [int]$ChainIndex = -1
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# Load configuration
$Config = & "$PSScriptRoot\Config.ps1"
$OutputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
if (-not (Test-Path $OutputsFile)) {
    Write-Error "Deployment outputs not found. Run 01-Deploy-Infrastructure.ps1 first."
    exit 1
}
$Outputs = Get-Content $OutputsFile -Raw | ConvertFrom-Json
$AppConfigName = $Outputs.appConfigName.value

$Prefix = "DO-Monitor:CertificateValidation:TrustedChains"
$Label = "prod"

function Bump-Sentinel {
    $sentinel = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString()
    az appconfig kv set --name $AppConfigName --key "DO-Monitor:Sentinel" --value $sentinel --label $Label --yes --output none
    Write-Host "  Sentinel updated ($sentinel) — Function App will reload config within 5 minutes." -ForegroundColor Gray
}

switch ($Action) {
    "List" {
        Write-Host "`n=== Trusted CA Chains ===" -ForegroundColor Cyan

        $DisableVal = az appconfig kv show --name $AppConfigName --key "DO-Monitor:CertificateValidation:DisableValidation" --label $Label --query "value" -o tsv 2>$null
        if ($DisableVal -eq "true") {
            Write-Host "  ⚠ Certificate validation is DISABLED" -ForegroundColor Yellow
        } else {
            Write-Host "  ✓ Certificate validation is ENABLED" -ForegroundColor Green
        }

        $AllKeys = az appconfig kv list --name $AppConfigName --key "$Prefix:*" --label $Label --query "[].{key:key, value:value}" -o json 2>$null | ConvertFrom-Json

        if (-not $AllKeys -or $AllKeys.Count -eq 0) {
            Write-Host "`n  No trusted CA chains configured." -ForegroundColor Yellow
            return
        }

        # Parse chain indices
        $indices = $AllKeys | ForEach-Object {
            if ($_.key -match "TrustedChains:(\d+):") { [int]$Matches[1] }
        } | Sort-Object -Unique

        foreach ($i in $indices) {
            $name = ($AllKeys | Where-Object { $_.key -eq "${Prefix}:${i}:Name" }).value
            $root = ($AllKeys | Where-Object { $_.key -eq "${Prefix}:${i}:RootCaThumbprint" }).value
            $subs = $AllKeys | Where-Object { $_.key -match "${Prefix}:${i}:SubCaThumbprints:" } | ForEach-Object { $_.value }

            Write-Host ""
            Write-Host "  Chain [$i]: $name" -ForegroundColor White
            Write-Host "    Root CA:  $root" -ForegroundColor Gray
            foreach ($sub in $subs) {
                Write-Host "    Sub CA:   $sub" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }

    "Add" {
        if (-not $ChainName -or -not $RootCaThumbprint -or -not $SubCaThumbprints) {
            Write-Error "Add requires -ChainName, -RootCaThumbprint, and -SubCaThumbprints parameters."
            exit 1
        }

        Write-Host "`n=== Adding Trusted CA Chain ===" -ForegroundColor Cyan

        # Find next available index
        $AllKeys = az appconfig kv list --name $AppConfigName --key "$Prefix:*" --label $Label --query "[].key" -o json 2>$null | ConvertFrom-Json
        $maxIndex = -1
        if ($AllKeys) {
            $AllKeys | ForEach-Object {
                if ($_ -match "TrustedChains:(\d+):") { $maxIndex = [math]::Max($maxIndex, [int]$Matches[1]) }
            }
        }
        $newIndex = $maxIndex + 1

        Write-Host "  Chain index: $newIndex" -ForegroundColor Gray
        Write-Host "  Name:        $ChainName" -ForegroundColor White
        Write-Host "  Root CA:     $RootCaThumbprint" -ForegroundColor White

        az appconfig kv set --name $AppConfigName --key "${Prefix}:${newIndex}:Name" --value $ChainName --label $Label --yes --output none
        az appconfig kv set --name $AppConfigName --key "${Prefix}:${newIndex}:RootCaThumbprint" --value $RootCaThumbprint --label $Label --yes --output none

        for ($s = 0; $s -lt $SubCaThumbprints.Count; $s++) {
            Write-Host "  Sub CA [$s]:  $($SubCaThumbprints[$s])" -ForegroundColor White
            az appconfig kv set --name $AppConfigName --key "${Prefix}:${newIndex}:SubCaThumbprints:${s}" --value $SubCaThumbprints[$s] --label $Label --yes --output none
        }

        Bump-Sentinel
        Write-Host "`n  ✓ Chain '$ChainName' added at index $newIndex." -ForegroundColor Green
    }

    "Remove" {
        if ($ChainIndex -lt 0) {
            Write-Error "Remove requires -ChainIndex parameter. Use -Action List to see indices."
            exit 1
        }

        Write-Host "`n=== Removing Trusted CA Chain [$ChainIndex] ===" -ForegroundColor Cyan

        $KeysToDelete = az appconfig kv list --name $AppConfigName --key "${Prefix}:${ChainIndex}:*" --label $Label --query "[].key" -o json 2>$null | ConvertFrom-Json

        if (-not $KeysToDelete -or $KeysToDelete.Count -eq 0) {
            Write-Error "No chain found at index $ChainIndex."
            exit 1
        }

        foreach ($key in $KeysToDelete) {
            Write-Host "  Deleting: $key" -ForegroundColor Gray
            az appconfig kv delete --name $AppConfigName --key $key --label $Label --yes --output none
        }

        Bump-Sentinel
        Write-Host "`n  ✓ Chain [$ChainIndex] removed ($($KeysToDelete.Count) keys deleted)." -ForegroundColor Green
    }

    "Enable" {
        Write-Host "`n=== Enabling Certificate Validation ===" -ForegroundColor Cyan
        az appconfig kv set --name $AppConfigName --key "DO-Monitor:CertificateValidation:DisableValidation" --value "false" --label $Label --yes --output none
        Bump-Sentinel
        Write-Host "  ✓ Certificate validation ENABLED." -ForegroundColor Green
    }

    "Disable" {
        Write-Host "`n=== Disabling Certificate Validation ===" -ForegroundColor Yellow
        az appconfig kv set --name $AppConfigName --key "DO-Monitor:CertificateValidation:DisableValidation" --value "true" --label $Label --yes --output none
        Bump-Sentinel
        Write-Host "  ⚠ Certificate validation DISABLED. All certificates will be accepted." -ForegroundColor Yellow
    }
}
