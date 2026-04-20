# DO-Monitor — Stima dei Costi per 60.000 Client (4 esecuzioni/giorno)

## 1. Premesse e Assunzioni

| Parametro | Valore | Note |
|---|---|---|
| Numero client | **60.000** | Device gestiti tramite Intune |
| Frequenza raccolta | **4 volte/giorno** | Ogni 6 ore |
| Job DO medi per device/esecuzione | **10** | Stima conservativa (updates + app) |
| Dimensione media payload HTTP | **5 KB** | JSON per device (con 10 job) |
| Dimensione media entry Log Analytics | **500 bytes** | Singola riga flattened per job DO |
| Retention Log Analytics | **90 giorni** | Configurabile |
| Region Azure | **West Europe** | |
| Prezzi | **Listino pubblico Azure** | Aprile 2026, senza sconti EA/CSP |

---

## 2. Volumi Giornalieri

| Metrica | Calcolo | Valore/giorno |
|---|---|---|
| Chiamate HTTP (client → Function) | 60.000 × 4 | **240.000** |
| Messaggi Service Bus | 60.000 × 4 | **240.000** |
| Function executions (HTTP + SB) | 240.000 × 2 | **480.000** |
| Job DO totali | 240.000 × 10 | **2.400.000** |
| Dati ingestion HTTP (in) | 240.000 × 5 KB | **~1,14 GB** |
| Dati Log Analytics (ingestion) | 2.400.000 × 500 B | **~1,14 GB** |

---

## 3. Volumi Mensili (30 giorni)

| Metrica | Valore/mese |
|---|---|
| Function executions totali | **14.400.000** |
| Messaggi Service Bus | **7.200.000** |
| Dati ingestion Log Analytics | **~34,3 GB** |
| Dati in retention (90 gg, a regime) | **~103 GB** |

---

## 4. Stima Costi Mensili Dettagliata

### 4.1 Azure Functions (Consumption Plan)

| Componente | Free tier | Utilizzato | Costo unitario | Costo/mese |
|---|---|---|---|---|
| Esecuzioni | 1.000.000 | 14.400.000 | $0,20/milione | **$2,68** |
| Compute (GB-s) | 400.000 GB-s | ~1.800.000 GB-s¹ | $0,000016/GB-s | **$22,40** |
| **Subtotale Functions** | | | | **$25,08** |

> ¹ 480.000 exec/giorno × 0,5s × 256 MB = 61.440.000 MB-s/giorno = 60.000 GB-s/giorno × 30 = 1.800.000 GB-s/mese

### 4.2 Azure Service Bus (Basic)

| Componente | Costo unitario | Utilizzato | Costo/mese |
|---|---|---|---|
| Operazioni messaging² | $0,05/milione | ~21,6M ops | **$1,08** |
| **Subtotale Service Bus** | | | **$1,08** |

> ² Ogni messaggio ≈ 3 operazioni (send + receive + complete): 7,2M × 3 = 21,6M operazioni

### 4.3 Log Analytics

| Componente | Free tier | Utilizzato | Costo unitario | Costo/mese |
|---|---|---|---|---|
| Data ingestion | 5 GB/mese | ~34,3 GB | $2,76/GB | **$80,87**³ |
| Retention 0-30 giorni | Inclusa | ~34,3 GB | — | $0 |
| Retention 31-90 giorni | — | ~68,6 GB⁴ | $0,12/GB/mese | **$8,23** |
| **Subtotale Log Analytics** | | | | **$89,10** |

> ³ (34,3 - 5) × $2,76 = $80,87
> ⁴ Dati accumulati nei mesi 2-3 di retention

### 4.4 Azure Storage Account

| Componente | Costo/mese |
|---|---|
| Blob storage (Function state) | ~$1,00 |
| Transactions | ~$1,00 |
| **Subtotale Storage** | **$2,00** |

### 4.5 Alert Rules (Scheduled Query)

| Componente | Costo unitario | Quantità | Costo/mese |
|---|---|---|---|
| Scheduled Query Rule | ~$1,50/regola | 3 regole | **$4,50** |

### 4.6 Componenti inclusi (costo zero)

| Componente | Costo |
|---|---|
| Data Collection Endpoint (DCE) | Incluso |
| Data Collection Rule (DCR) | Incluso |
| Azure Workbook | Incluso |
| Application Insights (sampling) | Incluso (<5 GB) |
| Managed Identity | Incluso |

---

## 5. Riepilogo Costi Mensili

| Servizio | Costo/mese (USD) | Costo/mese (EUR)¹ | % del totale |
|---|---|---|---|
| **Log Analytics (ingestion)** | $80,87 | €74,40 | **66,3%** |
| **Azure Functions** | $25,08 | €23,07 | **20,6%** |
| **Log Analytics (retention)** | $8,23 | €7,57 | **6,7%** |
| **Alert Rules** | $4,50 | €4,14 | **3,7%** |
| **Storage Account** | $2,00 | €1,84 | **1,6%** |
| **Service Bus** | $1,08 | €0,99 | **0,9%** |
| DCE/DCR/Workbook/AppInsights | $0 | €0 | 0% |
| | | | |
| **TOTALE MENSILE** | **$121,76** | **~€112** | |
| **TOTALE ANNUALE** | **$1.461** | **~€1.344** | |

