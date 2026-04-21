// ============================================================
// DO-Monitor — Service Bus Module
// ============================================================

@description('Service Bus namespace name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Queue name')
param queueName string = 'do-telemetry'

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
    disableLocalAuth: true
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

output id string = serviceBus.id
output name string = serviceBus.name
output queueName string = queue.name
output namespaceFqdn string = '${serviceBus.name}.servicebus.windows.net'
