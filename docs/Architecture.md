# DO-Monitor — Documento di Architettura

## 1. Executive Summary

La soluzione **DO-Monitor** raccoglie telemetria dettagliata sull'utilizzo della Delivery Optimization (DO) da tutti i client gestiti tramite Microsoft Intune, centralizzandola su Azure Log Analytics per analisi, dashboard e alerting.

L'architettura è progettata per **60.000 client** con raccolta **4 volte al giorno** e un pattern event-driven che disaccoppia l'ingestion dal processing tramite Azure Service Bus.

---

## 2. Diagramma di Architettura

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        CLIENT LAYER (60.000 device)                     │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Intune Proactive Remediation (Detection Script)                 │   │
│  │  Schedule: ogni 6 ore (4 esecuzioni/giorno)                      │   │
│  │  ┌─────────────────────────────┐                                 │   │
│  │  │  Get-DeliveryOptimization   │                                 │   │
│  │  │  Status                     │──► JSON Payload ──► POST HTTPS  │   │
│  │  └─────────────────────────────┘                                 │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ HTTPS POST (JSON ~5 KB)
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                        INGESTION LAYER (Azure)                          │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐   │
│  │  Azure Function App (Consumption Plan, PowerShell 7.4)           │   │
│  │  System-Assigned Managed Identity                                │   │
│  │                                                                  │   │
│  │  ┌─────────────────────┐    ┌──────────────────────────────┐    │   │
│  │  │  DOIngest            │    │  DOProcessor                  │    │   │
│  │  │  (HTTP Trigger)      │    │  (Service Bus Trigger)        │    │   │
│  │  │                      │    │                                │    │   │
│  │  │  • Valida payload    │    │  • Deserializza messaggio     │    │   │
│  │  │  • Arricchisce con   │    │  • Flatten jobs in entries    │    │   │
│  │  │    timestamp         │    │  • Batch invio (500 entries)  │    │   │
│  │  │  • Invia a SB queue  │    │  • Invia a Log Analytics      │    │   │
│  │  │                      │    │    via Data Collection API    │    │   │
│  │  └──────────┬───────────┘    └──────────────┬─────────────────┘   │   │
│  │             │                                │                    │   │
│  └─────────────┼────────────────────────────────┼────────────────────┘   │
│                │                                │                        │
│                ▼                                │                        │
│  ┌──────────────────────┐                       │                        │
│  │  Azure Service Bus   │                       │                        │
│  │  Namespace (Basic)   │───────── trigger ─────┘                        │
│  │  Queue: do-telemetry │                                                │
│  │  TTL: 7 giorni       │                                                │
│  │  Max Delivery: 10    │                                                │
│  │  Lock: 5 minuti      │                                                │
│  └──────────────────────┘                                                │
└─────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼ Data Collection API (Managed Identity)
┌─────────────────────────────────────────────────────────────────────────┐
│                      ANALYTICS LAYER (Azure Monitor)                    │
│                                                                         │
│  ┌──────────────────────┐  ┌─────────────────┐  ┌──────────────────┐   │
│  │  Data Collection     │  │  Data Collection │  │  Log Analytics   │   │
│  │  Endpoint (DCE)      │─►│  Rule (DCR)      │─►│  Workspace       │   │
│  │                      │  │                  │  │                   │   │
│  │  Endpoint HTTPS per  │  │  Schema mapping  │  │  Tabella custom:  │   │
│  │  ingestion dati      │  │  DOStatus_CL     │  │  DOStatus_CL     │   │
│  └──────────────────────┘  └─────────────────┘  └────────┬──────────┘   │
│                                                           │              │
│  ┌────────────────────────────────────────────────────────┼──────────┐   │
│  │                     PRESENTATION LAYER                 │          │   │
│  │  ┌─────────────────────┐    ┌──────────────────────┐  │          │   │
│  │  │  Azure Workbook     │    │  Scheduled Query     │  │          │   │
│  │  │  (Dashboard)        │◄───│  Alert Rules         │◄─┘          │   │
│  │  │                     │    │                      │              │   │
│  │  │  • Distribuzione    │    │  • High HTTP Traffic │              │   │
│  │  │    traffico (pie)   │    │  • No Data Received  │              │   │
│  │  │  • Trend giornaliero│    │  • Low Peer Caching  │              │   │
│  │  │  • Top 50 devices   │    │                      │              │   │
│  │  │  • Top 20 files     │    └──────────┬───────────┘              │   │
│  │  │  • Download modes   │               │                          │   │
│  │  │  • Banda risparmiata│               ▼                          │   │
│  │  └─────────────────────┘    ┌──────────────────────┐              │   │
│  │                             │  Action Group        │              │   │
│  │                             │  (Email/Teams/Webhook)│             │   │
│  │                             └──────────────────────┘              │   │
│  └──────────────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Flusso Dati

