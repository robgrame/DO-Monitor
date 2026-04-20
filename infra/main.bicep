// ============================================================
// DO-Monitor — Main Bicep Orchestrator
// ============================================================
// Deploys the complete DO-Monitor infrastructure:
//   - Key Vault (secrets)
//   - App Configuration (settings)
//   - Storage Account (Function App state)
//   - Service Bus (message queue)
//   - Data Collection Endpoint + Rule (Log Analytics ingestion)
//   - Application Insights + App Service Plan
//   - Function App (with Managed Identity, KV refs, App Config)
//   - RBAC assignments
// ============================================================

targetScope = 'resourceGroup'

// ---- Parameters ----
@description('Base name for all resources (lowercase, no special chars)')
@minLength(3)
@maxLength(12)
param baseName string

@description('Azure region for deployment')
param location string = resourceGroup().location

@description('Log Analytics Workspace resource ID (existing)')
param logAnalyticsWorkspaceId string

@description('Environment tag')
@allowed(['dev', 'staging', 'prod'])
param environment string = 'prod'

@description('Deployer principal ID (for initial Key Vault access)')
param deployerPrincipalId string = ''

// ---- Variables ----
var resourceSuffix = '${baseName}-${environment}'
var storageName = replace(toLower('${baseName}${environment}st'), '-', '')
var tags = {
  Project: 'DO-Monitor'
  Environment: environment
  ManagedBy: 'Bicep'
}

// ============================================================
// 1. MONITORING (App Insights + App Service Plan)
// ============================================================
module monitoring 'modules/monitoring.bicep' = {
  name: 'deploy-monitoring'
  params: {
    baseName: resourceSuffix
    location: location
    workspaceResourceId: logAnalyticsWorkspaceId
    tags: tags
  }
}

// ============================================================
// 2. STORAGE ACCOUNT
// ============================================================
module storage 'modules/storage.bicep' = {
  name: 'deploy-storage'
  params: {
    name: storageName
    location: location
    tags: tags
  }
}

// ============================================================
// 3. KEY VAULT
// ============================================================
module keyVault 'modules/keyvault.bicep' = {
  name: 'deploy-keyvault'
  params: {
    name: '${resourceSuffix}-kv'
    location: location
    tags: tags
    // Secrets User role will be assigned after Function App is created
  }
}

// ============================================================
// 4. SERVICE BUS
// ============================================================
module serviceBus 'modules/servicebus.bicep' = {
  name: 'deploy-servicebus'
  params: {
    name: '${resourceSuffix}-sb'
    location: location
    queueName: 'do-telemetry'
    keyVaultName: '${resourceSuffix}-kv'
    tags: tags
  }
  dependsOn: [keyVault]
}

// ============================================================
// 5. DATA COLLECTION (DCE + DCR)
// ============================================================
module dataCollection 'modules/datacollection.bicep' = {
  name: 'deploy-datacollection'
  params: {
    dceName: '${resourceSuffix}-dce'
    dcrName: '${resourceSuffix}-dcr'
    location: location
    workspaceResourceId: logAnalyticsWorkspaceId
    keyVaultName: '${resourceSuffix}-kv'
    tags: tags
  }
  dependsOn: [keyVault]
}

// ============================================================
// 6. FUNCTION APP
// ============================================================
module functionApp 'modules/functionapp.bicep' = {
  name: 'deploy-functionapp'
  params: {
    name: '${resourceSuffix}-func'
    location: location
    appServicePlanId: monitoring.outputs.appServicePlanId
    storageConnectionString: storage.outputs.connectionString
    keyVaultUri: keyVault.outputs.uri
    keyVaultName: '${resourceSuffix}-kv'
    appConfigEndpoint: appConfig.outputs.endpoint
    sbConnectionSecretUri: serviceBus.outputs.connectionSecretUri
    sbQueueName: 'do-telemetry'
    dceEndpoint: dataCollection.outputs.dceEndpoint
    dcrSecretUri: dataCollection.outputs.dcrSecretUri
    appInsightsConnectionString: monitoring.outputs.appInsightsConnectionString
    tags: tags
  }
}

// ============================================================
// 7. APP CONFIGURATION
// ============================================================
module appConfig 'modules/appconfig.bicep' = {
  name: 'deploy-appconfig'
  params: {
    name: '${resourceSuffix}-appconfig'
    location: location
    tags: tags
  }
}

// ============================================================
// 8. RBAC ASSIGNMENTS (post Function App creation)
// ============================================================

// Function App → Key Vault Secrets User
resource kvSecretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(keyVault.outputs.id, functionApp.outputs.principalId, 'KVSecretsUser')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
    )
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App → App Configuration Data Reader
resource appConfigReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(appConfig.outputs.id, functionApp.outputs.principalId, 'AppConfigReader')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '516239f1-63e1-4d78-a4de-a74fb236a071' // App Configuration Data Reader
    )
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Function App → Monitoring Metrics Publisher on DCR
resource monitoringPublisherRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(dataCollection.outputs.dcrId, functionApp.outputs.principalId, 'MonitoringPublisher')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      '3913510d-42f4-4e42-8a64-420c390055eb' // Monitoring Metrics Publisher
    )
    principalId: functionApp.outputs.principalId
    principalType: 'ServicePrincipal'
  }
}

// Deployer → Key Vault Secrets Officer (for seeding secrets)
resource deployerKvRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (deployerPrincipalId != '') {
  name: guid(keyVault.outputs.id, deployerPrincipalId, 'KVSecretsOfficer')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId(
      'Microsoft.Authorization/roleDefinitions',
      'b86a8fe4-44ce-4948-aee5-eccb2c155cd7' // Key Vault Secrets Officer
    )
    principalId: deployerPrincipalId
    principalType: 'User'
  }
}

// ============================================================
// OUTPUTS
// ============================================================
output functionAppName string = functionApp.outputs.name
output functionAppUrl string = functionApp.outputs.functionUrl
output functionAppDefaultHostName string = functionApp.outputs.defaultHostName
output functionAppPrincipalId string = functionApp.outputs.principalId
output keyVaultName string = keyVault.outputs.name
output keyVaultUri string = keyVault.outputs.uri
output appConfigName string = appConfig.outputs.name
output appConfigEndpoint string = appConfig.outputs.endpoint
output serviceBusName string = serviceBus.outputs.name
output storageName string = storage.outputs.name
output dceEndpoint string = dataCollection.outputs.dceEndpoint
output dcrImmutableId string = dataCollection.outputs.dcrImmutableId
output appInsightsConnectionString string = monitoring.outputs.appInsightsConnectionString
