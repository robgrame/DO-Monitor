# Local Delivery Optimization collector

Version: **2.7.4**

`scripts\Collect-DOStatusLocal.ps1` is a standalone alternative to
`scripts\Detect-DOStatus.ps1`. It collects the same job fields, device information,
performance snapshot and GPO/MDM/local policies, but writes to disk instead of
posting to the Azure Function. The existing Azure collector and installer are
unchanged. No Azure resources, certificates, network calls, external modules or
Intune license are required by this script.

## Run

Use Windows 10/11 with Delivery Optimization, **64-bit Windows PowerShell 5.1
or PowerShell 7**. Run as SYSTEM or an administrator so that the DO cmdlets and
machine policies are accessible.

```powershell
.\scripts\Collect-DOStatusLocal.ps1 -Verbose

# Optional dedicated local directory; its parent must already exist.
.\scripts\Collect-DOStatusLocal.ps1 -OutputDirectory 'D:\Telemetry\DO' -Verbose
```

The default directory is `%ProgramData%\DO-Monitor-Local`. The script creates it
with an inheritance-disabled ACL granting full control only to SYSTEM, local
Administrators and the account executing the script. An existing directory must
already have a trusted owner and a protected ACL with no other allowed accounts;
otherwise the script refuses it without changing its permissions. Use a new,
dedicated directory, not a folder containing unrelated files. Fixed local drives
only: UNC paths, mapped network drives and paths through junctions/symlinks are
rejected. Directory handles prevent path replacement during collection, and ACLs
are validated after creation as well as on later runs. The script does not change
Execution Policy; sign it if your policy
requires signed scripts.

Each invocation creates a new file:

```text
C:\ProgramData\DO-Monitor-Local\DO-20261015T0942521234567Z-<snapshot-id>.json
```

The JSON is UTF-8 without BOM. A unique snapshot ID prevents collisions, including
concurrent invocations. It is written and flushed to `.json.tmp`, then renamed to
`.json`; downstream collectors must select **only `DO-*.json`**, not temporary files.
An interrupted process can leave a `.tmp` file: it is not a published snapshot.
No previous snapshot is overwritten, and **no retention/deletion is automatic**.
Monitor disk usage and remove archived files only after verifying their collection.
A disk/ACL/write failure produces exit code 1, not a successful collection.

## Schedule without Azure

For managed installation through Intune with a **five-minute SYSTEM task**, use
the [dedicated Win32 package](Local-Intune-Package.md). The manual example below
uses a separate, configurable fifteen-minute interval.

Copy the script to an administrator-controlled local path, for example
`C:\Program Files\DO-Monitor-Local\Collect-DOStatusLocal.ps1`, then create a task
from an elevated PowerShell session:

```powershell
$ScriptPath = 'C:\Program Files\DO-Monitor-Local\Collect-DOStatusLocal.ps1'
if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Install the script first: $ScriptPath"
}
$Action = New-ScheduledTaskAction `
    -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
    -Argument "-NoProfile -NonInteractive -File `"$ScriptPath`""
$Trigger = New-ScheduledTaskTrigger -Daily -At (Get-Date).AddMinutes(1)
$Repeating = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) `
    -RepetitionInterval (New-TimeSpan -Minutes 15) `
    -RepetitionDuration (New-TimeSpan -Days 1)
$Trigger.Repetition = $Repeating.Repetition
$Principal = New-ScheduledTaskPrincipal -UserId 'SYSTEM' `
    -LogonType ServiceAccount -RunLevel Highest
$Settings = New-ScheduledTaskSettingsSet -StartWhenAvailable `
    -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
Register-ScheduledTask -TaskName 'DO-Monitor Local Collector' `
    -Action $Action -Trigger $Trigger -Principal $Principal -Settings $Settings
```

This is a **separate** task, not the existing `DO-Monitor Collector` Azure task.
The daily trigger repeats every 15 minutes for one day, then restarts its
repetition on the next daily trigger.
Do not place a SYSTEM-run script in a user-writable directory. Manage script
updates/signing through your normal endpoint tooling. To stop this collector:

```powershell
Unregister-ScheduledTask -TaskName 'DO-Monitor Local Collector' -Confirm:$false
```

Unregistering the task does not delete snapshots.

## Format and subsequent collection

Each file contains one snapshot object, not JSON Lines or a CSV:

| Field | Meaning |
|---|---|
| `SchemaVersion`, `CollectorVersion` | File schema and collector versions |
| `SnapshotId`, `CollectedAt`, `DeviceName` | Unique snapshot ID, UTC timestamp and device |
| `CollectionStatus`, `CollectionErrors` | `Complete` or `Partial`; explicit failed stages/messages |
| `OSVersion`, `OSBuild`, `SerialNumber`, `Domain`, `Manufacturer`, `Model` | Device context; null if that CIM stage failed |
| `Jobs`, `JobCount` | Array of DO jobs, including an empty array if no jobs are present |
| `TotalFromPeers`, `TotalFromHttp`, `TotalFromCache`, `TotalUploaded` | Job byte totals; uploads include link-local peers |
| `PerfSnap` | DO performance snapshot; empty on failure |
| `Policies` | Registry values prefixed with `GPO_`, `MDM_` or `Local_` |

The job shape follows the Azure collector, including duration in seconds and
ISO 8601 expiration dates. Like that collector, absent numeric job properties
on older Windows versions are normalized to zero; absent string fields to an
empty string. Missing performance properties are null, not fabricated counters.
Unconfigured policy keys are normal, not failures.

| Exit code | Meaning |
|---|---|
| `0` | Complete snapshot saved, even with zero DO jobs |
| `1` | Fatal failure: unsupported host, unsafe storage, DO job query or file write failed; no snapshot published by this invocation |
| `2` | Snapshot saved, but device/performance/policy collection was partial; inspect `CollectionErrors` |

Your later collection tool can copy the JSON files using an authorized
administrator/SYSTEM context, then parse them centrally. For a local inspection:

```powershell
$Snapshots = Get-ChildItem 'C:\ProgramData\DO-Monitor-Local' -Filter 'DO-*.json' |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json }
$Snapshots | Select-Object DeviceName, CollectedAt, JobCount, CollectionStatus, TotalFromHttp
$Snapshots | ForEach-Object { $_.Jobs } | Select-Object FileId, Status, BytesFromPeers, BytesFromHttp
```

These are **periodic snapshots**, not a complete event history. DO only returns
jobs still available at query time: short-lived jobs can be missed between runs.
Choose the collection interval accordingly. Repeated snapshots can contain the
same `FileId` and cumulative counters: do not sum them as independent downloads.
Deduplicate files by `SnapshotId`; analyse job histories by device, file ID and
collection time, accounting for counter resets.

The files contain device identifiers, policy configuration and raw source URLs,
which may include sensitive URL parameters. They are access-controlled but
**not encrypted by this script**. Protect the disk (for example with BitLocker),
restrict downstream storage access, and define retention suitable for your organization.

## Development verification

For per-machine job statistics, counter-aware traffic totals, policy history and
performance summaries, see [Offline snapshot analysis](Local-Snapshot-Analysis.md).

Run `.\scripts\tests\Test-Collect-DOStatusLocal.ps1` with 64-bit PowerShell.
It uses mocked Windows data sources in a temporary dedicated directory and does
not query the real DO service or publish data remotely.
