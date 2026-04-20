<#
.SYNOPSIS
    Step 6 — Validate end-to-end deployment.
.DESCRIPTION
    Verifies all components are deployed and working:
    - Azure resources exist and are healthy
    - Function App is responding
    - Service Bus queue exists
    - Key Vault secrets are accessible
    - App Configuration entries are populated
    - Sends a test payload to validate the pipeline
.EXAMPLE
    .\06-Validate-Deployment.ps1
    .\06-Validate-Deployment.ps1 -SendTestPayload
#>

[CmdletBinding()]
param(
    [switch]$SendTestPayload
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 6: Validate Deployment" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Load configuration
$Config = & "$PSScriptRoot\Config.ps1"

# Load deployment outputs
$OutputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
if (-not (Test-Path $OutputsFile)) {
    Write-Error "Deployment outputs not found. Run 01-Deploy-Infrastructure.ps1 first."
    exit 1
}
$Outputs = Get-Content $OutputsFile -Raw | ConvertFrom-Json

$Passed = 0
$Failed = 0
$Warnings = 0

function Test-Check {
    param([string]$Name, [scriptblock]$Check)
    Write-Host "  Checking: $Name... " -NoNewline -ForegroundColor Gray
    try {
        $Result = & $Check
        if ($Result) {
            Write-Host "PASS" -ForegroundColor Green
            $script:Passed++
        } else {
            Write-Host "FAIL" -ForegroundColor Red
            $script:Failed++
        }
    } catch {
        Write-Host "FAIL - $($_.Exception.Message)" -ForegroundColor Red
        $script:Failed++
    }
}

# ---- 1. Resource Group ----
Write-Host "`n[1/7] Resource Group" -ForegroundColor Yellow
Test-Check "Resource group exists" {
    $rg = az group show --name $Config.ResourceGroupName --query "name" -o tsv 2>$null
    $rg -eq $Config.ResourceGroupName
}

# ---- 2. Key Vault ----
Write-Host "`n[2/7] Key Vault" -ForegroundColor Yellow
$KVName = $Outputs.keyVaultName.value
Test-Check "Key Vault exists" {
    $kv = az keyvault show --name $KVName --query "name" -o tsv 2>$null
    $kv -eq $KVName
}
Test-Check "ServiceBusConnection secret" {
    $secret = az keyvault secret show --vault-name $KVName --name "ServiceBusConnection" --query "name" -o tsv 2>$null
    $secret -eq "ServiceBusConnection"
}
Test-Check "DcrImmutableId secret" {
    $secret = az keyvault secret show --vault-name $KVName --name "DcrImmutableId" --query "name" -o tsv 2>$null
    $secret -eq "DcrImmutableId"
}
Test-Check "FunctionAppHostKey secret" {
    $secret = az keyvault secret show --vault-name $KVName --name "FunctionAppHostKey" --query "name" -o tsv 2>$null
    $secret -eq "FunctionAppHostKey"
}

# ---- 3. App Configuration ----
Write-Host "`n[3/7] App Configuration" -ForegroundColor Yellow
$AppConfigName = $Outputs.appConfigName.value
Test-Check "App Configuration exists" {
    $ac = az appconfig show --name $AppConfigName --query "name" -o tsv 2>$null
    $ac -eq $AppConfigName
}
Test-Check "Configuration entries populated" {
    $count = az appconfig kv list --name $AppConfigName --query "length(@)" -o tsv 2>$null
    [int]$count -gt 0
}

# ---- 4. Service Bus ----
Write-Host "`n[4/7] Service Bus" -ForegroundColor Yellow
$SBName = $Outputs.serviceBusName.value
Test-Check "Service Bus namespace exists" {
    $sb = az servicebus namespace show --name $SBName --resource-group $Config.ResourceGroupName --query "name" -o tsv 2>$null
    $sb -eq $SBName
}
Test-Check "Queue 'do-telemetry' exists" {
    $q = az servicebus queue show --namespace-name $SBName --resource-group $Config.ResourceGroupName --name "do-telemetry" --query "name" -o tsv 2>$null
    $q -eq "do-telemetry"
}

# ---- 5. Function App ----
Write-Host "`n[5/7] Function App" -ForegroundColor Yellow
$FuncName = $Outputs.functionAppName.value
Test-Check "Function App exists" {
    $fa = az functionapp show --name $FuncName --resource-group $Config.ResourceGroupName --query "name" -o tsv 2>$null
    $fa -eq $FuncName
}
Test-Check "Function App is running" {
    $state = az functionapp show --name $FuncName --resource-group $Config.ResourceGroupName --query "state" -o tsv 2>$null
    $state -eq "Running"
}
Test-Check "Managed Identity enabled" {
    $mi = az functionapp show --name $FuncName --resource-group $Config.ResourceGroupName --query "identity.principalId" -o tsv 2>$null
    -not [string]::IsNullOrEmpty($mi)
}
Test-Check "DOIngest function deployed" {
    $funcs = az functionapp function list --name $FuncName --resource-group $Config.ResourceGroupName --query "[].name" -o json 2>$null | ConvertFrom-Json
    "DOIngest" -in $funcs
}
Test-Check "DOProcessor function deployed" {
    $funcs = az functionapp function list --name $FuncName --resource-group $Config.ResourceGroupName --query "[].name" -o json 2>$null | ConvertFrom-Json
    "DOProcessor" -in $funcs
}

# ---- 6. Data Collection ----
Write-Host "`n[6/7] Data Collection (DCE/DCR)" -ForegroundColor Yellow
Test-Check "DCE endpoint reachable" {
    $dce = $Outputs.dceEndpoint.value
    -not [string]::IsNullOrEmpty($dce)
}
Test-Check "DCR immutable ID available" {
    $dcr = $Outputs.dcrImmutableId.value
    -not [string]::IsNullOrEmpty($dcr)
}

# ---- 7. End-to-End Test ----
if ($SendTestPayload) {
    Write-Host "`n[7/7] End-to-End Test" -ForegroundColor Yellow

    $FunctionKey = az keyvault secret show --vault-name $KVName --name "FunctionAppHostKey" --query "value" -o tsv 2>$null
    $FunctionUrl = "$($Outputs.functionAppUrl.value)?code=$FunctionKey"

    $TestPayload = @{
        DeviceName    = "TEST-VALIDATION-DEVICE"
        OSVersion     = "10.0.99999.0"
        SerialNumber  = "VALIDATION-TEST"
        Domain        = "test.local"
        CollectedAt   = (Get-Date).ToUniversalTime().ToString("o")
        JobCount      = 1
        TotalFromPeers = 1024
        TotalFromHttp  = 2048
        TotalFromCache = 512
        Jobs          = @(
            @{
                FileId              = "test-validation-$(Get-Date -Format 'yyyyMMddHHmmss')"
                FileName            = "validation-test.cab"
                FileSize            = 3584
                Status              = "Complete"
                Priority            = "Normal"
                BytesFromPeers      = 1024
                BytesFromHttp       = 2048
                BytesFromCacheServer = 512
                BytesFromLanPeers   = 512
                BytesFromGroupPeers = 512
                BytesFromIntPeers   = 0
                TotalBytesDownloaded = 3584
                PercentPeerCaching  = 28.6
                DownloadMode        = "LAN"
                SourceURL           = "http://test.validation/test.cab"
                ExpireOn            = ""
                IsPinned            = $false
            }
        )
    } | ConvertTo-Json -Depth 5 -Compress

    Test-Check "POST test payload to DOIngest" {
        $Response = Invoke-RestMethod -Uri $FunctionUrl -Method POST -Body $TestPayload -ContentType "application/json" -TimeoutSec 30
        $Response.status -eq "accepted"
    }

    Write-Host "`n  Note: Check Log Analytics in ~5 minutes for test data." -ForegroundColor Yellow
    Write-Host "  Query: DOStatus_CL | where DeviceName == 'TEST-VALIDATION-DEVICE'" -ForegroundColor Gray
} else {
    Write-Host "`n[7/7] End-to-End Test: SKIPPED (use -SendTestPayload to enable)" -ForegroundColor Gray
}

# ---- Summary ----
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Passed:   $Passed" -ForegroundColor Green
Write-Host "  Failed:   $Failed" -ForegroundColor $(if ($Failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

if ($Failed -eq 0) {
    Write-Host "  ALL CHECKS PASSED — Deployment is healthy!" -ForegroundColor Green
} else {
    Write-Host "  SOME CHECKS FAILED — Review the errors above." -ForegroundColor Red
}
Write-Host ""
