"""
Generator for DO-Monitor Azure Workbooks.

Produces 4 ARM template JSON files:
  - DO-Monitor-Workbook.json       (overview dashboard, fixed)
  - DO-Efficiency-Workbook.json    (peer-caching effectiveness & savings)
  - DO-Network-Workbook.json       (peer types, connections, throughput)
  - DO-Packages-Workbook.json      (per-package / per-caller / per-source-URL)

Run from the workbooks/ folder:
    python _build_workbooks.py
"""

from __future__ import annotations
import json
from pathlib import Path

# ---- helpers ----------------------------------------------------------------


def text(md: str, name: str) -> dict:
    return {"type": 1, "content": {"json": md}, "name": name}


def param_block(name: str = "parameters") -> dict:
    return {
        "type": 9,
        "content": {
            "version": "KqlParameterItem/1.0",
            "parameters": [
                {
                    "id": "timeRange",
                    "version": "KqlParameterItem/1.0",
                    "name": "TimeRange",
                    "type": 4,
                    "isRequired": True,
                    "value": {"durationMs": 604800000},
                    "typeSettings": {
                        "selectableValues": [
                            {"durationMs": 3600000},
                            {"durationMs": 86400000},
                            {"durationMs": 604800000},
                            {"durationMs": 2592000000},
                        ]
                    },
                },
            ],
        },
        "name": name,
    }


# No Domain filter: a previously used multi-select parameter could expand to
# an empty list (`in ()`) breaking KQL parsing on first load.
DOMAIN_FILTER = ""


def kql_item(
    query: str,
    title: str,
    viz: str = "table",
    size: int = 0,
    name: str = "q",
    chart_settings: dict | None = None,
    tile_settings: dict | None = None,
    grid_settings: dict | None = None,
) -> dict:
    content: dict = {
        "version": "KqlItem/1.0",
        "query": query,
        "size": size,
        "title": title,
        "queryType": 0,
        "resourceType": "microsoft.operationalinsights/workspaces",
        "visualization": viz,
    }
    if chart_settings:
        content["chartSettings"] = chart_settings
    if tile_settings:
        content["tileSettings"] = tile_settings
    if grid_settings:
        content["gridSettings"] = grid_settings
    return {"type": 3, "content": content, "name": name}


def group(items: list, name: str, title: str | None = None) -> dict:
    g = {
        "type": 12,
        "content": {
            "version": "NotebookGroup/1.0",
            "groupType": "editable",
            "items": items,
        },
        "name": name,
    }
    if title:
        g["content"]["title"] = title
    return g


def arm_workbook(display_name: str, items: list) -> dict:
    serialized = {"version": "Notebook/1.0", "items": items, "isLocked": False}
    return {
        "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
        "contentVersion": "1.0.0.0",
        "parameters": {
            "workbookDisplayName": {"type": "string", "defaultValue": display_name},
            "workbookSourceId": {
                "type": "string",
                "metadata": {
                    "description": "Resource ID of the Log Analytics workspace"
                },
            },
            "workbookId": {
                "type": "string",
                "defaultValue": f"[guid('{display_name}')]",
                "metadata": {"description": "Workbook resource name (GUID)"},
            },
        },
        "resources": [
            {
                "type": "microsoft.insights/workbooks",
                "apiVersion": "2022-04-01",
                "name": "[parameters('workbookId')]",
                "location": "[resourceGroup().location]",
                "kind": "shared",
                "properties": {
                    "displayName": "[parameters('workbookDisplayName')]",
                    "serializedData": json.dumps(serialized, ensure_ascii=False),
                    "version": "1.0",
                    "sourceId": "[parameters('workbookSourceId')]",
                    "category": "workbook",
                },
            }
        ],
    }


