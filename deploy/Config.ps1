<#
.SYNOPSIS
    DO-Monitor — Shared deployment configuration.
.DESCRIPTION
    Centralizes all deployment parameters used by the deploy scripts.
    Edit this file before running any deployment script.
    
    LogAnalyticsWorkspaceId: leave empty to create a new workspace,
    or provide an existing workspace resource ID.
#>

# ============================================================
# DEPLOYMENT CONFIGURATION — EDIT THESE VALUES
# ============================================================

# Azure subscription and resource group
$Config = @{
    SubscriptionId          = "b45c5b53-d8f3-4a4c-9fe5-5537818a9886"
    ResourceGroupName       = "rg-domonitor-prod"
    Location                = "westeurope"

    # Base name for resources (lowercase, 3-12 chars)
    BaseName                = "domonitor"
    Environment             = "prod"

    # Log Analytics Workspace resource ID
    # Leave EMPTY ("") to create a new workspace automatically
    # Or provide an existing workspace resource ID
    LogAnalyticsWorkspaceId = ""

    # Derived resource names (auto-calculated from BaseName + Environment)
    FunctionAppName         = "domonitor-prod-func"
    AppConfigName           = "domonitor-prod-appconfig"
    KeyVaultName            = "domonitor-prod-kv"
    ServiceBusName          = "domonitor-prod-sbus"

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
