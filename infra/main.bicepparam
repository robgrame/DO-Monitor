using 'main.bicep'

// ============================================================
// DO-Monitor — Deployment Parameters
// ============================================================
// Update these values before deployment.
// ============================================================

param baseName = 'domonitor'
param environment = 'prod'
param logAnalyticsWorkspaceId = '<YOUR-LOG-ANALYTICS-WORKSPACE-RESOURCE-ID>'

// Optional: your Azure AD user principal ID for Key Vault access during setup
param deployerPrincipalId = ''