# KQL prelude shared by Packages workbook: derives PackageName from FileName/SourceURL
# and TrafficCategory from SourceURL. Compact single-line case() to avoid
# multi-line tokenisation quirks in the Workbook KQL preprocessor.
PACKAGE_LET = (
    "DOStatus_CL\n"
    "| where TimeGenerated {TimeRange}\n"
    "| extend PackageName = iff(isnotempty(FileName), FileName, "
        "iff(isnotempty(SourceURL), extract(@'([^/?]+)(?:\\?|$)', 1, SourceURL), FileId))\n"
    "| extend TrafficCategory = case("
        "SourceURL has_any ('windowsupdate.com','wustat.windows.com','update.microsoft.com','download.windowsupdate.com'), 'Windows Update', "
        "SourceURL has_any ('officecdn','office.net','office.com','officeapps.live.com'), 'Microsoft 365 Apps', "
        "SourceURL has_any ('delivery.mp.microsoft.com','dl.delivery.mp.microsoft.com'), 'Microsoft Store / Apps', "
        "SourceURL has_any ('msedge','edgedl','edge.microsoft.com'), 'Microsoft Edge', "
        "SourceURL has_any ('def.update.microsoft.com','definitionupdates'), 'Defender Definitions', "
        "isempty(SourceURL), 'Unknown', "
        "'Other')\n"
)


# =============================================================================
# Workbook 1 — Overview (fix of the existing one: correct schema columns)
# =============================================================================


def workbook_overview() -> dict:
    items = [
        text(
            "# 📊 Delivery Optimization — Overview\n---\n"
            "Vista d'insieme dell'utilizzo della Delivery Optimization sul parco client.\n"
            "Usa il filtro **TimeRange** e **Domain** per restringere l'analisi.",
            "title",
        ),
        param_block(),
        # ---------- KPI tiles ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize\n"
                "    Devices=dcount(DeviceName),\n"
                "    Jobs=count(),\n"
                "    TotalGB=round(sum(TotalBytesDownloaded)/1073741824.0, 2),\n"
                "    PeerGB=round(sum(BytesFromPeers)/1073741824.0, 2),\n"
                "    HttpGB=round(sum(BytesFromHttp)/1073741824.0, 2),\n"
                "    CacheGB=round(sum(BytesFromCacheServer)/1073741824.0, 2),\n"
                "    PeerEffPct=round(100.0*sum(BytesFromPeers)/iif(sum(TotalBytesDownloaded)==0, 1, sum(TotalBytesDownloaded)), 1)"
            ),
            title="KPI globali",
            viz="tiles",
            size=4,
            name="kpi",
            tile_settings={
                "titleContent": {"columnMatch": "Devices", "formatter": 12},
                "leftContent": {"columnMatch": "TotalGB", "formatter": 12},
                "showBorder": True,
            },
        ),
        # ---------- Pie chart: traffic by source ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peers=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), CacheServer=sum(BytesFromCacheServer)\n"
                "| mv-expand Source=pack_array('Peers','HTTP/CDN','Connected Cache') to typeof(string),\n"
                "            Bytes=pack_array(Peers,HTTP,CacheServer) to typeof(long)\n"
                "| project Source, GB=round(todouble(Bytes)/1073741824.0, 3)"
            ),
            title="📊 Distribuzione traffico per sorgente (GB)",
            viz="piechart",
            size=1,
            name="trafficDistribution",
        ),
        # ---------- Daily trend ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize PeerMB=sum(BytesFromPeers)/1048576.0,\n"
                "            HttpMB=sum(BytesFromHttp)/1048576.0,\n"
                "            CacheMB=sum(BytesFromCacheServer)/1048576.0\n"
                "          by bin(TimeGenerated, 1d)\n"
                "| order by TimeGenerated asc"
            ),
            title="📈 Trend giornaliero traffico (MB)",
            viz="linechart",
            name="dailyTrend",
        ),
        # ---------- Top devices ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize TotalBytes=sum(TotalBytesDownloaded),\n"
                "            PeerBytes=sum(BytesFromPeers),\n"
                "            HttpBytes=sum(BytesFromHttp),\n"
                "            CacheBytes=sum(BytesFromCacheServer),\n"
                "            JobCount=count() by DeviceName, Domain\n"
                "| extend PeerPct=round(100.0*PeerBytes/iif(TotalBytes==0, 1, TotalBytes), 1),\n"
                "         TotalMB=round(TotalBytes/1048576.0, 2),\n"
                "         PeerMB=round(PeerBytes/1048576.0, 2),\n"
                "         HttpMB=round(HttpBytes/1048576.0, 2),\n"
                "         CacheMB=round(CacheBytes/1048576.0, 2)\n"
                "| project DeviceName, Domain, JobCount, TotalMB, PeerMB, HttpMB, CacheMB, PeerPct\n"
                "| order by TotalMB desc\n"
                "| take 50"
            ),
            title="🖥️ Top 50 device per traffico totale",
            viz="table",
            name="topDevices",
            grid_settings={
                "formatters": [
                    {"columnMatch": "PeerPct", "formatter": 8, "formatOptions": {"palette": "greenRed"}},
                    {"columnMatch": "TotalMB", "formatter": 8, "formatOptions": {"palette": "blue"}},
                ]
            },
        ),
        # ---------- Bandwidth saved ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize PeerBytes=sum(BytesFromPeers),\n"
                "            HttpBytes=sum(BytesFromHttp),\n"
                "            CacheBytes=sum(BytesFromCacheServer),\n"
                "            TotalBytes=sum(TotalBytesDownloaded)\n"
                "| extend BandwidthSavedGB=round((PeerBytes+CacheBytes)/1073741824.0, 2),\n"
                "         BandwidthSavedPct=round(100.0*(PeerBytes+CacheBytes)/iif(TotalBytes==0,1,TotalBytes), 1)"
            ),
            title="💰 Banda WAN risparmiata (peer + cache)",
            viz="tiles",
            size=4,
            name="bandwidthSaved",
            tile_settings={
                "titleContent": {"columnMatch": "BandwidthSavedPct", "formatter": 12},
                "leftContent": {"columnMatch": "BandwidthSavedGB", "formatter": 12},
                "showBorder": True,
            },
        ),
    ]
    return arm_workbook("Delivery Optimization — Overview", items)


