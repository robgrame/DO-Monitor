<#
.SYNOPSIS
    Step 3 — Build and publish Azure Functions (.NET 10).
.DESCRIPTION
    Builds the .NET 10 Function App project, creates a publish package,
    and deploys it to Azure via zip deployment.
.EXAMPLE
    .\03-Build-And-Publish-Functions.ps1
    .\03-Build-And-Publish-Functions.ps1 -BuildOnly
    .\03-Build-And-Publish-Functions.ps1 -Configuration Debug
#>

[CmdletBinding()]
param(
    [switch]$BuildOnly,
    [ValidateSet("Release", "Debug")]
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Step 3: Build & Publish Functions (.NET 10)" -ForegroundColor Cyan
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

# Paths
$SolutionPath = Join-Path $Config.FunctionsPath "DO-Monitor.Functions.sln"
$ProjectPath = Join-Path $Config.FunctionsPath "src\DO-Monitor.Functions\DO-Monitor.Functions.csproj"
$PublishPath = Join-Path $PSScriptRoot "publish"
$ZipPath = Join-Path $PSScriptRoot "functions.zip"

# Step 1: Verify prerequisites
Write-Host "`n[1/4] Checking prerequisites..." -ForegroundColor Yellow

$DotnetVersion = dotnet --version 2>$null
if (-not $DotnetVersion) {
    Write-Error ".NET SDK not found. Install .NET 10 SDK from https://dot.net"
    exit 1
}
Write-Host "  .NET SDK: $DotnetVersion" -ForegroundColor Green

if (-not $DotnetVersion.StartsWith("10.")) {
    Write-Warning "  Expected .NET 10, found $DotnetVersion. Build may fail."
}

# Step 2: Restore packages
Write-Host "`n[2/4] Restoring NuGet packages..." -ForegroundColor Yellow
dotnet restore $ProjectPath --verbosity quiet
if ($LASTEXITCODE -ne 0) {
    Write-Error "NuGet restore failed!"
    exit 1
}
Write-Host "  Packages restored." -ForegroundColor Green

# Step 3: Build and publish
Write-Host "`n[3/4] Building and publishing ($Configuration)..." -ForegroundColor Yellow

if (Test-Path $PublishPath) { Remove-Item -Path $PublishPath -Recurse -Force }

dotnet publish $ProjectPath `
    --configuration $Configuration `
    --output $PublishPath `
    --verbosity quiet `
    --no-restore

if ($LASTEXITCODE -ne 0) {
    Write-Error "Build failed!"
    exit 1
}

# Create zip package
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path "$PublishPath\*" -DestinationPath $ZipPath -Force

$ZipSize = [math]::Round((Get-Item $ZipPath).Length / 1MB, 2)
Write-Host "  Build succeeded: functions.zip ($ZipSize MB)" -ForegroundColor Green

if ($BuildOnly) {
    Write-Host "`n  Build-only mode. Skipping publish." -ForegroundColor Yellow
    Remove-Item -Path $PublishPath -Recurse -Force -ErrorAction SilentlyContinue
    exit 0
}

# Step 4: Deploy to Azure
Write-Host "`n[4/4] Deploying to Azure Function App: $FunctionAppName ..." -ForegroundColor Yellow

az functionapp deployment source config-zip `
    --resource-group $Config.ResourceGroupName `
    --name $FunctionAppName `
    --src $ZipPath `
    --build-remote false `
    --output none

if ($LASTEXITCODE -ne 0) {
    Write-Error "Deployment failed!"
    exit 1
}

# Restart Function App to pick up new code
Write-Host "  Restarting Function App..." -ForegroundColor Gray
az functionapp restart `
    --resource-group $Config.ResourceGroupName `
    --name $FunctionAppName `
    --output none

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Functions published successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Function App:    $FunctionAppName" -ForegroundColor White
Write-Host "  Runtime:         .NET 10 (isolated worker)" -ForegroundColor White
Write-Host "  Configuration:   $Configuration" -ForegroundColor White
Write-Host "  Functions:       DOIngest (HTTP), DOProcessor (SB Trigger)" -ForegroundColor White
Write-Host ""

# Cleanup
Remove-Item -Path $PublishPath -Recurse -Force -ErrorAction SilentlyContinue
