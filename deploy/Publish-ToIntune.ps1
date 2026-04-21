<#
.SYNOPSIS
    DO-Monitor — Publish Win32 app to Intune and assign to All Devices.
.DESCRIPTION
    Connects to Microsoft Graph with DeviceManagementApps.ReadWrite.All scope,
    creates the Win32 LOB app, uploads the .intunewin package, and assigns
    to All Devices as Required.

    Uses Invoke-MgGraphRequest (Microsoft Graph PowerShell SDK) for all API calls.

    Prerequisites:
    - Microsoft.Graph module installed
    - Package built (run: .\package\Build-IntunePackage.ps1)
.EXAMPLE
    .\deploy\Publish-ToIntune.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot | Split-Path
$PackagePath = Join-Path $RepoRoot "package\output\Install-DOMonitor.intunewin"
$DetectionScriptPath = Join-Path $RepoRoot "package\source\Detect-DOMonitor.ps1"
$Version = (Get-Content (Join-Path $RepoRoot "VERSION") -Raw).Trim()
$TenantId = "46b06a5e-8f7a-467b-bc9a-e776011fbb57"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " DO-Monitor — Publish to Intune" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Version: $Version" -ForegroundColor White
Write-Host "  Package: $PackagePath" -ForegroundColor Gray

if (-not (Test-Path $PackagePath)) {
    Write-Error "Package not found. Run .\package\Build-IntunePackage.ps1 first."
    exit 1
}

# ---- Connect to Graph with Intune scope ----
Write-Host "`n[1/5] Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All" -TenantId $TenantId -NoWelcome

$ctx = Get-MgContext
if (-not $ctx -or -not $ctx.TenantId) {
    Write-Error "Graph authentication failed."
    exit 1
}
Write-Host "  Connected as: $($ctx.Account) (Tenant: $($ctx.TenantId))" -ForegroundColor Green

# ---- Read detection script as base64 ----
$DetectionScriptContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($DetectionScriptPath))

# ---- Read .intunewin metadata ----
Write-Host "`n[2/5] Reading package metadata..." -ForegroundColor Yellow
Add-Type -AssemblyName System.IO.Compression.FileSystem
$IntuneWinZip = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
$MetadataEntry = $IntuneWinZip.Entries | Where-Object { $_.FullName -match "Detection.xml" }
$MetadataStream = $MetadataEntry.Open()
$MetadataReader = [System.IO.StreamReader]::new($MetadataStream)
$MetadataXml = [xml]$MetadataReader.ReadToEnd()
$MetadataReader.Close()
$IntuneWinZip.Dispose()

$EncryptionInfo = $MetadataXml.ApplicationInfo.EncryptionInfo
$SetupFile = $MetadataXml.ApplicationInfo.SetupFile
Write-Host "  Setup file: $SetupFile" -ForegroundColor Gray

# ---- Create Win32 LOB App ----
Write-Host "`n[3/5] Creating Win32 app in Intune..." -ForegroundColor Yellow

$AppBody = @{
    "@odata.type"                  = "#microsoft.graph.win32LobApp"
    displayName                    = "DO-Monitor Collector"
    description                    = "Delivery Optimization telemetry collector v$Version. Collects DO job details, performance stats, and applied policies from Windows clients."
    publisher                      = "IT Operations"
    displayVersion                 = $Version
    fileName                       = [System.IO.Path]::GetFileName($PackagePath)
    installCommandLine             = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DOMonitor.ps1"
    uninstallCommandLine           = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DOMonitor.ps1"
    installExperience              = @{
        runAsAccount               = "system"
        deviceRestartBehavior      = "suppress"
    }
    minimumSupportedOperatingSystem = @{
        v10_21H2 = $true
    }
    applicableArchitectures        = "x64"
    setupFilePath                  = $SetupFile
    detectionRules                 = @(
        @{
            "@odata.type"          = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
            scriptContent          = $DetectionScriptContent
            enforceSignatureCheck  = $false
            runAs32Bit             = $false
        }
    )
    returnCodes                    = @(
        @{ returnCode = 0;    type = "success" }
        @{ returnCode = 1707; type = "success" }
        @{ returnCode = 3010; type = "softReboot" }
        @{ returnCode = 1641; type = "hardReboot" }
        @{ returnCode = 1618; type = "retry" }
    )
}

$AppJson = $AppBody | ConvertTo-Json -Depth 10

$App = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
    -Body $AppJson -ContentType "application/json"
Write-Host "  App created: $($App.displayName) (ID: $($App.id))" -ForegroundColor Green

