// ============================================================
// DO-Monitor — App Configuration Module
// ============================================================

@description('App Configuration name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Principal IDs to grant App Configuration Data Reader role')
param dataReaderPrincipalIds array = []

@description('Tags')
param tags object = {}

resource appConfig 'Microsoft.AppConfiguration/configurationStores@2023-03-01' = {
  name: name
  location: location
  tags: tags
  sku: {
    name: 'free'
  }
  properties: {
    publicNetworkAccess: 'Enabled'
    disableLocalAuth: false
  }
}

// Grant App Configuration Data Reader role
@batchSize(1)
resource dataReaderRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (principalId, i) in dataReaderPrincipalIds: {
    name: guid(appConfig.id, principalId, '516239f1-63e1-4d78-a4de-a74fb236a071')
    scope: appConfig
    properties: {
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        '516239f1-63e1-4d78-a4de-a74fb236a071' // App Configuration Data Reader
      )
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output id string = appConfig.id
output name string = appConfig.name
output endpoint string = appConfig.properties.endpoint
