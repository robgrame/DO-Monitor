<#
.SYNOPSIS
    Step 3 — Build and publish Azure Functions.
.DESCRIPTION
    Builds the Function App package and publishes it to Azure.
    Requires Azure Functions Core Tools (func) to be installed.
.EXAMPLE
    .\03-Build-And-Publish-Functions.ps1
#>

[CmdletBinding()]
param(
    [switch]$BuildOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 3: Build & Publish Functions" -ForegroundColor Cyan
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
$FunctionAppName = $Outputs.functionAppName.value

# Step 1: Verify prerequisites
Write-Host "`n[1/4] Checking prerequisites..." -ForegroundColor Yellow

$FuncVersion = func --version 2>$null
if (-not $FuncVersion) {
    Write-Error "Azure Functions Core Tools not found. Install with: npm install -g azure-functions-core-tools@4 --unsafe-perm true"
    exit 1
}
Write-Host "  Azure Functions Core Tools: v$FuncVersion" -ForegroundColor Green

# Step 2: Validate function structure
Write-Host "`n[2/4] Validating function structure..." -ForegroundColor Yellow

$FunctionsPath = $Config.FunctionsPath
$RequiredFiles = @(
    "host.json",
    "requirements.psd1",
    "DOIngest\function.json",
    "DOIngest\run.ps1",
    "DOProcessor\function.json",
    "DOProcessor\run.ps1"
)

$MissingFiles = @()
foreach ($File in $RequiredFiles) {
    $FullPath = Join-Path $FunctionsPath $File
    if (-not (Test-Path $FullPath)) {
        $MissingFiles += $File
    }
}

if ($MissingFiles.Count -gt 0) {
    Write-Error "Missing function files:`n  $($MissingFiles -join "`n  ")"
    exit 1
}
Write-Host "  All function files present." -ForegroundColor Green

# Step 3: Build (package)
Write-Host "`n[3/4] Building function package..." -ForegroundColor Yellow

$BuildOutput = Join-Path $PSScriptRoot "publish"
if (Test-Path $BuildOutput) {
    Remove-Item -Path $BuildOutput -Recurse -Force
}
New-Item -ItemType Directory -Path $BuildOutput -Force | Out-Null

# Copy function files to publish folder
$FilesToCopy = @(
    "host.json",
    "requirements.psd1",
    "profile.ps1",
    "DOIngest",
    "DOProcessor"
)

foreach ($Item in $FilesToCopy) {
    $Source = Join-Path $FunctionsPath $Item
    if (Test-Path $Source) {
        $Dest = Join-Path $BuildOutput $Item
        if ((Get-Item $Source).PSIsContainer) {
            Copy-Item -Path $Source -Destination $Dest -Recurse -Force
        } else {
            Copy-Item -Path $Source -Destination $Dest -Force
        }
    }
}

# Create zip package
$ZipPath = Join-Path $PSScriptRoot "functions.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$BuildOutput\*" -DestinationPath $ZipPath -Force

$ZipSize = [math]::Round((Get-Item $ZipPath).Length / 1KB, 1)
Write-Host "  Package built: functions.zip ($ZipSize KB)" -ForegroundColor Green

if ($BuildOnly) {
    Write-Host "`n  Build-only mode. Skipping publish." -ForegroundColor Yellow
    exit 0
}

# Step 4: Publish to Azure
Write-Host "`n[4/4] Publishing to Azure Function App: $FunctionAppName ..." -ForegroundColor Yellow

Push-Location $BuildOutput
try {
    func azure functionapp publish $FunctionAppName --powershell

    if ($LASTEXITCODE -ne 0) {
        Write-Warning "func publish failed. Trying az cli deployment..."
        az functionapp deployment source config-zip `
            --resource-group $Config.ResourceGroupName `
            --name $FunctionAppName `
            --src $ZipPath `
            --output none

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Deployment failed!"
            exit 1
        }
    }
} finally {
    Pop-Location
}

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Functions published successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Function App:  $FunctionAppName" -ForegroundColor White
Write-Host "  Functions:     DOIngest (HTTP), DOProcessor (SB)" -ForegroundColor White
Write-Host ""

# Cleanup
Remove-Item -Path $BuildOutput -Recurse -Force -ErrorAction SilentlyContinue
