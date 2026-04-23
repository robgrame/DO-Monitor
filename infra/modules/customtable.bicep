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
        // Timestamps
        { name: 'TimeGenerated', type: 'dateTime', description: 'Collection timestamp (UTC)' }
        // Device context
        { name: 'DeviceName', type: 'string', description: 'Device hostname' }
        { name: 'OSVersion', type: 'string', description: 'Windows OS version' }
        { name: 'OSBuild', type: 'string', description: 'Windows OS build number' }
        { name: 'SerialNumber', type: 'string', description: 'Device serial number' }
        { name: 'Domain', type: 'string', description: 'AD domain' }
        { name: 'Manufacturer', type: 'string', description: 'Device manufacturer' }
        { name: 'Model', type: 'string', description: 'Device model' }
        // Job identity
        { name: 'FileId', type: 'string', description: 'DO job file ID' }
        { name: 'FileSize_Bytes', type: 'long', description: 'File size in bytes' }
        { name: 'FileSizeInCache', type: 'long', description: 'File size in DO cache' }
        { name: 'TotalBytesDownloaded', type: 'long', description: 'Total bytes downloaded' }
        { name: 'Status', type: 'string', description: 'Job status' }
        { name: 'Priority', type: 'string', description: 'Download priority' }
        { name: 'DownloadMode', type: 'string', description: 'DO download mode' }
        { name: 'PercentPeerCaching', type: 'real', description: 'Peer caching percentage' }
        // Bytes downloaded by source
        { name: 'BytesFromPeers', type: 'long', description: 'Bytes from all peers' }
        { name: 'BytesFromHttp', type: 'long', description: 'Bytes from HTTP/CDN' }
        { name: 'BytesFromCacheServer', type: 'long', description: 'Bytes from Connected Cache' }
        { name: 'BytesFromLanPeers', type: 'long', description: 'Bytes from LAN peers' }
        { name: 'BytesFromGroupPeers', type: 'long', description: 'Bytes from group peers' }
        { name: 'BytesFromInternetPeers', type: 'long', description: 'Bytes from Internet peers' }
        { name: 'BytesFromLinkLocalPeers', type: 'long', description: 'Bytes from link-local peers' }
        // Bytes uploaded by destination
        { name: 'BytesToLanPeers', type: 'long', description: 'Bytes uploaded to LAN peers' }
        { name: 'BytesToGroupPeers', type: 'long', description: 'Bytes uploaded to group peers' }
        { name: 'BytesToInternetPeers', type: 'long', description: 'Bytes uploaded to Internet peers' }
        { name: 'BytesToLinkLocalPeers', type: 'long', description: 'Bytes uploaded to link-local peers' }
        // Connection counts
        { name: 'HttpConnectionCount', type: 'int', description: 'HTTP connections' }
        { name: 'LanConnectionCount', type: 'int', description: 'LAN peer connections' }
        { name: 'GroupConnectionCount', type: 'int', description: 'Group peer connections' }
        { name: 'InternetConnectionCount', type: 'int', description: 'Internet peer connections' }
        { name: 'LinkLocalConnectionCount', type: 'int', description: 'Link-local connections' }
        { name: 'CacheServerConnectionCount', type: 'int', description: 'Cache server connections' }
        { name: 'NumPeers', type: 'int', description: 'Number of peers' }
        // Metadata
        { name: 'SourceURL', type: 'string', description: 'Download source URL' }
        { name: 'CacheHost', type: 'string', description: 'Cache host URI' }
        { name: 'PredefinedCallerApplication', type: 'string', description: 'Calling application' }
        { name: 'DownloadDuration', type: 'real', description: 'Download duration in seconds' }
        { name: 'IsPinned', type: 'boolean', description: 'Content pinned in cache' }
      ]
    }
  }
}

output tableName string = customTable.name
