# 🚀 DO-Monitor — Delivery Optimization Monitoring for Intune

**v2.9.8**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure Functions](https://img.shields.io/badge/Azure%20Functions-.NET%2010-blue)](https://learn.microsoft.com/azure/azure-functions/)
[![Bicep](https://img.shields.io/badge/IaC-Bicep-orange)](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

> **Enterprise-grade monitoring solution** that collects Windows Delivery Optimization telemetry from Intune-managed devices and centralizes it in Azure Log Analytics for analysis, dashboards, and alerting.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Local-only Collection](#local-only-collection)
- [Project Structure](#project-structure)
- [Deployment Guide](#deployment-guide)
- [Configuration](#configuration)
- [Certificate Management](#certificate-management)
- [Monitoring & Alerting](#monitoring--alerting)
- [Cost Estimation](#cost-estimation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Windows **Delivery Optimization (DO)** enables peer-to-peer content sharing to reduce bandwidth consumption. However, there's no built-in way to get **granular, per-job telemetry** across all managed devices.

**DO-Monitor** fills this gap by:
- Collecting DO job details from every client via **Intune Proactive Remediations**
- Authenticating clients via **mutual TLS (mTLS)** with client certificates
- Ingesting data through a **serverless Azure Function** pipeline (.NET 10)
- Storing structured telemetry in **Log Analytics** custom tables
- Providing **Workbook dashboards** and **Alert Rules** for operational visibility

### What you can answer with DO-Monitor

- 🔍 **What is generating network traffic?** — See every DO job with source URL, file name, and bytes downloaded
- 📊 **How effective is peer caching?** — Track bytes from peers vs. HTTP/CDN vs. Connected Cache
- 🖥️ **Which devices consume the most bandwidth?** — Top devices by download volume
- ⚠️ **Are there devices not using DO?** — Identify misconfigured DownloadMode settings
- 💰 **How much bandwidth is DO saving?** — Quantify peer caching efficiency across the fleet

---

## Architecture

```
┌────────────────────────────────────────────────────────┐
│  CLIENTS (Intune-managed Windows devices)               │
│  Proactive Remediation runs every 6h                    │
│  Collects DO jobs via Get-DeliveryOptimizationStatus    │
│  POSTs JSON payload via HTTPS + client certificate      │
└───────────────────────┬────────────────────────────────┘
                        │ mTLS (client cert)
                        ▼
┌────────────────────────────────────────────────────────┐
│  AZURE FUNCTION APP (.NET 10 isolated, Elastic Premium) │
│  ┌──────────────────┐                                   │
│  │ Cert Validation   │  Middleware: validates client     │
│  │ Middleware         │  cert chain against App Config   │
│  └────────┬─────────┘                                   │
│           ▼                                             │
│  ┌──────────────┐     ┌───────────────────────────┐    │
│  │ DOIngest      │────►│ Azure Service Bus          │    │
│  │ (HTTP Trigger)│     │ Queue: do-telemetry        │    │
│  └──────────────┘     │ (Managed Identity auth)    │    │
│                        └───────────┬───────────────┘    │
│  ┌──────────────┐                 │                     │
│  │ DOProcessor   │◄───────────────┘                     │
│  │ (SB Trigger)  │──► Data Collection API (DCR/DCE)     │
│  └──────────────┘     (Managed Identity auth)           │
└────────────────────────────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│  LOG ANALYTICS WORKSPACE                                │
│  Custom table: DOStatus_CL                              │
│                                                         │
│  ┌──────────────┐  ┌──────────────────────────────┐    │
│  │ Workbook      │  │ Alert Rules                   │    │
│  │ Dashboard     │  │ • High HTTP traffic           │    │
│  │               │  │ • No data received (24h)      │    │
│  │               │  │ • Low peer efficiency (<20%)  │    │
│  └──────────────┘  └──────────────────────────────┘    │
└────────────────────────────────────────────────────────┘
```

### Security — Full RBAC, Zero Secrets

| Layer | Mechanism |
|---|---|
| Client → Function | **mTLS** (client certificate, CA chain validation) |
| Function → Service Bus | **Managed Identity** (Azure Service Bus Data Owner) |
| Function → Log Analytics | **Managed Identity** (Monitoring Metrics Publisher) |
| Function → Storage | **Managed Identity** (Blob/Queue/Table Data roles) |
| Function → App Configuration | **Managed Identity** (App Configuration Data Reader) |
| Secrets management | **Azure Key Vault** with RBAC authorization |
| Configuration | **Azure App Configuration** with hot-reload |

> No shared keys, no SAS tokens, no connection strings in app settings. All service-to-service authentication uses Managed Identity.

---

## Features

- ✅ **Zero-agent** — Uses built-in Intune Proactive Remediations (no additional agent)
- ✅ **.NET 10** — Azure Functions isolated worker with C# for high performance
- ✅ **mTLS authentication** — Client certificates with configurable CA chain validation
- ✅ **Full RBAC** — All Azure resources use Managed Identity, zero shared keys
- ✅ **Event-driven** — Service Bus decouples ingestion from processing
- ✅ **Infrastructure as Code** — Modular Bicep deployment (9 modules)
- ✅ **Self-contained** — Optionally creates Log Analytics workspace (no pre-existing resources needed)
- ✅ **Automated deployment** — 6-step PowerShell pipeline + `Deploy-All.ps1` orchestrator
- ✅ **Hot-reload config** — CA chains updated via App Configuration without restart
- ✅ **Observable** — Workbook dashboard, 3 alert rules, Application Insights
- ✅ **Cost-effective** — ~$120/month for 60,000 devices at 4 collections/day

---

## Prerequisites

| Requirement | Version |
|---|---|
| Azure subscription | Contributor access on target resource group |
| Azure CLI | ≥ 2.60 |
| .NET SDK | **10.0** |
| PowerShell | ≥ 7.4 |
| Microsoft Intune | License with Proactive Remediations (Intune P1) |
| Client certificate | Deployed to devices via Intune PKCS/SCEP profile |

---

## Quick Start

```powershell
# 1. Clone the repository
git clone https://github.com/robgrame/DO-Monitor.git
cd DO-Monitor

# 2. Edit deployment configuration
notepad deploy\Config.ps1

# 3. Run full deployment (infra + functions + monitoring)
.\deploy\Deploy-All.ps1

# 4. Add your trusted CA chain
.\deploy\Manage-TrustedCAChains.ps1 -Action Add `
    -ChainName "Corporate CA" `
    -RootCaThumbprint "A1B2C3..." `
    -SubCaThumbprints "D4E5F6..."

# 5. Enable certificate validation
.\deploy\Manage-TrustedCAChains.ps1 -Action Enable

# 6. Generate client script with cert thumbprint
.\deploy\05-Generate-ClientScript.ps1 -CertThumbprint "YOUR-CLIENT-CERT-THUMBPRINT"

# 7. Upload deploy\Detect-DOStatus-READY.ps1 to Intune
```

---

## Local-only Collection

To collect telemetry **without Azure**, use the dedicated standalone script:

```powershell
.\scripts\Collect-DOStatusLocal.ps1 -Verbose
```

It saves one access-controlled UTF-8 JSON snapshot per invocation in
`%ProgramData%\DO-Monitor-Local`, without certificates or network calls.
Run with 64-bit Windows PowerShell 5.1 or PowerShell 7, preferably as SYSTEM
or an administrator. Existing Azure collection remains unchanged.
See [Local collector guide](docs/Local-Collector.md) for custom paths, scheduling,
file format, exit codes, privacy, and later collection using other tools.
For a dedicated **Intune Win32 package** that installs a **five-minute SYSTEM
scheduled task**, see [Local Win32 package](docs/Local-Intune-Package.md).
Analyze one machine's snapshots with `scripts\Analyze-DOLocalSnapshots.ps1`:
see [Offline snapshot analysis](docs/Local-Snapshot-Analysis.md) for job statistics,
counter deduplication, policy changes and performance summaries.

## Project Structure

```
DO-Monitor/
├── scripts/
│   └── Detect-DOStatus.ps1              # Intune detection script (client-side, mTLS)
├── functions/
│   ├── DO-Monitor.Functions.sln         # Visual Studio solution
│   └── src/DO-Monitor.Functions/
│       ├── DO-Monitor.Functions.csproj   # .NET 10 project
│       ├── Program.cs                    # DI, App Config, middleware registration
│       ├── host.json                     # Function App runtime config
│       ├── Functions/
│       │   ├── DOIngest.cs               # HTTP Trigger → validates + queues to SB
│       │   └── DOProcessor.cs            # SB Trigger → flattens + writes to Log Analytics
│       ├── Middleware/
│       │   └── ClientCertificateValidationMiddleware.cs  # mTLS CA chain validation
│       ├── Models/
│       │   ├── DOTelemetryPayload.cs     # Client payload model
│       │   ├── DOLogEntry.cs             # Flattened Log Analytics entry
│       │   └── CertificateValidationOptions.cs  # CA chain config model
│       └── Services/
│           ├── LogAnalyticsIngestionService.cs   # DCR/DCE ingestion with batching
│           └── CertificateValidationService.cs   # CA chain validator
├── infra/
│   ├── main.bicep                        # Main orchestrator
│   ├── main.bicepparam                   # Parameters file
│   └── modules/
│       ├── loganalytics.bicep            # Log Analytics workspace (optional)
│       ├── keyvault.bicep                # Azure Key Vault (RBAC auth)
│       ├── appconfig.bicep               # Azure App Configuration
│       ├── servicebus.bicep              # Service Bus (Managed Identity, no SAS)
│       ├── storage.bicep                 # Storage Account (RBAC, no shared key)
│       ├── functionapp.bicep             # Function App (EP1, mTLS, Managed Identity)
│       ├── datacollection.bicep          # DCE + DCR for Log Analytics
│       ├── customtable.bicep             # DOStatus_CL table schema
│       └── monitoring.bicep              # App Insights + Elastic Premium plan
├── deploy/
│   ├── Config.ps1                        # Deployment configuration
│   ├── Deploy-All.ps1                    # Full orchestrator (steps 1-6)
│   ├── 01-Deploy-Infrastructure.ps1      # Bicep deployment
│   ├── 02-Seed-AppConfiguration.ps1      # App Configuration entries
│   ├── 03-Build-And-Publish-Functions.ps1  # dotnet publish + zip deploy
│   ├── 04-Deploy-Monitoring.ps1          # Workbook + Alert Rules
│   ├── 05-Generate-ClientScript.ps1      # Generate Intune-ready script
│   ├── 06-Validate-Deployment.ps1        # End-to-end validation
│   └── Manage-TrustedCAChains.ps1        # CA chain CRUD operations
├── workbooks/
│   ├── DO-Monitor-Workbook.json          # Overview dashboard
│   ├── DO-Efficiency-Workbook.json       # Peer-caching efficiency analysis
│   ├── DO-Network-Workbook.json          # Network / peer-type / MCC analysis
│   ├── DO-Packages-Workbook.json         # Per-package & traffic-category analysis
│   └── _build_workbooks.py               # Generator for the 4 workbook templates
├── alerts/
│   └── DO-Alert-Rules.json               # Scheduled Query Alert Rules
└── docs/
    ├── Architecture.md                    # Detailed architecture document
    └── Cost-Estimation-60K.md             # Cost analysis for 60K devices
```

---

## Deployment Guide

### Config.ps1 — Configuration

Edit `deploy\Config.ps1` with your Azure details:

```powershell
$Config = @{
    SubscriptionId          = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ResourceGroupName       = "rg-domonitor-prod"
    Location                = "westeurope"
    BaseName                = "domonitor"
    Environment             = "prod"
    # Leave empty to create a new workspace, or provide existing ID
    LogAnalyticsWorkspaceId = ""
}
```

### Deploy-All.ps1 — Full Deployment

```powershell
# Preview (what-if)
.\deploy\Deploy-All.ps1 -WhatIf

# Full deploy
.\deploy\Deploy-All.ps1

# Stop on first error
.\deploy\Deploy-All.ps1 -StopOnError
```

### Individual Steps

| Step | Script | Parameters |
|---|---|---|
| 1 | `01-Deploy-Infrastructure.ps1` | `-WhatIf` |
| 2 | `02-Seed-AppConfiguration.ps1` | — |
| 3 | `03-Build-And-Publish-Functions.ps1` | `-BuildOnly`, `-Configuration Release\|Debug` |
| 4 | `04-Deploy-Monitoring.ps1` | — |
| 5 | `05-Generate-ClientScript.ps1` | **`-CertThumbprint`** (required) |
| 6 | `06-Validate-Deployment.ps1` | `-SendTestPayload` |

### Deploy to Intune

1. Open **Microsoft Intune admin center**
2. Navigate to **Devices > Remediations > Create**
3. Upload `deploy\Detect-DOStatus-READY.ps1` as the **Detection script**
4. No Remediation script needed
5. **Run in 64-bit PowerShell**: Yes
6. **Run as**: SYSTEM (required for LocalMachine cert store)
7. **Schedule**: Every 6 hours
8. **Assign** to target device group

---

## Certificate Management

Client authentication uses mTLS with CA chain validation. Manage trusted CA chains via App Configuration (hot-reload, no Function restart needed):

```powershell
# List configured chains
.\deploy\Manage-TrustedCAChains.ps1 -Action List

# Add a new CA chain
.\deploy\Manage-TrustedCAChains.ps1 -Action Add `
    -ChainName "Corporate CA 2026" `
    -RootCaThumbprint "A1B2C3D4E5F6..." `
    -SubCaThumbprints "G7H8I9J0K1L2...", "M3N4O5P6Q7R8..."

# Remove a chain by index
.\deploy\Manage-TrustedCAChains.ps1 -Action Remove -ChainIndex 0

# Enable validation (disable bypass)
.\deploy\Manage-TrustedCAChains.ps1 -Action Enable

# Disable validation (development only)
.\deploy\Manage-TrustedCAChains.ps1 -Action Disable
```

Multiple CA chains are supported for certificate rotation and multi-CA environments.

---

## Configuration

### App Configuration Keys

| Key | Default | Description |
|---|---|---|
| `DO-Monitor:ServiceBusQueueName` | `do-telemetry` | Service Bus queue name |
| `DO-Monitor:LogAnalyticsStreamName` | `Custom-DOStatus_CL` | Log Analytics stream |
| `DO-Monitor:BatchSize` | `500` | Batch size for ingestion |
| `DO-Monitor:MaxRetries` | `3` | Max retries for failed ingestion |
| `DO-Monitor:ClientMinFileSizeBytes` | `0` | Min file size to report |
| `DO-Monitor:CollectionFrequencyHours` | `6` | Collection frequency |
| `DO-Monitor:Sentinel` | `1` | Change to trigger config refresh |
| `DO-Monitor:CertificateValidation:DisableValidation` | `true` | Bypass cert validation |
| `DO-Monitor:CertificateValidation:TrustedChains:N:*` | — | CA chain definitions |

### Key Vault Secrets

| Secret | Description |
|---|---|
| `DcrImmutableId` | Data Collection Rule immutable ID |
| `ClientCertThumbprint` | Client certificate thumbprint (reference) |

---

## Monitoring & Alerting

### Workbook Dashboards

Four ARM workbook templates are deployed by `04-Deploy-Monitoring.ps1`. All share a
common `TimeRange` + `Domain` parameter pair.

**1. Overview (`DO-Monitor-Workbook.json`)** — fleet-wide health.

| Panel | Description |
|---|---|
| 🎯 KPI tiles | Devices, jobs, total/peer/HTTP/cache GB, global peer-efficiency % |
| 📊 Traffic Distribution | Pie chart: Peers vs HTTP/CDN vs Connected Cache |
| 📈 Daily Trend | Line chart: bandwidth by source over time |
| 🖥️ Top 50 Devices | Table with conditional heatmap on Peer% and Total MB |
| 💰 Bandwidth Saved | Tile: WAN bytes saved (peer + cache) and % |

**2. Efficiency (`DO-Efficiency-Workbook.json`)** — is DO actually doing its job?

| Panel | Description |
|---|---|
| 📈 Peer/Cache/HTTP % over time | Daily trend of source mix in % |
| 💰 Saved bandwidth KPI | GB and % saved (peer + MCC) |
| 📊 PercentPeerCaching histogram | Distribution of job-level peer ratio (6 buckets) |
| ⬇️ Top 25 HTTP-heavy devices | Devices pulling most bytes from HTTP/CDN |
| 🥶 Cold-cache devices | Devices >100 MB but <5 % from peers (misconfig / isolation) |
| 🏢 Efficiency by Domain | Per-AD-domain table |
| 🎛️ Efficiency by DownloadMode | Compares peer % across DO modes |

**3. Network (`DO-Network-Workbook.json`)** — where is the traffic flowing?

| Panel | Description |
|---|---|
| 🥧 Download by peer type | LAN / Group / Internet split |
| 🥧 Source distribution | Peers vs HTTP/CDN vs Connected Cache |
| 📈 Daily stacked peer trend | Bars per peer type per day |
| 📈 Source trend | Line: Peer/HTTP/Cache MB per day |
| 🏆 Top 50 LAN-peer receivers | Best beneficiaries of in-LAN peer traffic |
| 🗄️ MCC daily contribution | Connected Cache bytes per day |

**4. Packages & Traffic Type (`DO-Packages-Workbook.json`)** — *what* are we downloading?

| Panel | Description |
|---|---|
| 🏷️ Traffic by category | Auto-derived category (Windows Update, M365, Store, Edge, Defender…) |
| 🥧 Category share | Pie chart of GB by category |
| 📦 Top 50 packages | Per-file aggregates (uses `FileName`, falls back to SourceURL/FileId) |
| 🌍 Top 25 hosts | Per-`SourceURL` Host aggregates |
| 📈 Daily trend per category | Stacked bars over time |
| 📐 File-size distribution | Buckets: <10 MB / 10-100 MB / 100 MB-1 GB / 1-5 GB / >5 GB |
| 🧪 Per-package source breakdown | HTTP/Cache/LAN/Group/Internet MB for top 25 packages |

> All KQL queries reference **only** the columns currently materialised in
> `DOStatus_CL` (verified live against the workspace):
> `DeviceName, OSVersion, SerialNumber, Domain, FileId, FileName, FileSize_Bytes,
> Status, Priority, DownloadMode, PercentPeerCaching, SourceURL, IsPinned,
> TotalBytesDownloaded, BytesFromPeers, BytesFromHttp, BytesFromCacheServer,
> BytesFromLanPeers, BytesFromGroupPeers, BytesFromIntPeers`.
> The Bicep `infra/modules/customtable.bicep` file declares additional columns
> (upload bytes, connection counts, `CacheHost`, `PredefinedCallerApplication`,
> `DownloadDuration`) that are **not yet active** in the live table — extend the
> DCR/ingestion model first if you want to surface those.
>
> Regenerate the JSON templates after editing the KQL with
> `python workbooks/_build_workbooks.py`.

### Alert Rules

| Alert | Severity | Trigger |
|---|---|---|
| **High HTTP Traffic** | Sev 2 | Device downloads >500 MB via HTTP with <10 MB from peers in 24h |
| **No Data Received** | Sev 1 | No telemetry received for 24 hours |
| **Low Peer Efficiency** | Sev 3 | Global peer caching drops below 20% |

---

## Data Schema — DOStatus_CL

| Field | Type | Description |
|---|---|---|
| `TimeGenerated` | datetime | Collection timestamp (UTC) |
| `DeviceName` | string | Device hostname |
| `OSVersion` | string | Windows version |
| `SerialNumber` | string | Device serial number |
| `Domain` | string | AD domain |
| `FileId` | string | DO job file ID |
| `FileName` | string | Downloaded file name |
| `FileSize_Bytes` | long | File size in bytes |
| `Status` | string | Job status (Caching, Complete, etc.) |
| `BytesFromPeers` | long | Bytes from all peers |
| `BytesFromHttp` | long | Bytes from HTTP/CDN |
| `BytesFromCacheServer` | long | Bytes from Connected Cache |
| `BytesFromLanPeers` | long | Bytes from LAN peers |
| `BytesFromGroupPeers` | long | Bytes from group peers |
| `TotalBytesDownloaded` | long | Total bytes downloaded |
| `PercentPeerCaching` | real | Peer caching percentage |
| `DownloadMode` | string | Configured DO mode |
| `SourceURL` | string | Download source URL |

### Sample KQL Queries

```kusto
// Bandwidth saved by peer caching (last 7 days)
DOStatus_CL
| where TimeGenerated > ago(7d)
| summarize PeerMB=round(sum(BytesFromPeers)/1048576.0, 2),
            HttpMB=round(sum(BytesFromHttp)/1048576.0, 2)
| extend SavedPct=round(100.0*PeerMB/(PeerMB+HttpMB), 1)

// Top bandwidth consumers
DOStatus_CL
| where TimeGenerated > ago(24h)
| summarize TotalMB=round(sum(TotalBytesDownloaded)/1048576.0, 2) by DeviceName
| top 20 by TotalMB

// What content generates the most traffic?
DOStatus_CL
| where TimeGenerated > ago(7d)
| summarize TotalMB=round(sum(TotalBytesDownloaded)/1048576.0, 2),
            Devices=dcount(DeviceName) by FileName
| top 20 by TotalMB
```

---

## Cost Estimation

Estimated monthly cost for **60,000 devices** at **4 collections/day**:

| Service | Cost/month |
|---|---|
| Log Analytics (ingestion ~34 GB) | ~$81 |
| Azure Functions (Elastic Premium EP1) | ~$150 |
| Log Analytics (retention 90d) | ~$8 |
| Alert Rules (3) | ~$5 |
| Storage Account | ~$2 |
| Service Bus (Standard) | ~$10 |
| **Total** | **~$256/month** |

> With Consumption plan (where allowed by subscription policies), Functions cost drops to ~$25/month.

See [docs/Cost-Estimation-60K.md](docs/Cost-Estimation-60K.md) for detailed breakdown and optimization strategies.

---

## Changelog

### v2.0.0

- **Breaking**: Migrated Azure Functions from PowerShell to **.NET 10** (C# isolated worker)
- **Breaking**: Authentication changed from Function Key to **client certificates (mTLS)**
- **Security**: Full RBAC — all resources use Managed Identity, no shared keys or SAS tokens
- **Security**: CA chain validation middleware with multiple chain support
- **Security**: Hot-reload CA chains via Azure App Configuration (no restart needed)
- **Infra**: Switched to Elastic Premium (EP1) plan for full RBAC storage support
- **Infra**: Log Analytics workspace is now optional (auto-created if not provided)
- **Infra**: Added 9 modular Bicep modules (loganalytics, keyvault, appconfig, servicebus, storage, functionapp, datacollection, customtable, monitoring)
- **Deploy**: Added `Manage-TrustedCAChains.ps1` for CA chain CRUD operations
- **Deploy**: `Config.ps1` no longer requires pre-existing resources

### v1.0.0

- Initial release with PowerShell Azure Functions
- Function Key authentication
- Basic Bicep deployment

---

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Commit your changes (`git commit -m 'Add my feature'`)
4. Push to the branch (`git push origin feature/my-feature`)
5. Open a Pull Request

---

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