# =============================================================================
# Workbook 2 — Efficiency
# =============================================================================


def workbook_efficiency() -> dict:
    items = [
        text(
            "# ⚙️ Delivery Optimization — Efficienza\n---\n"
            "Quanto è efficace il peer-caching? Quanta banda WAN viene risparmiata, "
            "quali device contribuiscono come seeder, quali hanno cache fredda.",
            "title",
        ),
        param_block(),
        # ---------- Peer efficiency over time ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peer=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), Cache=sum(BytesFromCacheServer)\n"
                "         by bin(TimeGenerated, 1d)\n"
                "| extend Total=Peer+HTTP+Cache\n"
                "| extend PeerPct=round(100.0*Peer/iif(Total==0,1,Total), 1),\n"
                "         CachePct=round(100.0*Cache/iif(Total==0,1,Total), 1),\n"
                "         HttpPct=round(100.0*HTTP/iif(Total==0,1,Total), 1)\n"
                "| project TimeGenerated, PeerPct, CachePct, HttpPct\n"
                "| order by TimeGenerated asc"
            ),
            title="📈 Efficienza peer/cache nel tempo (%)",
            viz="linechart",
            name="effTrend",
            chart_settings={"yAxis": ["PeerPct", "CachePct", "HttpPct"]},
        ),
        # ---------- Saved bandwidth KPI ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peer=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), Cache=sum(BytesFromCacheServer), Total=sum(TotalBytesDownloaded)\n"
                "| extend\n"
                "    SavedWAN_GB=round((Peer+Cache)/1073741824.0, 2),\n"
                "    SavedWAN_Pct=round(100.0*(Peer+Cache)/iif(Total==0,1,Total), 1),\n"
                "    PeerOnly_Pct=round(100.0*Peer/iif(Total==0,1,Total), 1),\n"
                "    Cache_Pct=round(100.0*Cache/iif(Total==0,1,Total), 1)"
            ),
            title="💰 Banda risparmiata",
            viz="tiles",
            size=4,
            name="savedKpi",
            tile_settings={
                "titleContent": {"columnMatch": "SavedWAN_Pct", "formatter": 12},
                "leftContent": {"columnMatch": "SavedWAN_GB", "formatter": 12},
                "showBorder": True,
            },
        ),
        # ---------- Distribution histogram of PercentPeerCaching ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| where TotalBytesDownloaded > 0\n"
                "| extend Bucket=case(\n"
                "    PercentPeerCaching == 0, '0% (nessun peer)',\n"
                "    PercentPeerCaching <= 25, '1-25%',\n"
                "    PercentPeerCaching <= 50, '26-50%',\n"
                "    PercentPeerCaching <= 75, '51-75%',\n"
                "    PercentPeerCaching < 100, '76-99%',\n"
                "    '100% (full peer)')\n"
                "| summarize Jobs=count() by Bucket\n"
                "| order by Bucket asc"
            ),
            title="📊 Distribuzione PercentPeerCaching (job)",
            viz="barchart",
            name="peerHistogram",
        ),
        # ---------- Top device per traffico HTTP "puro" (cattivi peer) ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize HttpBytes=sum(BytesFromHttp),\n"
                "            PeerBytes=sum(BytesFromPeers),\n"
                "            Total=sum(TotalBytesDownloaded), Jobs=count()\n"
                "         by DeviceName, Domain\n"
                "| where Total > 0\n"
                "| extend HttpPct=round(100.0*HttpBytes/Total, 1),\n"
                "         HttpMB=round(HttpBytes/1048576.0, 1),\n"
                "         TotalMB=round(Total/1048576.0, 1)\n"
                "| project DeviceName, Domain, Jobs, TotalMB, HttpMB, HttpPct\n"
                "| order by HttpMB desc\n"
                "| take 25"
            ),
            title="⬇️ Top 25 device per traffico HTTP/CDN",
            viz="table",
            name="topHttpDevices",
            grid_settings={
                "formatters": [
                    {"columnMatch": "HttpMB", "formatter": 8, "formatOptions": {"palette": "red"}}
                ]
            },
        ),
        # ---------- Cold-cache devices (always HTTP) ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize HttpBytes=sum(BytesFromHttp),\n"
                "            PeerBytes=sum(BytesFromPeers),\n"
                "            CacheBytes=sum(BytesFromCacheServer),\n"
                "            Total=sum(TotalBytesDownloaded),\n"
                "            Jobs=count() by DeviceName, Domain\n"
                "| where Total > 104857600  // > 100 MB\n"
                "| extend PeerPct=round(100.0*PeerBytes/iif(Total==0,1,Total), 1),\n"
                "         HttpMB=round(HttpBytes/1048576.0, 1),\n"
                "         TotalMB=round(Total/1048576.0, 1)\n"
                "| where PeerPct < 5\n"
                "| project DeviceName, Domain, Jobs, TotalMB, HttpMB, PeerPct\n"
                "| order by HttpMB desc\n"
                "| take 50"
            ),
            title="🥶 Device con cache 'fredda' (>100MB, <5% peer)",
            viz="table",
            name="coldDevices",
        ),
        # ---------- Efficiency by domain ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peer=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), Cache=sum(BytesFromCacheServer),\n"
                "            Total=sum(TotalBytesDownloaded), Devices=dcount(DeviceName) by Domain\n"
                "| extend PeerPct=round(100.0*Peer/iif(Total==0,1,Total), 1),\n"
                "         CachePct=round(100.0*Cache/iif(Total==0,1,Total), 1),\n"
                "         TotalGB=round(Total/1073741824.0, 2)\n"
                "| project Domain, Devices, TotalGB, PeerPct, CachePct\n"
                "| order by TotalGB desc"
            ),
            title="🏢 Efficienza per dominio",
            viz="table",
            name="byDomain",
            grid_settings={
                "formatters": [
                    {"columnMatch": "PeerPct", "formatter": 8, "formatOptions": {"palette": "greenRed"}},
                    {"columnMatch": "CachePct", "formatter": 8, "formatOptions": {"palette": "blue"}},
                ]
            },
        ),
        # ---------- Efficiency by download mode ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peer=sum(BytesFromPeers), Total=sum(TotalBytesDownloaded),\n"
                "            Devices=dcount(DeviceName), Jobs=count() by DownloadMode\n"
                "| extend PeerPct=round(100.0*Peer/iif(Total==0,1,Total), 1),\n"
                "         TotalGB=round(Total/1073741824.0, 2)\n"
                "| project DownloadMode, Devices, Jobs, TotalGB, PeerPct\n"
                "| order by TotalGB desc"
            ),
            title="🎛️ Efficienza per DownloadMode",
            viz="table",
            name="byDlMode",
        ),
    ]
    return arm_workbook("Delivery Optimization — Efficiency", items)