# ---- Upload content ----
Write-Host "`n[4/5] Uploading package content..." -ForegroundColor Yellow

# Create content version
$ContentVersion = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions" `
    -Body @{}
Write-Host "  Content version: $($ContentVersion.id)" -ForegroundColor Gray

# Create content file entry
$ContentFile = Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files" `
    -Body @{
        "@odata.type" = "#microsoft.graph.mobileAppContentFile"
        name          = [System.IO.Path]::GetFileName($PackagePath)
        size          = (Get-Item $PackagePath).Length
        sizeEncrypted = (Get-Item $PackagePath).Length
    }
Write-Host "  Content file: $($ContentFile.id)" -ForegroundColor Gray

# Wait for Azure Storage URI
Write-Host "  Waiting for upload URI..." -ForegroundColor Gray
$MaxRetries = 30
for ($i = 0; $i -lt $MaxRetries; $i++) {
    Start-Sleep -Seconds 5
    $FileStatus = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)"
    if ($FileStatus.uploadState -eq "azureStorageUriRequestSuccess") {
        Write-Host "  Upload URI ready." -ForegroundColor Green
        break
    }
    if ($i -eq ($MaxRetries - 1)) {
        Write-Error "Timed out waiting for upload URI. State: $($FileStatus.uploadState)"
        exit 1
    }
}

# Upload file to Azure Storage (direct, no Graph auth needed)
$UploadUri = $FileStatus.azureStorageUri
$FileBytes = [System.IO.File]::ReadAllBytes($PackagePath)

$BlockId = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("0000"))
Invoke-RestMethod -Uri "$UploadUri&comp=block&blockid=$BlockId" -Method PUT -Body $FileBytes `
    -ContentType "application/octet-stream" -Headers @{ "x-ms-blob-type" = "BlockBlob" }

$BlockListXml = '<?xml version="1.0" encoding="utf-8"?><BlockList><Latest>' + $BlockId + '</Latest></BlockList>'
Invoke-RestMethod -Uri "$UploadUri&comp=blocklist" -Method PUT -Body $BlockListXml -ContentType "application/xml"

Write-Host "  File uploaded ($([math]::Round($FileBytes.Length/1KB, 1)) KB)" -ForegroundColor Green

# Commit the file with encryption info
Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)/commit" `
    -Body @{
        fileEncryptionInfo = @{
            encryptionKey        = $EncryptionInfo.EncryptionKey
            macKey               = $EncryptionInfo.macKey
            initializationVector = $EncryptionInfo.initializationVector
            mac                  = $EncryptionInfo.mac
            profileIdentifier    = $EncryptionInfo.profileIdentifier
            fileDigest           = $EncryptionInfo.fileDigest
            fileDigestAlgorithm  = $EncryptionInfo.fileDigestAlgorithm
        }
    }

# Wait for content processing
Write-Host "  Waiting for content processing..." -ForegroundColor Gray
for ($i = 0; $i -lt $MaxRetries; $i++) {
    Start-Sleep -Seconds 5
    $FileStatus = Invoke-MgGraphRequest -Method GET `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)"
    if ($FileStatus.uploadState -eq "commitFileSuccess") {
        Write-Host "  Content processed." -ForegroundColor Green
        break
    }
    if ($FileStatus.uploadState -eq "commitFileFailed") {
        Write-Error "Content processing failed."
        exit 1
    }
}

# Set committed content version
Invoke-MgGraphRequest -Method PATCH `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)" `
    -Body @{ "@odata.type" = "#microsoft.graph.win32LobApp"; committedContentVersion = $ContentVersion.id }

# ---- Assign to All Devices ----
Write-Host "`n[5/5] Assigning to All Devices (Required)..." -ForegroundColor Yellow

Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/assign" `
    -Body @{
        mobileAppAssignments = @(
            @{
                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                intent        = "required"
                target        = @{ "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget" }
                settings      = @{
                    "@odata.type"                = "#microsoft.graph.win32LobAppAssignmentSettings"
                    notifications                = "hideAll"
                    deliveryOptimizationPriority = "foreground"
                }
            }
        )
    }

Write-Host "  Assigned to All Devices." -ForegroundColor Green

# ---- Summary ----
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Published to Intune successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  App Name:     DO-Monitor Collector" -ForegroundColor White
Write-Host "  App ID:       $($App.id)" -ForegroundColor White
Write-Host "  Version:      $Version" -ForegroundColor White
Write-Host "  Assignment:   All Devices (Required)" -ForegroundColor White
Write-Host ""

$App.id | Out-File -FilePath (Join-Path $PSScriptRoot "intune-app-id.txt") -Encoding utf8