> ¹ Conversione: 1 USD ≈ 0,92 EUR

---

## 6. Distribuzione Costi

```
Log Analytics Ingestion  ████████████████████████████████████  66,3%  ($80,87)
Azure Functions          ████████████                          20,6%  ($25,08)
Log Analytics Retention  ████                                   6,7%  ($8,23)
Alert Rules              ██                                     3,7%  ($4,50)
Storage Account          █                                      1,6%  ($2,00)
Service Bus              █                                      0,9%  ($1,08)
```

---

## 7. Scenari di Confronto

### 7.1 Impatto della frequenza di raccolta

| Frequenza | Exec/giorno | LA Ingestion/mese | Costo/mese |
|---|---|---|---|
| 1×/giorno | 60.000 | ~8,6 GB | **~$20** |
| 2×/giorno | 120.000 | ~17,1 GB | **~$55** |
| **4×/giorno (attuale)** | **240.000** | **~34,3 GB** | **~$122** |
| 6×/giorno | 360.000 | ~51,4 GB | **~$180** |

### 7.2 Con Log Analytics Commitment Tier

| Commitment Tier | Prezzo/GB effettivo | Risparmio su ingestion | Costo totale/mese |
|---|---|---|---|
| Pay-as-you-go (attuale) | $2,76/GB | — | ~$122 |
| 100 GB/giorno | $1,96/GB | -29% | ~$98 |
| 200 GB/giorno | $1,78/GB | -36% | ~$92 |
| 500 GB/giorno | $1,55/GB | -44% | ~$85 |

> **Nota**: Se il workspace ingerisce già dati sufficienti per un commitment tier, l'incremento marginale di DO-Monitor è quasi nullo.

### 7.3 Confronto con alternative di mercato

| Soluzione | Costo/mese | Dettaglio dati | Setup |
|---|---|---|---|
| **DO-Monitor (questa)** | **~€112** | Alto (per job) | ~4 ore |
| WUfB Reports (built-in) | €0 | Medio (aggregato) | ~1 ora |
| Adaptiva OneSite | €2.000-5.000+ | Alto | Settimane |
| 1E Nomad | €1.500-4.000+ | Alto | Settimane |

---

## 8. Ottimizzazioni di Costo

| Ottimizzazione | Risparmio stimato | Implementazione |
|---|---|---|
| **Filtro job lato client** (solo >1 MB) | -30/50% ingestion | Modifica script PowerShell |
| **Commitment Tier LA** (se applicabile) | -29/44% ingestion | Configurazione workspace |
| **Ridurre a 2×/giorno** | -55% totale | Modifica schedule remediation |
| **Compressione Gzip** | -20% banda | Header Content-Encoding nello script |
| **Sampling client** (es. 50%) | -50% totale | Logica random nello script |
| **Aggregazione lato client** | -60/70% entries | Sommare bytes per FileName prima dell'invio |

### Esempio: Ottimizzazione con filtro + aggregazione

```
Scenario base:     60K × 4 × 10 job = 2,4M entries/giorno → ~$122/mese
Con filtro >1MB:   60K × 4 ×  5 job = 1,2M entries/giorno → ~$65/mese
Con aggregazione:  60K × 4 ×  3 agg = 0,72M entries/giorno → ~$42/mese
```

---

## 9. Costi una tantum (Setup)

| Attività | Effort stimato |
|---|---|
| Deploy infrastruttura (Bicep) | ~1 ora |
| Configurazione DCR/DCE | ~1 ora |
| Deploy e test Azure Functions | ~1 ora |
| Configurazione Intune Remediation | ~30 min |
| Test end-to-end e validazione | ~1 ora |
| Setup Workbook e Alert Rules | ~30 min |
| **Totale effort setup** | **~5 ore** |

---

## 10. Proiezione Costi 12 Mesi

| Mese | Ingestion cumulata | Retention attiva | Costo/mese |
|---|---|---|---|
| Mese 1 | 34,3 GB | 34,3 GB | ~$114 |
| Mese 2 | 34,3 GB | 68,6 GB | ~$118 |
| Mese 3+ (a regime) | 34,3 GB | 103 GB | ~$122 |

**Costo anno 1: ~$1.461 (~€1.344)**

---

## 11. Conclusioni

La soluzione DO-Monitor per **60.000 client con 4 esecuzioni/giorno** ha un costo operativo di **~€112/mese (~€1.344/anno)**.

**Key takeaways:**
- Il **66% del costo è Log Analytics ingestion** — è la leva principale per ottimizzare
- Con un **commitment tier esistente**, il costo può scendere a **~€85/mese**
- Con **filtro + aggregazione lato client**, si può arrivare a **~€40/mese**
- Il costo è **10-40× inferiore** rispetto a soluzioni commerciali equivalenti
- Il pattern serverless garantisce **zero costi fissi** e scaling automatico