# =============================================================================
# Workbook 3 — Network
# =============================================================================


def workbook_network() -> dict:
    items = [
        text(
            "# 🌐 Delivery Optimization — Rete\n---\n"
            "Analisi dell'utilizzo di rete: tipo di peer (LAN/Group/Internet), "
            "trend nel tempo e contributo della Connected Cache.",
            "title",
        ),
        param_block(),
        # ---------- Bytes by peer type (download) ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize LAN=sum(BytesFromLanPeers), Grp=sum(BytesFromGroupPeers),\n"
                "            Internet=sum(BytesFromIntPeers)\n"
                "| mv-expand PeerType=pack_array('LAN','Group','Internet') to typeof(string),\n"
                "            Bytes=pack_array(LAN,Grp,Internet) to typeof(long)\n"
                "| project PeerType, GB=round(todouble(Bytes)/1073741824.0, 3)"
            ),
            title="🥧 Download da peer per tipo di peer",
            viz="piechart",
            size=1,
            name="byPeerType",
        ),
        # ---------- Sorgenti totali (peer vs HTTP vs cache) ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peers=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), CacheServer=sum(BytesFromCacheServer)\n"
                "| mv-expand Source=pack_array('Peers','HTTP/CDN','Connected Cache') to typeof(string),\n"
                "            Bytes=pack_array(Peers,HTTP,CacheServer) to typeof(long)\n"
                "| project Source, GB=round(todouble(Bytes)/1073741824.0, 3)"
            ),
            title="🥧 Distribuzione sorgenti download",
            viz="piechart",
            size=1,
            name="bySource",
        ),
        # ---------- Bytes by peer type — daily stacked ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize LAN_MB=sum(BytesFromLanPeers)/1048576.0,\n"
                "            Group_MB=sum(BytesFromGroupPeers)/1048576.0,\n"
                "            Internet_MB=sum(BytesFromIntPeers)/1048576.0\n"
                "         by bin(TimeGenerated, 1d)\n"
                "| order by TimeGenerated asc"
            ),
            title="📈 Trend download da peer per tipo (MB / giorno)",
            viz="barchart",
            name="peerTrend",
        ),
        # ---------- Trend sorgenti ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize Peer_MB=sum(BytesFromPeers)/1048576.0,\n"
                "            HTTP_MB=sum(BytesFromHttp)/1048576.0,\n"
                "            Cache_MB=sum(BytesFromCacheServer)/1048576.0\n"
                "         by bin(TimeGenerated, 1d)\n"
                "| order by TimeGenerated asc"
            ),
            title="📈 Trend sorgenti (MB / giorno)",
            viz="linechart",
            name="sourceTrend",
        ),
        # ---------- Top device per banda LAN-peer (ottimi seeder candidati) ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| summarize LanMB=round(sum(BytesFromLanPeers)/1048576.0, 1),\n"
                "            GroupMB=round(sum(BytesFromGroupPeers)/1048576.0, 1),\n"
                "            InternetMB=round(sum(BytesFromIntPeers)/1048576.0, 1),\n"
                "            HttpMB=round(sum(BytesFromHttp)/1048576.0, 1),\n"
                "            CacheMB=round(sum(BytesFromCacheServer)/1048576.0, 1)\n"
                "         by DeviceName, Domain\n"
                "| where LanMB+GroupMB+InternetMB > 0\n"
                "| order by LanMB desc\n"
                "| take 50"
            ),
            title="🏆 Top 50 device per traffico LAN-peer (ricezione)",
            viz="table",
            name="topPeerReceivers",
            grid_settings={
                "formatters": [
                    {"columnMatch": "LanMB", "formatter": 8, "formatOptions": {"palette": "green"}},
                    {"columnMatch": "HttpMB", "formatter": 8, "formatOptions": {"palette": "red"}},
                ]
            },
        ),
        # ---------- Contributo Connected Cache ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| where BytesFromCacheServer > 0\n"
                "| summarize Devices=dcount(DeviceName), Jobs=count(),\n"
                "            CacheGB=round(sum(BytesFromCacheServer)/1073741824.0, 2)\n"
                "         by bin(TimeGenerated, 1d)\n"
                "| order by TimeGenerated asc"
            ),
            title="🗄️ Connected Cache: contributo giornaliero",
            viz="linechart",
            name="mccTrend",
        ),
    ]
    return arm_workbook("Delivery Optimization — Network", items)


