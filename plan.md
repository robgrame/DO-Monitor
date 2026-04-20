# DO-Monitor — Delivery Optimization Monitoring Solution

## Architettura

```
Client (Intune Remediation)
    │ POST JSON (DO job details)
    ▼
Azure Function (HTTP Trigger) ─── DOIngest
    │ Send message to queue
    ▼
Azure Service Bus Queue ─── do-telemetry
    │ SB Trigger
    ▼
Azure Function (SB Trigger) ─── DOProcessor
    │ Data Collection API (Managed Identity)
    ▼
Log Analytics Workspace ─── DOStatus_CL (custom table)
    │
    ├──► Azure Workbook (dashboard)
    └──► Alert Rules (anomalie)
```

## Componenti

| Componente | Path | Descrizione |
|---|---|---|
| Detection Script | `scripts/Detect-DOStatus.ps1` | Intune Proactive Remediation - raccoglie DO jobs e li invia alla Function |
| HTTP Trigger | `functions/DOIngest/` | Riceve i dati dai client, li mette in coda Service Bus |
| SB Trigger | `functions/DOProcessor/` | Processa i messaggi e scrive su Log Analytics via DCR/DCE |
| Workbook | `workbooks/DO-Monitor-Workbook.json` | Dashboard con pie chart, trend, top devices, bandwidth saved |
| Alert Rules | `alerts/DO-Alert-Rules.json` | 3 alert: alto traffico HTTP, nessun dato, bassa efficienza peer |
| Infrastruttura | `infra/main.bicep` | Bicep per deploy completo (Function App, SB, DCR, DCE, Storage) |

## Dati raccolti per ogni DO job

- DeviceName, OSVersion, SerialNumber, Domain
- FileId, FileName, FileSize, Status, Priority, DownloadMode
- BytesFromPeers, BytesFromHttp, BytesFromCacheServer
- BytesFromLanPeers, BytesFromGroupPeers, BytesFromIntPeers
- TotalBytesDownloaded, PercentPeerCaching, SourceURL, IsPinned

## Alert Rules

1. **DO-HighHTTPTraffic** (Sev 2) — Device con >500 MB HTTP e <10 MB peer in 24h
2. **DO-NoDataReceived** (Sev 1) — Nessun dato ricevuto per 24h
3. **DO-LowPeerEfficiency** (Sev 3) — Peer caching globale sotto il 20%

## Deploy

```bash
# 1. Deploy infrastruttura
az deployment group create -g <RG> -f infra/main.bicep \
  --parameters logAnalyticsWorkspaceId=<WORKSPACE-ID>

# 2. Deploy Functions
cd functions && func azure functionapp publish <FUNCTION-APP-NAME>

# 3. Aggiorna lo script con l'URL della Function
# Modifica $FunctionUrl in scripts/Detect-DOStatus.ps1

# 4. Deploy Workbook
az deployment group create -g <RG> -f workbooks/DO-Monitor-Workbook.json \
  --parameters workbookSourceId=<WORKSPACE-ID>

# 5. Deploy Alert Rules
az deployment group create -g <RG> -f alerts/DO-Alert-Rules.json \
  --parameters workspaceResourceId=<WORKSPACE-ID> actionGroupResourceId=<AG-ID>
```
