// ============================================================
// DO-Monitor — Monitoring Module (App Insights + App Service Plan)
// ============================================================

@description('Base name for resources')
param baseName string

@description('Azure region')
param location string = resourceGroup().location

@description('Log Analytics workspace resource ID')
param workspaceResourceId string

@description('Tags')
param tags object = {}

// ---- Application Insights ----
resource appInsights 'Microsoft.Insights/components@2020-02-02' = {
  name: '${baseName}-appi'
  location: location
  tags: tags
  kind: 'web'
  properties: {
    Application_Type: 'web'
    WorkspaceResourceId: workspaceResourceId
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
    SamplingPercentage: 50
  }
}

// ---- App Service Plan (Basic B1, Linux dedicated) ----
// The environment enforces an Azure Policy (storageaccountpublicnetworkmodify) that keeps
// the storage account's public network access Disabled and shared-key auth off. Flex
// Consumption cannot deploy its package to the locked-down storage container without adding
// VNet integration + a private endpoint. A dedicated Basic (B1) Linux plan deploys code to
// platform-managed storage (via Kudu on the dedicated worker) and reaches the customer
// storage at runtime through Managed Identity + the AzureServices bypass — exactly like the
// previous EP1 plan did — while costing a fraction of Elastic Premium.
resource appPlan 'Microsoft.Web/serverfarms@2023-12-01' = {
  name: '${baseName}-plan'
  location: location
  tags: tags
  sku: {
    name: 'B1'
    tier: 'Basic'
  }
  kind: 'linux'
  properties: {
    reserved: true
  }
}

output appInsightsId string = appInsights.id
output appInsightsConnectionString string = appInsights.properties.ConnectionString
output appServicePlanId string = appPlan.id
