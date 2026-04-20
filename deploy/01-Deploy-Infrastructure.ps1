<#
.SYNOPSIS
    Step 1 — Deploy Azure infrastructure via Bicep.
.DESCRIPTION
    Deploys all infrastructure resources for DO-Monitor:
    Key Vault, App Configuration, Storage, Service Bus,
    Data Collection (DCE/DCR), App Insights, Function App.
.EXAMPLE
    .\01-Deploy-Infrastructure.ps1
#>

[CmdletBinding()]
param(
    [switch]$WhatIf
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 1: Deploy Infrastructure" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Load configuration
$Config = & "$PSScriptRoot\Config.ps1"

# Verify Azure CLI is logged in
Write-Host "`n[1/4] Verifying Azure CLI login..." -ForegroundColor Yellow
$Account = az account show --query "{name:name, id:id}" -o json 2>$null | ConvertFrom-Json
if (-not $Account) {
    Write-Host "  Not logged in. Running 'az login'..." -ForegroundColor Yellow
    az login
    $Account = az account show --query "{name:name, id:id}" -o json | ConvertFrom-Json
}
Write-Host "  Subscription: $($Account.name) ($($Account.id))" -ForegroundColor Green

# Set subscription
Write-Host "`n[2/4] Setting subscription..." -ForegroundColor Yellow
az account set --subscription $Config.SubscriptionId
Write-Host "  Subscription set to: $($Config.SubscriptionId)" -ForegroundColor Green

# Create resource group if not exists
Write-Host "`n[3/4] Creating resource group..." -ForegroundColor Yellow
az group create `
    --name $Config.ResourceGroupName `
    --location $Config.Location `
    --tags "Project=DO-Monitor" "Environment=$($Config.Environment)" "ManagedBy=Bicep" `
    --output none
Write-Host "  Resource group: $($Config.ResourceGroupName)" -ForegroundColor Green

# Get deployer principal ID
$DeployerPrincipalId = az ad signed-in-user show --query id -o tsv 2>$null
if (-not $DeployerPrincipalId) {
    Write-Host "  Warning: Could not get deployer principal ID. Key Vault deployer role will not be assigned." -ForegroundColor Yellow
    $DeployerPrincipalId = ""
}

# Deploy Bicep
Write-Host "`n[4/4] Deploying Bicep template..." -ForegroundColor Yellow
$DeploymentName = "domonitor-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

$BicepParams = @(
    "--name", $DeploymentName
    "--resource-group", $Config.ResourceGroupName
    "--template-file", (Join-Path $Config.InfraPath "main.bicep")
    "--parameters",
        "baseName=$($Config.BaseName)",
        "environment=$($Config.Environment)",
        "logAnalyticsWorkspaceId=$($Config.LogAnalyticsWorkspaceId)",
        "deployerPrincipalId=$DeployerPrincipalId"
    "--output", "json"
)

if ($WhatIf) {
    Write-Host "  Running what-if analysis..." -ForegroundColor Yellow
    az deployment group what-if @BicepParams
} else {
    $Result = az deployment group create @BicepParams | ConvertFrom-Json

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment failed!"
        exit 1
    }

    Write-Host "`n========================================" -ForegroundColor Green
    Write-Host " Infrastructure deployed successfully!" -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
    Write-Host ""
    Write-Host "  Function App:    $($Result.properties.outputs.functionAppName.value)" -ForegroundColor White
    Write-Host "  Function URL:    $($Result.properties.outputs.functionAppUrl.value)" -ForegroundColor White
    Write-Host "  Key Vault:       $($Result.properties.outputs.keyVaultName.value)" -ForegroundColor White
    Write-Host "  App Config:      $($Result.properties.outputs.appConfigName.value)" -ForegroundColor White
    Write-Host "  Service Bus:     $($Result.properties.outputs.serviceBusName.value)" -ForegroundColor White
    Write-Host "  DCE Endpoint:    $($Result.properties.outputs.dceEndpoint.value)" -ForegroundColor White
    Write-Host ""

    # Save outputs for subsequent scripts
    $OutputsFile = Join-Path $PSScriptRoot "deployment-outputs.json"
    $Result.properties.outputs | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputsFile -Encoding utf8
    Write-Host "  Outputs saved to: $OutputsFile" -ForegroundColor Gray
}
