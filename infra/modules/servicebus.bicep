// ============================================================
// DO-Monitor — Service Bus Module
// ============================================================

@description('Service Bus namespace name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Queue name')
param queueName string = 'do-telemetry'

@description('Key Vault name to store connection string')
param keyVaultName string

@description('Tags')
param tags object = {}

resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'Standard'
    tier: 'Standard'
  }
  properties: {
    minimumTlsVersion: '1.2'
    publicNetworkAccess: 'Enabled'
  }
}

resource queue 'Microsoft.ServiceBus/namespaces/queues@2022-10-01-preview' = {
  parent: serviceBus
  name: queueName
  properties: {
    maxDeliveryCount: 10
    lockDuration: 'PT5M'
    defaultMessageTimeToLive: 'P7D'
    deadLetteringOnMessageExpiration: true
    maxSizeInMegabytes: 1024
  }
}

// Auth rules
resource listenSendRule 'Microsoft.ServiceBus/namespaces/AuthorizationRules@2022-10-01-preview' = {
  parent: serviceBus
  name: 'DOMonitorListenSend'
  properties: {
    rights: ['Listen', 'Send']
  }
}

// Store connection string in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource sbConnectionSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'ServiceBusConnection'
  properties: {
    value: listenSendRule.listKeys().primaryConnectionString
    contentType: 'Service Bus connection string for DO-Monitor'
  }
}

output id string = serviceBus.id
output name string = serviceBus.name
output queueName string = queue.name
output connectionSecretUri string = sbConnectionSecret.properties.secretUri
