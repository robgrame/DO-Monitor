<#
.SYNOPSIS
    Step 4 — Deploy Workbook and Alert Rules.
.DESCRIPTION
    Deploys the Azure Workbook dashboard and Scheduled Query Alert Rules
    via ARM template deployment.
.EXAMPLE
    .\04-Deploy-Monitoring.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 4: Deploy Monitoring" -ForegroundColor Cyan
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

# Resolve workspace ID from outputs (handles both greenfield and existing workspace)
$WorkspaceId = $Outputs.logAnalyticsWorkspaceId.value
if (-not $WorkspaceId) {
    $WorkspaceId = $Config.LogAnalyticsWorkspaceId
}
if (-not $WorkspaceId) {
    Write-Error "Log Analytics workspace ID not found in outputs or config."
    exit 1
}
Write-Host "  Workspace ID: $WorkspaceId" -ForegroundColor Gray

# ---- Deploy Workbooks ----
Write-Host "`n[1/2] Deploying Azure Workbooks..." -ForegroundColor Yellow

$Workbooks = @(
    @{ File = "DO-Monitor-Workbook.json";     Label = "Overview" }
    @{ File = "DO-Efficiency-Workbook.json";  Label = "Efficiency" }
    @{ File = "DO-Network-Workbook.json";     Label = "Network" }
    @{ File = "DO-Packages-Workbook.json";    Label = "Packages & Traffic Type" }
)

foreach ($wb in $Workbooks) {
    $WorkbookTemplate = Join-Path $Config.WorkbooksPath $wb.File
    if (-not (Test-Path $WorkbookTemplate)) {
        Write-Warning "  [$($wb.Label)] template not found: $WorkbookTemplate"
        continue
    }

    $WorkbookDeployment = "domonitor-wb-$([IO.Path]::GetFileNameWithoutExtension($wb.File))-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Write-Host "  - Deploying $($wb.Label)..." -ForegroundColor Gray

    az deployment group create `
        --name $WorkbookDeployment `
        --resource-group $Config.ResourceGroupName `
        --template-file $WorkbookTemplate `
        --parameters workbookSourceId=$WorkspaceId `
        --output none

    if ($LASTEXITCODE -eq 0) {
        Write-Host "    OK: $($wb.Label) deployed." -ForegroundColor Green
    } else {
        Write-Warning "    FAILED: $($wb.Label). Deploy it manually from the Azure Portal."
    }
}

# ---- Deploy Alert Rules ----
Write-Host "`n[2/2] Deploying Alert Rules..." -ForegroundColor Yellow

$AlertTemplate = Join-Path $Config.AlertsPath "DO-Alert-Rules.json"
if (Test-Path $AlertTemplate) {
    # Check if an Action Group exists, or create a placeholder
    Write-Host "  Checking for existing Action Group..." -ForegroundColor Gray
    $ActionGroupId = az monitor action-group list `
        --resource-group $Config.ResourceGroupName `
        --query "[0].id" -o tsv 2>$null

    if (-not $ActionGroupId) {
        Write-Host "  Creating default Action Group..." -ForegroundColor Yellow
        az monitor action-group create `
            --resource-group $Config.ResourceGroupName `
            --name "DO-Monitor-Alerts" `
            --short-name "DOMonAlerts" `
            --output none

        $ActionGroupId = az monitor action-group show `
            --resource-group $Config.ResourceGroupName `
            --name "DO-Monitor-Alerts" `
            --query "id" -o tsv
    }

    Write-Host "  Action Group: $ActionGroupId" -ForegroundColor Gray

    $AlertDeployment = "domonitor-alerts-$(Get-Date -Format 'yyyyMMdd-HHmmss')"

    az deployment group create `
        --name $AlertDeployment `
        --resource-group $Config.ResourceGroupName `
        --template-file $AlertTemplate `
        --parameters `
            workspaceResourceId=$WorkspaceId `
            actionGroupResourceId=$ActionGroupId `
        --output none

    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Alert Rules deployed successfully." -ForegroundColor Green
    } else {
        Write-Warning "  Alert Rules deployment failed. You can deploy them manually."
    }
} else {
    Write-Warning "  Alert Rules template not found at: $AlertTemplate"
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Monitoring deployed successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Workbooks:   Overview, Efficiency, Network, Packages" -ForegroundColor White
Write-Host "  Alerts:      3 Scheduled Query Rules" -ForegroundColor White
Write-Host "  Action Group: DO-Monitor-Alerts" -ForegroundColor White
Write-Host ""
Write-Host "  Note: Configure email/Teams notifications in the Action Group" -ForegroundColor Yellow
Write-Host "        via Azure Portal > Monitor > Action Groups" -ForegroundColor Yellow
Write-Host ""
