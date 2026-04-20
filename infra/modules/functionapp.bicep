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

@description('Client certificate thumbprint (stored in Key Vault for reference)')
param clientCertThumbprint string = ''

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
    clientCertEnabled: true
    clientCertMode: 'Required'
    clientCertExclusionPaths: '/api/health'
    siteConfig: {
      netFrameworkVersion: 'v10.0'
      ftpsState: 'Disabled'
      minTlsVersion: '1.2'
      http20Enabled: true
      use32BitWorkerProcess: false
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
          value: 'dotnet-isolated'
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

// Store client cert thumbprint in Key Vault (for reference by deploy scripts)
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource certThumbprintSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = if (clientCertThumbprint != '') {
  parent: keyVault
  name: 'ClientCertThumbprint'
  properties: {
    value: clientCertThumbprint
    contentType: 'Client certificate thumbprint for DO-Monitor clients'
  }
}

output id string = functionApp.id
output name string = functionApp.name
output defaultHostName string = functionApp.properties.defaultHostName
output principalId string = functionApp.identity.principalId
output functionUrl string = 'https://${functionApp.properties.defaultHostName}/api/DOIngest'
