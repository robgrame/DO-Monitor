// ============================================================
// DO-Monitor — Data Collection (DCE + DCR) Module
// ============================================================

@description('Data Collection Endpoint name')
param dceName string

@description('Data Collection Rule name')
param dcrName string

@description('Azure region')
param location string = resourceGroup().location

@description('Log Analytics workspace resource ID')
param workspaceResourceId string

@description('Key Vault name to store DCR immutable ID')
param keyVaultName string

@description('Tags')
param tags object = {}

// ---- Data Collection Endpoint ----
resource dataCollectionEndpoint 'Microsoft.Insights/dataCollectionEndpoints@2022-06-01' = {
  name: dceName
  location: location
  tags: tags
  properties: {
    networkAcls: {
      publicNetworkAccess: 'Enabled'
    }
  }
}

// ---- Data Collection Rule ----
resource dataCollectionRule 'Microsoft.Insights/dataCollectionRules@2022-06-01' = {
  name: dcrName
  location: location
  tags: tags
  properties: {
    dataCollectionEndpointId: dataCollectionEndpoint.id
    streamDeclarations: {
      'Custom-DOStatus_CL': {
        columns: [
          // Timestamps
          { name: 'TimeGenerated', type: 'datetime' }
          // Device context
          { name: 'DeviceName', type: 'string' }
          { name: 'OSVersion', type: 'string' }
          { name: 'OSBuild', type: 'string' }
          { name: 'SerialNumber', type: 'string' }
          { name: 'Domain', type: 'string' }
          { name: 'Manufacturer', type: 'string' }
          { name: 'Model', type: 'string' }
          // Job identity
          { name: 'FileId', type: 'string' }
          { name: 'FileSize_Bytes', type: 'long' }
          { name: 'FileSizeInCache', type: 'long' }
          { name: 'TotalBytesDownloaded', type: 'long' }
          { name: 'Status', type: 'string' }
          { name: 'Priority', type: 'string' }
          { name: 'DownloadMode', type: 'string' }
          { name: 'PercentPeerCaching', type: 'real' }
          // Bytes downloaded by source
          { name: 'BytesFromPeers', type: 'long' }
          { name: 'BytesFromHttp', type: 'long' }
          { name: 'BytesFromCacheServer', type: 'long' }
          { name: 'BytesFromLanPeers', type: 'long' }
          { name: 'BytesFromGroupPeers', type: 'long' }
          { name: 'BytesFromInternetPeers', type: 'long' }
          { name: 'BytesFromLinkLocalPeers', type: 'long' }
          // Bytes uploaded by destination
          { name: 'BytesToLanPeers', type: 'long' }
          { name: 'BytesToGroupPeers', type: 'long' }
          { name: 'BytesToInternetPeers', type: 'long' }
          { name: 'BytesToLinkLocalPeers', type: 'long' }
          // Connection counts
          { name: 'HttpConnectionCount', type: 'int' }
          { name: 'LanConnectionCount', type: 'int' }
          { name: 'GroupConnectionCount', type: 'int' }
          { name: 'InternetConnectionCount', type: 'int' }
          { name: 'LinkLocalConnectionCount', type: 'int' }
          { name: 'CacheServerConnectionCount', type: 'int' }
          { name: 'NumPeers', type: 'int' }
          // Metadata
          { name: 'SourceURL', type: 'string' }
          { name: 'CacheHost', type: 'string' }
          { name: 'PredefinedCallerApplication', type: 'string' }
          { name: 'DownloadDuration', type: 'real' }
          { name: 'IsPinned', type: 'boolean' }
        ]
      }
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: workspaceResourceId
          name: 'logAnalyticsDest'
        }
      ]
    }
    dataFlows: [
      {
        streams: [ 'Custom-DOStatus_CL' ]
        destinations: [ 'logAnalyticsDest' ]
        transformKql: 'source'
        outputStream: 'Custom-DOStatus_CL'
      }
    ]
  }
}

// Store DCR immutable ID in Key Vault
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' existing = {
  name: keyVaultName
}

resource dcrSecret 'Microsoft.KeyVault/vaults/secrets@2023-07-01' = {
  parent: keyVault
  name: 'DcrImmutableId'
  properties: {
    value: dataCollectionRule.properties.immutableId
    contentType: 'DCR Immutable ID for DO-Monitor'
  }
}

output dceId string = dataCollectionEndpoint.id
output dceName string = dataCollectionEndpoint.name
output dceEndpoint string = dataCollectionEndpoint.properties.logsIngestion.endpoint
output dcrId string = dataCollectionRule.id
output dcrName string = dataCollectionRule.name
output dcrImmutableId string = dataCollectionRule.properties.immutableId
output dcrSecretUri string = dcrSecret.properties.secretUri
