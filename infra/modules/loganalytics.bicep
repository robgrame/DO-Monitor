// ============================================================
// DO-Monitor — Log Analytics Workspace Module
// ============================================================

@description('Workspace name')
param name string

@description('Azure region')
param location string = resourceGroup().location

@description('Retention in days')
param retentionInDays int = 90

@description('Tags')
param tags object = {}

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' = {
  name: name
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: retentionInDays
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

output id string = workspace.id
output name string = workspace.name
output resourceGroup string = resourceGroup().name
