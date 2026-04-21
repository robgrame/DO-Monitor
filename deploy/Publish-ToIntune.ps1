<#
.SYNOPSIS
    DO-Monitor — Publish Win32 app to Intune and assign to All Devices.
.DESCRIPTION
    Connects to Microsoft Graph via az cli, creates the Win32 app in Intune
    using Graph REST APIs, uploads the .intunewin package, configures
    detection/install/uninstall, and assigns to All Devices as Required.

    Prerequisites:
    - az cli logged in to the Intune tenant (run: az login --tenant <tenantId>)
    - Package built (run: .\package\Build-IntunePackage.ps1)
.EXAMPLE
    az login --tenant 46b06a5e-8f7a-467b-bc9a-e776011fbb57
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

# ---- Verify az cli auth ----
Write-Host "`n[1/5] Verifying Azure CLI login..." -ForegroundColor Yellow
$Account = az account show --query "{tenant:tenantId, user:user.name}" -o json 2>$null | ConvertFrom-Json
if (-not $Account) {
    Write-Host "  Not logged in. Run: az login --tenant $TenantId" -ForegroundColor Red
    exit 1
}
Write-Host "  Logged in as: $($Account.user) (Tenant: $($Account.tenant))" -ForegroundColor Green

# ---- Get access token for Graph ----
Write-Host "`n[2/5] Getting Graph access token..." -ForegroundColor Yellow
$Token = az account get-access-token --resource "https://graph.microsoft.com" --query "accessToken" -o tsv
if (-not $Token) {
    Write-Error "Failed to get Graph access token."
    exit 1
}
$Headers = @{
    "Authorization" = "Bearer $Token"
    "Content-Type"  = "application/json"
}
Write-Host "  Token acquired." -ForegroundColor Green

# ---- Read detection script as base64 ----
$DetectionScriptContent = [Convert]::ToBase64String([System.IO.File]::ReadAllBytes($DetectionScriptPath))

# ---- Create Win32 LOB App ----
Write-Host "`n[3/5] Creating Win32 app in Intune..." -ForegroundColor Yellow

# Read the .intunewin to get metadata
Add-Type -AssemblyName System.IO.Compression.FileSystem
$IntuneWinZip = [System.IO.Compression.ZipFile]::OpenRead($PackagePath)
$MetadataEntry = $IntuneWinZip.Entries | Where-Object { $_.FullName -match "Detection.xml" }
$MetadataStream = $MetadataEntry.Open()
$MetadataReader = [System.IO.StreamReader]::new($MetadataStream)
$MetadataXml = [xml]$MetadataReader.ReadToEnd()
$MetadataReader.Close()
$IntuneWinZip.Dispose()

$EncryptionInfo = $MetadataXml.ApplicationInfo.EncryptionInfo
$FileSize = [long]$MetadataXml.ApplicationInfo.UnencryptedContentSize
$SetupFile = $MetadataXml.ApplicationInfo.SetupFile

$AppBody = @{
    "@odata.type"                    = "#microsoft.graph.win32LobApp"
    displayName                      = "DO-Monitor Collector"
    description                      = "Delivery Optimization telemetry collector v$Version. Collects DO job details, performance stats, and applied policies from Windows clients."
    publisher                        = "IT Operations"
    displayVersion                   = $Version
    installCommandLine               = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Install-DOMonitor.ps1"
    uninstallCommandLine             = "powershell.exe -NoProfile -ExecutionPolicy Bypass -File Uninstall-DOMonitor.ps1"
    installExperience                = @{
        runAsAccount                 = "system"
        deviceRestartBehavior        = "suppress"
    }
    minimumSupportedWindowsRelease   = "v10_21H2"
    applicableArchitectures          = "x64"
    setupFilePath                    = $SetupFile
    detectionRules                   = @(
        @{
            "@odata.type"            = "#microsoft.graph.win32LobAppPowerShellScriptDetection"
            scriptContent            = $DetectionScriptContent
            enforceSignatureCheck    = $false
            runAs32Bit               = $false
        }
    )
    returnCodes                      = @(
        @{ returnCode = 0;    type = "success" }
        @{ returnCode = 1707; type = "success" }
        @{ returnCode = 3010; type = "softReboot" }
        @{ returnCode = 1641; type = "hardReboot" }
        @{ returnCode = 1618; type = "retry" }
    )
} | ConvertTo-Json -Depth 10

$App = Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
    -Method POST -Headers $Headers -Body $AppBody
Write-Host "  App created: $($App.displayName) (ID: $($App.id))" -ForegroundColor Green

