// ============================================================
// DO-Monitor — Function App Module
// ============================================================

@description('Function App name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('App Service Plan ID')
param appServicePlanId string

@description('Storage Account connection string')
@secure()
param storageConnectionString string

@description('Key Vault URI')
param keyVaultUri string

@description('Key Vault name')
param keyVaultName string

@description('App Configuration endpoint')
param appConfigEndpoint string

@description('Service Bus connection string Key Vault secret URI')
param sbConnectionSecretUri string

@description('Service Bus queue name')
param sbQueueName string

@description('DCE endpoint')
param dceEndpoint string

@description('DCR Immutable ID Key Vault secret URI')
param dcrSecretUri string

@description('Application Insights connection string')
param appInsightsConnectionString string

@description('Tags')
param tags object = {}

// ---- Function App ----
resource functionApp 'Microsoft.Web/sites@2023-12-01' = {
  name: name
  location: location
  kind: 'functionapp'
  tags: tags
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlanId
    httpsOnly: true
    siteConfig: {
      powerShellVersion: '7.4'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      appSettings: [
        {
          name: 'AzureWebJobsStorage'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTAZUREFILECONNECTIONSTRING'
          value: storageConnectionString
        }
        {
          name: 'WEBSITE_CONTENTSHARE'
          value: toLower(name)
        }
        {
          name: 'FUNCTIONS_EXTENSION_VERSION'
          value: '~4'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME'
          value: 'powershell'
        }
        {
          name: 'FUNCTIONS_WORKER_RUNTIME_VERSION'
          value: '7.4'
        }
        // Key Vault references for secrets
        {
          name: 'ServiceBusConnection'
          value: '@Microsoft.KeyVault(SecretUri=${sbConnectionSecretUri})'
        }
        {
          name: 'ServiceBusQueueName'
          value: sbQueueName
        }
        // Log Analytics DCE/DCR config
        {
          name: 'LogAnalyticsDCE'
          value: dceEndpoint
        }
        {
          name: 'LogAnalyticsDCR_ImmutableId'
          value: '@Microsoft.KeyVault(SecretUri=${dcrSecretUri})'
        }
        {
          name: 'LogAnalyticsStreamName'
          value: 'Custom-DOStatus_CL'
        }
        // App Configuration
        {
          name: 'AppConfigEndpoint'
          value: appConfigEndpoint
        }
        // Key Vault URI
        {
          name: 'KeyVaultUri'
          value: keyVaultUri
        }
        // Application Insights
        {
          name: 'APPLICATIONINSIGHTS_CONNECTION_STRING'
          value: appInsightsConnectionString
        }
      ]
    }
  }
}

// Store Function App default key in Key Vault (for client script)
resource functionAppHost 'Microsoft.Web/sites/host@2023-12-01' existing = {
  parent: functionApp
  name: 'default'
}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource functionKeySecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'FunctionAppHostKey'
  properties: {
    value: functionAppHost.listKeys().functionKeys.default
    contentType: 'Function App default host key for client script'
  }
}

output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output principalId string = functionApp.identity.principalId
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api/DOIngest'
