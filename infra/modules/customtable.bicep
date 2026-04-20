// ============================================================
// DO-Monitor — Custom Log Analytics Table Module
// ============================================================
// Creates the DOStatus_CL custom table in the Log Analytics workspace.
// Must be deployed BEFORE the Data Collection Rule.
// ============================================================

@description('Log Analytics workspace name')
param workspaceName string

@description('Custom table name (without _CL suffix in the resource name)')
param tableName string = 'DOStatus_CL'

@description('Retention in days')
param retentionInDays int = 90

resource workspace 'Microsoft.OperationalInsights/workspaces@2022-10-01' existing = {
  name: workspaceName
}

resource customTable 'Microsoft.OperationalInsights/workspaces/tables@2022-10-01' = {
  parent: workspace
  name: tableName
  properties: {
    plan: 'Analytics'
    retentionInDays: retentionInDays
    schema: {
      name: tableName
      columns: [
        { name: 'TimeGenerated', type: 'dateTime', description: 'Collection timestamp (UTC)' }
        { name: 'DeviceName', type: 'string', description: 'Device hostname' }
        { name: 'OSVersion', type: 'string', description: 'Windows OS version' }
        { name: 'SerialNumber', type: 'string', description: 'Device serial number' }
        { name: 'Domain', type: 'string', description: 'AD domain' }
        { name: 'FileId', type: 'string', description: 'DO job file ID' }
        { name: 'FileName', type: 'string', description: 'Downloaded file name' }
        { name: 'FileSize_Bytes', type: 'long', description: 'File size in bytes' }
        { name: 'Status', type: 'string', description: 'Job status' }
        { name: 'Priority', type: 'string', description: 'Download priority' }
        { name: 'BytesFromPeers', type: 'long', description: 'Bytes from all peers' }
        { name: 'BytesFromHttp', type: 'long', description: 'Bytes from HTTP/CDN' }
        { name: 'BytesFromCacheServer', type: 'long', description: 'Bytes from Connected Cache' }
        { name: 'BytesFromLanPeers', type: 'long', description: 'Bytes from LAN peers' }
        { name: 'BytesFromGroupPeers', type: 'long', description: 'Bytes from group peers' }
        { name: 'BytesFromIntPeers', type: 'long', description: 'Bytes from Internet peers' }
        { name: 'TotalBytesDownloaded', type: 'long', description: 'Total bytes downloaded' }
        { name: 'PercentPeerCaching', type: 'real', description: 'Peer caching percentage' }
        { name: 'DownloadMode', type: 'string', description: 'Configured DO download mode' }
        { name: 'SourceURL', type: 'string', description: 'Download source URL' }
        { name: 'IsPinned', type: 'boolean', description: 'Content pinned in cache' }
      ]
    }
  }
}

output tableName string = customTable.name