# =============================================================================
# Workbook 4 — Packages & Traffic Type
# =============================================================================


def workbook_packages() -> dict:
    items = [
        text(
            "# 📦 Delivery Optimization — Pacchetti & Tipo Traffico\n---\n"
            "Analisi per **pacchetto** (FileId / nome derivato da SourceURL) e per "
            "**categoria di traffico** (Windows Update, M365 Apps, Store, Edge, "
            "Defender, …). Utile per capire *cosa* sta consumando la WAN.",
            "title",
        ),
        param_block(),
        # ---------- Traffic by category ----------
        kql_item(
            query=(
                PACKAGE_LET
                + f"{DOMAIN_FILTER}\n"
                "| summarize Peer=sum(BytesFromPeers), HTTP=sum(BytesFromHttp), Cache=sum(BytesFromCacheServer),\n"
                "            Total=sum(TotalBytesDownloaded), Jobs=count(), Devices=dcount(DeviceName)\n"
                "         by TrafficCategory\n"
                "| extend TotalGB=round(Total/1073741824.0, 2),\n"
                "         PeerPct=round(100.0*Peer/iif(Total==0,1,Total), 1),\n"
                "         HttpGB=round(HTTP/1073741824.0, 2),\n"
                "         CacheGB=round(Cache/1073741824.0, 2)\n"
                "| project TrafficCategory, Devices, Jobs, TotalGB, HttpGB, CacheGB, PeerPct\n"
                "| order by TotalGB desc"
            ),
            title="🏷️ Traffico per categoria",
            viz="table",
            name="byCategory",
            grid_settings={
                "formatters": [
                    {"columnMatch": "TotalGB", "formatter": 8, "formatOptions": {"palette": "blue"}},
                    {"columnMatch": "PeerPct", "formatter": 8, "formatOptions": {"palette": "greenRed"}},
                ]
            },
        ),
        # ---------- Pie chart category ----------
        kql_item(
            query=(
                PACKAGE_LET
                + f"{DOMAIN_FILTER}\n"
                "| summarize GB=round(sum(TotalBytesDownloaded)/1073741824.0, 3) by TrafficCategory\n"
                "| order by GB desc"
            ),
            title="🥧 Distribuzione % per categoria di traffico",
            viz="piechart",
            size=1,
            name="catPie",
        ),
        # ---------- Top packages ----------
        kql_item(
            query=(
                PACKAGE_LET
                + f"{DOMAIN_FILTER}\n"
                "| summarize Total=sum(TotalBytesDownloaded),\n"
                "            Peer=sum(BytesFromPeers),\n"
                "            HTTP=sum(BytesFromHttp),\n"
                "            Cache=sum(BytesFromCacheServer),\n"
                "            Devices=dcount(DeviceName),\n"
                "            Jobs=count(),\n"
                "            AvgSizeMB=round(avg(FileSize_Bytes)/1048576.0, 1)\n"
                "         by PackageName, TrafficCategory\n"
                "| where Total > 0\n"
                "| extend TotalGB=round(Total/1073741824.0, 3),\n"
                "         PeerPct=round(100.0*Peer/iif(Total==0,1,Total), 1)\n"
                "| project PackageName, TrafficCategory, Devices, Jobs, AvgSizeMB, TotalGB, PeerPct\n"
                "| order by TotalGB desc\n"
                "| take 50"
            ),
            title="📦 Top 50 pacchetti per traffico",
            viz="table",
            name="topPackages",
            grid_settings={
                "formatters": [
                    {"columnMatch": "TotalGB", "formatter": 8, "formatOptions": {"palette": "blue"}},
                    {"columnMatch": "PeerPct", "formatter": 8, "formatOptions": {"palette": "greenRed"}},
                ]
            },
        ),
        # ---------- Top SourceURL hosts ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| where isnotempty(SourceURL)\n"
                "| extend Host=tostring(parse_url(SourceURL).Host)\n"
                "| summarize Bytes=sum(TotalBytesDownloaded), Jobs=count(), Devices=dcount(DeviceName) by Host\n"
                "| extend GB=round(Bytes/1073741824.0, 3)\n"
                "| project Host, Devices, Jobs, GB\n"
                "| order by GB desc\n"
                "| take 25"
            ),
            title="🌍 Top 25 host (SourceURL)",
            viz="table",
            name="topHosts",
        ),
        # ---------- Trend per category ----------
        kql_item(
            query=(
                PACKAGE_LET
                + f"{DOMAIN_FILTER}\n"
                "| summarize MB=sum(TotalBytesDownloaded)/1048576.0 by bin(TimeGenerated, 1d), TrafficCategory\n"
                "| order by TimeGenerated asc"
            ),
            title="📈 Trend giornaliero per categoria di traffico (MB)",
            viz="barchart",
            name="catTrend",
        ),
        # ---------- File-size distribution ----------
        kql_item(
            query=(
                "DOStatus_CL\n"
                "| where TimeGenerated {TimeRange}\n"
                f"{DOMAIN_FILTER}\n"
                "| where FileSize_Bytes > 0\n"
                "| extend SizeBucket=case(\n"
                "    FileSize_Bytes < 10*1024*1024, '<10 MB',\n"
                "    FileSize_Bytes < 100*1024*1024, '10-100 MB',\n"
                "    FileSize_Bytes < 1024*1024*1024, '100 MB-1 GB',\n"
                "    FileSize_Bytes < 5*1024*1024*1024, '1-5 GB',\n"
                "    '>5 GB')\n"
                "| summarize Jobs=count(), TotalGB=round(sum(TotalBytesDownloaded)/1073741824.0, 2) by SizeBucket\n"
                "| order by SizeBucket asc"
            ),
            title="📐 Distribuzione job per dimensione file",
            viz="barchart",
            name="sizeBuckets",
        ),
        # ---------- Per package, per peer-type breakdown ----------
        kql_item(
            query=(
                PACKAGE_LET
                + f"{DOMAIN_FILTER}\n"
                "| summarize LAN=sum(BytesFromLanPeers), Grp=sum(BytesFromGroupPeers),\n"
                "            Internet=sum(BytesFromIntPeers), HTTP=sum(BytesFromHttp),\n"
                "            Cache=sum(BytesFromCacheServer), Total=sum(TotalBytesDownloaded)\n"
                "         by PackageName\n"
                "| where Total > 104857600  // > 100 MB\n"
                "| extend LAN_MB=round(LAN/1048576.0,1), Group_MB=round(Grp/1048576.0,1),\n"
                "         Internet_MB=round(Internet/1048576.0,1), HTTP_MB=round(HTTP/1048576.0,1),\n"
                "         Cache_MB=round(Cache/1048576.0,1)\n"
                "| project PackageName, HTTP_MB, Cache_MB, LAN_MB, Group_MB, Internet_MB\n"
                "| order by HTTP_MB desc\n"
                "| take 25"
            ),
            title="🧪 Top 25 pacchetti — breakdown per sorgente (MB)",
            viz="table",
            name="pkgBreakdown",
        ),
    ]
    return arm_workbook("Delivery Optimization — Packages & Traffic Type", items)


# =============================================================================
# Main
# =============================================================================


def main() -> None:
    out_dir = Path(__file__).parent
    targets = {
        "DO-Monitor-Workbook.json": workbook_overview(),
        "DO-Efficiency-Workbook.json": workbook_efficiency(),
        "DO-Network-Workbook.json": workbook_network(),
        "DO-Packages-Workbook.json": workbook_packages(),
    }
    for name, payload in targets.items():
        path = out_dir / name
        path.write_text(json.dumps(payload, indent=2, ensure_ascii=False), encoding="utf-8")
        print(f"  wrote {path.name}  ({path.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
