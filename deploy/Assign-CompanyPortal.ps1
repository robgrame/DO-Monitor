<#
.SYNOPSIS
    Assigns Company Portal (Microsoft Store) to the specified Intune group.
.DESCRIPTION
    Connects to Graph with Intune scopes, finds or adds the Company Portal
    Store app, and assigns it as Required to the target group.
.EXAMPLE
    .\Assign-CompanyPortal.ps1
#>

$ErrorActionPreference = "Stop"
$TenantId = "46b06a5e-8f7a-467b-bc9a-e776011fbb57"
$GroupId = "3175a1f2-bbf1-4621-b3d3-0a3b0ad79e30"  # Intune - Windows Apps Common
$GroupName = "Intune - Windows Apps Common"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Assign Company Portal to $GroupName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# ---- Connect ----
Write-Host "`n[1/3] Connecting to Microsoft Graph..." -ForegroundColor Yellow
Connect-MgGraph -Scopes "DeviceManagementApps.ReadWrite.All" -TenantId $TenantId -NoWelcome
$ctx = Get-MgContext
if (-not $ctx -or -not $ctx.TenantId) { Write-Error "Auth failed."; exit 1 }
Write-Host "  Connected as: $($ctx.Account)" -ForegroundColor Green

# ---- Find or add Company Portal ----
Write-Host "`n[2/3] Finding Company Portal app..." -ForegroundColor Yellow

$allApps = Invoke-MgGraphRequest -Method GET `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$top=100&`$select=id,displayName"
$cpApp = $allApps.value | Where-Object { $_.displayName -match "Company Portal" } | Select-Object -First 1

if (-not $cpApp) {
    Write-Host "  Company Portal not found. Adding from Microsoft Store..." -ForegroundColor Yellow
    $cpApp = Invoke-MgGraphRequest -Method POST `
        -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps" `
        -Body (@{
            "@odata.type"        = "#microsoft.graph.winGetApp"
            displayName          = "Company Portal"
            description          = "Microsoft Intune Company Portal"
            publisher            = "Microsoft Corporation"
            packageIdentifier    = "9WZDNCRFJ3PZ"
            installExperience    = @{ runAsAccount = "system" }
        } | ConvertTo-Json -Depth 5) `
        -ContentType "application/json"
    Write-Host "  Created: $($cpApp.displayName) (ID: $($cpApp.id))" -ForegroundColor Green
} else {
    Write-Host "  Found: $($cpApp.displayName) (ID: $($cpApp.id))" -ForegroundColor Green
}

# ---- Assign to group ----
Write-Host "`n[3/3] Assigning to $GroupName..." -ForegroundColor Yellow

Invoke-MgGraphRequest -Method POST `
    -Uri "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($cpApp.id)/assign" `
    -Body (@{
        mobileAppAssignments = @(
            @{
                "@odata.type" = "#microsoft.graph.mobileAppAssignment"
                intent        = "required"
                target        = @{
                    "@odata.type"          = "#microsoft.graph.groupAssignmentTarget"
                    groupId                = $GroupId
                }
                settings      = $null
            }
        )
    } | ConvertTo-Json -Depth 10) `
    -ContentType "application/json"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " Company Portal assigned successfully!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "  App:    Company Portal" -ForegroundColor White
Write-Host "  Group:  $GroupName" -ForegroundColor White
Write-Host "  Intent: Required" -ForegroundColor White
Write-Host ""
