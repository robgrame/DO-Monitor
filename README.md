# 🚀 DO-Monitor — Delivery Optimization Monitoring for Intune

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Azure Functions](https://img.shields.io/badge/Azure%20Functions-PowerShell%207.4-blue)](https://learn.microsoft.com/azure/azure-functions/)
[![Bicep](https://img.shields.io/badge/IaC-Bicep-orange)](https://learn.microsoft.com/azure/azure-resource-manager/bicep/)

> **Enterprise-grade monitoring solution** that collects Windows Delivery Optimization telemetry from Intune-managed devices and centralizes it in Azure Log Analytics for analysis, dashboards, and alerting.

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Project Structure](#project-structure)
- [Deployment Guide](#deployment-guide)
- [Configuration](#configuration)
- [Monitoring & Alerting](#monitoring--alerting)
- [Cost Estimation](#cost-estimation)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Windows **Delivery Optimization (DO)** enables peer-to-peer content sharing to reduce bandwidth consumption. However, there's no built-in way to get **granular, per-job telemetry** across all managed devices.

**DO-Monitor** fills this gap by:
- Collecting DO job details from every client via **Intune Proactive Remediations**
- Ingesting data through a **serverless Azure Function** pipeline
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
│  POSTs JSON payload via HTTPS                           │
└───────────────────────┬────────────────────────────────┘
                        │
                        ▼
┌────────────────────────────────────────────────────────┐
│  AZURE FUNCTION APP (Consumption, PowerShell 7.4)       │
│  ┌──────────────┐     ┌───────────────────────────┐    │
│  │ DOIngest      │────►│ Azure Service Bus          │    │
│  │ (HTTP Trigger)│     │ Queue: do-telemetry        │    │
│  └──────────────┘     └───────────┬───────────────┘    │
│                                   │                     │
│  ┌──────────────┐                 │                     │
│  │ DOProcessor   │◄───────────────┘                     │
│  │ (SB Trigger)  │──► Data Collection API (DCR/DCE)     │
│  └──────────────┘     Managed Identity auth             │
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

### Security

| Layer | Mechanism |
|---|---|
| Client → Function | HTTPS + Function Key |
| Function → Service Bus | Connection string (Key Vault reference) |
| Function → Log Analytics | **Managed Identity** (zero secrets) |
| Secrets management | **Azure Key Vault** with RBAC |
| Configuration | **Azure App Configuration** |

---

## Features

- ✅ **Zero-agent** — Uses built-in Intune Proactive Remediations (no additional agent)
- ✅ **Serverless** — Azure Functions Consumption plan (pay-per-execution)
- ✅ **Event-driven** — Service Bus decouples ingestion from processing
- ✅ **Secure** — Managed Identity, Key Vault references, no hardcoded secrets
- ✅ **Infrastructure as Code** — Full Bicep deployment with modular architecture
- ✅ **Automated deployment** — PowerShell scripts for end-to-end deployment
- ✅ **Observable** — Workbook dashboard, alert rules, Application Insights
- ✅ **Cost-effective** — ~$120/month for 60,000 devices at 4 collections/day

---

## Prerequisites

| Requirement | Version |
|---|---|
| Azure subscription | Contributor access on target resource group |
| Azure CLI | ≥ 2.60 |
| Bicep CLI | ≥ 0.25 (bundled with Azure CLI) |
| Azure Functions Core Tools | ≥ 4.x |
| PowerShell | ≥ 7.4 |
| Microsoft Intune | License with Proactive Remediations (Intune P1) |
| Log Analytics workspace | Existing workspace |

---

## Quick Start

```powershell
# 1. Clone the repository
git clone https://github.com/<your-org>/DO-Monitor.git
cd DO-Monitor

# 2. Edit deployment configuration
notepad deploy\Config.ps1

# 3. Run full deployment
.\deploy\Deploy-All.ps1

# 4. Upload generated script to Intune
# Output: deploy\Detect-DOStatus-READY.ps1
```

---

## Project Structure

```
DO-Monitor/
├── scripts/
│   └── Detect-DOStatus.ps1          # Intune detection script (client-side)
├── functions/
│   ├── host.json                     # Function App runtime config
│   ├── requirements.psd1             # PowerShell module dependencies
│   ├── DOIngest/                     # HTTP Trigger — receives client data
│   │   ├── function.json
│   │   └── run.ps1
│   └── DOProcessor/                  # Service Bus Trigger — writes to Log Analytics
│       ├── function.json
│       └── run.ps1
├── infra/
│   ├── main.bicep                    # Main Bicep orchestrator
│   ├── main.bicepparam               # Deployment parameters
│   └── modules/
│       ├── keyvault.bicep            # Azure Key Vault
│       ├── appconfig.bicep           # Azure App Configuration
│       ├── servicebus.bicep          # Azure Service Bus + queue
│       ├── storage.bicep             # Storage Account
│       ├── functionapp.bicep         # Function App + Managed Identity
│       ├── datacollection.bicep      # DCE + DCR for Log Analytics
│       └── monitoring.bicep          # App Insights + App Service Plan
├── deploy/
│   ├── Config.ps1                    # Shared deployment configuration
│   ├── 01-Deploy-Infrastructure.ps1  # Step 1: Bicep deployment
│   ├── 02-Seed-AppConfiguration.ps1  # Step 2: App Configuration entries
│   ├── 03-Build-And-Publish-Functions.ps1  # Step 3: Function App deployment
│   ├── 04-Deploy-Monitoring.ps1      # Step 4: Workbook + Alert Rules
│   ├── 05-Generate-ClientScript.ps1  # Step 5: Generate ready-to-deploy script
│   ├── 06-Validate-Deployment.ps1    # Step 6: End-to-end validation
│   └── Deploy-All.ps1               # Full deployment orchestrator
├── workbooks/
│   └── DO-Monitor-Workbook.json      # Azure Workbook template
├── alerts/
│   └── DO-Alert-Rules.json           # Scheduled Query Alert Rules
└── docs/
    ├── Architecture.md               # Detailed architecture document
    └── Cost-Estimation-60K.md        # Cost analysis for 60K devices
```

---

## Deployment Guide

### Step 1 — Configure

Edit `deploy\Config.ps1` with your Azure details:

```powershell
$Config = @{
    SubscriptionId          = "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    ResourceGroupName       = "rg-domonitor-prod"
    Location                = "westeurope"
    BaseName                = "domonitor"
    Environment             = "prod"
    LogAnalyticsWorkspaceId = "/subscriptions/.../resourceGroups/.../providers/Microsoft.OperationalInsights/workspaces/..."
}
```

### Step 2 — Deploy Infrastructure

```powershell
# Preview changes first
.\deploy\01-Deploy-Infrastructure.ps1 -WhatIf

# Deploy
.\deploy\01-Deploy-Infrastructure.ps1
```

This creates: Key Vault, App Configuration, Storage, Service Bus, DCE/DCR, App Insights, Function App, and all RBAC assignments.

### Step 3 — Seed Configuration

```powershell
.\deploy\02-Seed-AppConfiguration.ps1
```

### Step 4 — Deploy Functions

```powershell
.\deploy\03-Build-And-Publish-Functions.ps1
```

### Step 5 — Deploy Monitoring

```powershell
.\deploy\04-Deploy-Monitoring.ps1
```

### Step 6 — Generate Client Script

```powershell
.\deploy\05-Generate-ClientScript.ps1
```

This generates `deploy\Detect-DOStatus-READY.ps1` with the actual Function URL and key embedded.

### Step 7 — Validate

```powershell
.\deploy\06-Validate-Deployment.ps1 -SendTestPayload
```

### Step 8 — Deploy to Intune

1. Open **Microsoft Intune admin center**
2. Navigate to **Devices > Remediations > Create**
3. Upload `Detect-DOStatus-READY.ps1` as the **Detection script**
4. Do not add a Remediation script
5. Set **Run in 64-bit PowerShell**: Yes
6. Set **Run as**: System
7. **Schedule**: Every 6 hours
8. **Assign** to your target device group

---

## Configuration

### App Configuration Keys

| Key | Default | Description |
|---|---|---|
| `DO-Monitor:ServiceBusQueueName` | `do-telemetry` | Service Bus queue name |
| `DO-Monitor:LogAnalyticsStreamName` | `Custom-DOStatus_CL` | Log Analytics custom table stream |
| `DO-Monitor:BatchSize` | `500` | Batch size for Log Analytics ingestion |
| `DO-Monitor:MaxRetries` | `3` | Max retries for failed ingestion |
| `DO-Monitor:ClientMinFileSizeBytes` | `0` | Minimum file size to report (filter small jobs) |
| `DO-Monitor:CollectionFrequencyHours` | `6` | Collection frequency (informational) |

### Key Vault Secrets

| Secret | Description |
|---|---|
| `ServiceBusConnection` | Service Bus connection string |
| `DcrImmutableId` | Data Collection Rule immutable ID |
| `FunctionAppHostKey` | Function App default host key (for client script) |

---

## Monitoring & Alerting

### Workbook Dashboard

The included Azure Workbook provides:

| Panel | Description |
|---|---|
| 📊 Traffic Distribution | Pie chart: Peers vs HTTP/CDN vs Cache Server |
| 📈 Daily Trend | Line chart: bandwidth by source over time |
| 🖥️ Top 50 Devices | Table: devices ranked by total download volume |
| 📦 Top 20 Files | Table: most downloaded files with peer % |
| ⚙️ Download Modes | Bar chart: DO mode distribution across fleet |
| 💰 Bandwidth Saved | Tile: total bandwidth saved via peer caching |

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
| Azure Functions | ~$25 |
| Log Analytics (retention 90d) | ~$8 |
| Alert Rules (3) | ~$5 |
| Storage Account | ~$2 |
| Service Bus (Standard) | ~$1 |
| **Total** | **~$122/month** |

See [docs/Cost-Estimation-60K.md](docs/Cost-Estimation-60K.md) for detailed breakdown and optimization strategies.

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
