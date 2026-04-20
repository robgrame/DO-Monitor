// ============================================================
// DO-Monitor — Key Vault Module
// ============================================================

@description('Key Vault name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Tenant ID')
param tenantId string = subscription().tenantId

@description('Principal IDs to grant Key Vault Secrets User role')
param secretsUserPrincipalIds array = []

@description('Tags')
param tags object = {}

resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      family: 'A'
      name: 'standard'
    }
    tenantId: tenantId
    enableRbacAuthorization: true
    enableSoftDelete: true
    softDeleteRetentionInDays: 30
    enablePurgeProtection: true
    publicNetworkAccess: 'Enabled'
    networkAcls: {
      defaultAction: 'Allow'
      bypass: 'AzureServices'
    }
  }
}

// Grant Key Vault Secrets User role to specified principals
@batchSize(1)
resource secretsUserRole 'Microsoft.Authorization/roleAssignments@2022-04-01' = [
  for (principalId, i) in secretsUserPrincipalIds: {
    name: guid(keyVault.id, principalId, '4633458b-17de-408a-b874-0445c86b69e6')
    scope: keyVault
    properties: {
      roleDefinitionId: subscriptionResourceId(
        'Microsoft.Authorization/roleDefinitions',
        '4633458b-17de-408a-b874-0445c86b69e6' // Key Vault Secrets User
      )
      principalId: principalId
      principalType: 'ServicePrincipal'
    }
  }
]

output id string = keyVault.id
output name string = keyVault.name
output uri string = keyVault.properties.vaultUri