### 3.1 Raccolta (Client → Function)
1. La **Proactive Remediation** Intune esegue `Detect-DOStatus.ps1` ogni **6 ore** (4 volte/giorno)
2. Lo script invoca `Get-DeliveryOptimizationStatus` per ottenere tutti i job DO attivi/in cache
3. I dati vengono arricchiti con informazioni device (hostname, OS, serial number)
4. Il payload JSON (~5 KB) viene inviato via HTTPS POST alla Azure Function `DOIngest`

### 3.2 Ingestion (Function HTTP → Service Bus)
5. `DOIngest` valida il payload e aggiunge il timestamp di ingestion
6. Il messaggio viene scritto sulla coda Service Bus `do-telemetry`
7. Risponde `202 Accepted` al client

### 3.3 Processing (Service Bus → Log Analytics)
8. `DOProcessor` viene triggerato dal messaggio in coda
9. Flatten dei job: ogni job DO diventa una riga nella tabella custom `DOStatus_CL`
10. I dati vengono inviati in batch (max 500 entries) a Log Analytics tramite la **Data Collection API**
11. L'autenticazione avviene tramite **Managed Identity** con ruolo `Monitoring Metrics Publisher`

### 3.4 Analisi e Alerting
12. I dati in `DOStatus_CL` sono queryabili con KQL
13. L'Azure Workbook fornisce dashboard interattive
14. Le Alert Rules monitorano anomalie e inviano notifiche tramite Action Group

---

## 4. Componenti e Tecnologie

| Componente | Servizio Azure | SKU/Piano | Finalità |
|---|---|---|---|
| Function App | Azure Functions | Consumption (Y1) | Hosting serverless per DOIngest e DOProcessor |
| Coda messaggi | Azure Service Bus | Basic | Disaccoppiamento ingestion/processing, retry automatico |
| Storage | Azure Storage Account | Standard LRS | Storage per la Function App (triggers, logs) |
| Ingestion endpoint | Data Collection Endpoint | — | Endpoint HTTPS per la Data Collection API |
| Schema e routing | Data Collection Rule | — | Definizione schema DOStatus_CL e routing verso workspace |
| Dati | Log Analytics Workspace | Pay-as-you-go | Storage e query dei dati DO |
| Dashboard | Azure Workbook | Incluso | Visualizzazione interattiva |
| Alerting | Scheduled Query Rules | — | Monitoraggio anomalie |
| Identità | System-Assigned MI | — | Autenticazione Function → Log Analytics (zero secrets) |

---

## 5. Schema Dati — DOStatus_CL