# ---- Upload content ----
Write-Host "`n[4/5] Uploading package content..." -ForegroundColor Yellow

# Create content version
$ContentVersion = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions" `
    -Method POST -Headers $Headers -Body "{}"
Write-Host "  Content version: $($ContentVersion.id)" -ForegroundColor Gray

# Create content file
$FileBody = @{
    "@odata.type" = "#microsoft.graph.mobileAppContentFile"
    name          = [System.IO.Path]::GetFileName($PackagePath)
    size          = (Get-Item $PackagePath).Length
    sizeEncrypted = (Get-Item $PackagePath).Length
} | ConvertTo-Json

$ContentFile = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files" `
    -Method POST -Headers $Headers -Body $FileBody
Write-Host "  Content file created: $($ContentFile.id)" -ForegroundColor Gray

# Wait for Azure Storage URI
Write-Host "  Waiting for upload URI..." -ForegroundColor Gray
$MaxRetries = 30
for ($i = 0; $i -lt $MaxRetries; $i++) {
    Start-Sleep -Seconds 5
    $FileStatus = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)" `
        -Headers $Headers
    if ($FileStatus.uploadState -eq "azureStorageUriRequestSuccess") {
        Write-Host "  Upload URI ready." -ForegroundColor Green
        break
    }
    if ($i -eq ($MaxRetries - 1)) {
        Write-Error "Timed out waiting for upload URI. State: $($FileStatus.uploadState)"
        exit 1
    }
}

# Upload file to Azure Storage
$UploadUri = $FileStatus.azureStorageUri
$FileBytes = [System.IO.File]::ReadAllBytes($PackagePath)

# Upload as single block (small file)
$BlockId = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("0000"))
$UploadBlockUri = "$UploadUri&comp=block&blockid=$BlockId"
Invoke-RestMethod -Uri $UploadBlockUri -Method PUT -Body $FileBytes -ContentType "application/octet-stream" -Headers @{ "x-ms-blob-type" = "BlockBlob" }

# Commit block list
$BlockListXml = "<?xml version=`"1.0`" encoding=`"utf-8`"?><BlockList><Latest>$BlockId</Latest></BlockList>"
Invoke-RestMethod -Uri "$UploadUri&comp=blocklist" -Method PUT -Body $BlockListXml -ContentType "application/xml"

Write-Host "  File uploaded ($([math]::Round($FileBytes.Length/1KB, 1)) KB)" -ForegroundColor Green

# Commit the file
$CommitBody = @{
    fileEncryptionInfo = @{
        encryptionKey        = $EncryptionInfo.EncryptionKey
        macKey               = $EncryptionInfo.macKey
        initializationVector = $EncryptionInfo.initializationVector
        mac                  = $EncryptionInfo.mac
        profileIdentifier    = $EncryptionInfo.profileIdentifier
        fileDigest           = $EncryptionInfo.fileDigest
        fileDigestAlgorithm  = $EncryptionInfo.fileDigestAlgorithm
    }
} | ConvertTo-Json -Depth 5

Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)/commit" `
    -Method POST -Headers $Headers -Body $CommitBody

# Wait for processing
Write-Host "  Waiting for content processing..." -ForegroundColor Gray
for ($i = 0; $i -lt $MaxRetries; $i++) {
    Start-Sleep -Seconds 5
    $FileStatus = Invoke-RestMethod `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/microsoft.graph.win32LobApp/contentVersions/$($ContentVersion.id)/files/$($ContentFile.id)" `
        -Headers $Headers
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
$UpdateBody = @{ "@odata.type" = "#microsoft.graph.win32LobApp"; committedContentVersion = $ContentVersion.id } | ConvertTo-Json
Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)" `
    -Method PATCH -Headers $Headers -Body $UpdateBody

# ---- Assign to All Devices ----
Write-Host "`n[5/5] Assigning to All Devices (Required)..." -ForegroundColor Yellow

$AssignmentBody = @{
    mobileAppAssignments = @(
        @{
            "@odata.type" = "#microsoft.graph.mobileAppAssignment"
            intent        = "required"
            target        = @{
                "@odata.type" = "#microsoft.graph.allDevicesAssignmentTarget"
            }
            settings      = @{
                "@odata.type"          = "#microsoft.graph.win32LobAppAssignmentSettings"
                notifications          = "hideAll"
                deliveryOptimizationPriority = "foreground"
                installTimeSettings    = $null
                restartSettings        = $null
            }
        }
    )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($App.id)/assign" `
    -Method POST -Headers $Headers -Body $AssignmentBody

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
