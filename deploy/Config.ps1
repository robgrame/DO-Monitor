<#
.SYNOPSIS
    DO-Monitor — Shared deployment configuration.
.DESCRIPTION
    Centralizes all deployment parameters used by the deploy scripts.
    Edit this file before running any deployment script.
#>

# ============================================================
# DEPLOYMENT CONFIGURATION — EDIT THESE VALUES
# ============================================================

# Azure subscription and resource group
$Config = @{
    SubscriptionId          = "<YOUR-SUBSCRIPTION-ID>"
    ResourceGroupName       = "rg-domonitor-prod"
    Location                = "westeurope"

    # Base name for resources (lowercase, 3-12 chars)
    BaseName                = "domonitor"
    Environment             = "prod"

    # Existing Log Analytics Workspace resource ID
    LogAnalyticsWorkspaceId = "<YOUR-LOG-ANALYTICS-WORKSPACE-RESOURCE-ID>"

    # Function App name (derived)
    FunctionAppName         = "domonitor-prod-func"

    # App Configuration name (derived)
    AppConfigName           = "domonitor-prod-appconfig"

    # Key Vault name (derived)
    KeyVaultName            = "domonitor-prod-kv"

    # Service Bus name (derived)
    ServiceBusName          = "domonitor-prod-sb"

    # Paths
    ProjectRoot             = $PSScriptRoot | Split-Path
    InfraPath               = Join-Path ($PSScriptRoot | Split-Path) "infra"
    FunctionsPath           = Join-Path ($PSScriptRoot | Split-Path) "functions"
    WorkbooksPath           = Join-Path ($PSScriptRoot | Split-Path) "workbooks"
    AlertsPath              = Join-Path ($PSScriptRoot | Split-Path) "alerts"
    ScriptsPath             = Join-Path ($PSScriptRoot | Split-Path) "scripts"
}

# Export for use in other scripts
return $Config