| Campo | Tipo | Descrizione |
|---|---|---|
| TimeGenerated | datetime | Timestamp raccolta dati sul client (UTC) |
| DeviceName | string | Nome del dispositivo |
| OSVersion | string | Versione del sistema operativo |
| SerialNumber | string | Numero di serie del dispositivo |
| Domain | string | Dominio di appartenenza |
| FileId | string | ID univoco del file DO |
| FileName | string | Nome del file scaricato |
| FileSize_Bytes | long | Dimensione del file in bytes |
| Status | string | Stato del job (Caching, Complete, etc.) |
| Priority | string | Priorità del download |
| BytesFromPeers | long | Bytes ricevuti da peer (totale) |
| BytesFromHttp | long | Bytes ricevuti da HTTP/CDN |
| BytesFromCacheServer | long | Bytes ricevuti da Connected Cache |
| BytesFromLanPeers | long | Bytes ricevuti da peer LAN |
| BytesFromGroupPeers | long | Bytes ricevuti da peer nel gruppo |
| BytesFromIntPeers | long | Bytes ricevuti da peer Internet |
| TotalBytesDownloaded | long | Totale bytes scaricati |
| PercentPeerCaching | real | Percentuale di peer caching (0-100) |
| DownloadMode | string | Modalità DO configurata |
| SourceURL | string | URL sorgente del download |
| IsPinned | boolean | Se il contenuto è pinnato in cache |

---

## 6. Sicurezza

### 6.1 Autenticazione
- **Client → Function**: Function Key (authLevel: function) su HTTPS
- **Function → Service Bus**: Connection String (app setting, rotazione gestita)
- **Function → Log Analytics**: System-Assigned Managed Identity con ruolo `Monitoring Metrics Publisher` sul DCR — **zero secrets**

### 6.2 Rete
- Tutte le comunicazioni avvengono su **HTTPS/TLS 1.2**
- La Function App ha `httpsOnly: true`
- Il DCE accetta traffico da reti pubbliche (configurabile con Private Endpoint se necessario)
- Nessuna porta in ingresso necessaria sui client

### 6.3 Dati e Privacy
- **Non vengono raccolti dati personali (PII)** — solo hostname, serial number e metriche DO
- I dati contengono URL sorgente dei download (utile per analisi, nessun dato utente)
- Retention configurabile su Log Analytics (consigliato: 90 giorni)

---

## 7. Scalabilità e Resilienza

| Aspetto | Design |
|---|---|
| **Burst di 240K chiamate/giorno** | Service Bus assorbe i picchi, DOProcessor processa in modo asincrono |
| **Retry automatico** | SB queue con maxDeliveryCount=10, dead-letter queue per messaggi non processabili |
| **Auto-scaling** | Function App scala automaticamente (Consumption plan, fino a 200 istanze) |
| **Idempotenza** | Log Analytics gestisce duplicati; ogni entry ha TimeGenerated + DeviceName + FileId |
| **TTL messaggi** | 7 giorni — se il processing è temporaneamente fermo, i messaggi non vengono persi |
| **Lock duration** | 5 minuti per messaggio — sufficiente per processing + batch invio a Log Analytics |
| **Backpressure** | Se Log Analytics è lento, i messaggi restano in coda SB senza perdita di dati |

---

## 8. Monitoring della Soluzione

| Cosa | Come |
|---|---|
| Salute Function App | Application Insights (latenza, errori, throughput) |
| Profondità coda SB | Azure Service Bus Metrics (active messages, dead-lettered) |
| Flusso dati end-to-end | Alert Rule "No Data Received" — nessun dato per 24h |
| Errori ingestion | Application Insights exceptions + SB dead-letter queue |

---

## 9. Prerequisiti per il Deploy

1. Sottoscrizione Azure con permessi **Contributor** sul Resource Group
2. **Log Analytics Workspace** esistente
3. Licenza **Intune P1** (per Proactive Remediations)
4. **Azure CLI** + **Bicep CLI** installati
5. **Azure Functions Core Tools** per il deploy delle Functions

---

## 10. Limitazioni Note

| Limitazione | Impatto | Mitigazione |
|---|---|---|
| `Get-DeliveryOptimizationStatus` mostra solo job attivi/in cache | Job completati e rimossi dalla cache non visibili | Raccolta 4×/giorno cattura più snapshot |
| Payload max Service Bus Basic: 256 KB | Limite di ~100+ job per messaggio | Sufficiente per la quasi totalità dei device |
| Function Key nello script client | Deve essere protetta | Considerare Azure APIM per sicurezza avanzata |
| Latenza ingestion Log Analytics | Dati visibili dopo 2-5 minuti | Accettabile per questo caso d'uso |
