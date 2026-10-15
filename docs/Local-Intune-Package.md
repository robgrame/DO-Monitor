# Local collector: Intune Win32 package

Package version: **2.8.6**. Bundled collector: **2.7.4**, unchanged.

This package installs only the offline collector. It does not require Azure
infrastructure, certificates or connectivity to run. Intune is used to distribute
the app; it does not receive the collected snapshots automatically.

## Build

```powershell
.\package\Build-LocalIntunePackage.ps1

# Or specify an existing Microsoft-signed Content Prep Tool:
.\package\Build-LocalIntunePackage.ps1 -ToolPath 'C:\Tools\IntuneWinAppUtil.exe'
```

The default tool is the existing repository copy under `deploy\tools`.
The builder verifies its Microsoft Authenticode signature. It never downloads
or executes an unsigned replacement. If the tool is missing, obtain the
[Microsoft Win32 Content Prep Tool](https://github.com/microsoft/Microsoft-Win32-Content-Prep-Tool)
and supply its path.

Outputs:

```text
package\output\local\2.8.6\Install-DOMonitorLocal.intunewin
package\output\local\2.8.6\Detect-DOMonitorLocal.ps1
package\output\local\2.8.6\package-info.json
```

Build inputs are generated under `package\local\build\2.8.6`. Both directories are
git-ignored. Every build uses its own version; existing output is never deleted
or overwritten. Increment the package/script Build before rebuilding changed
sources. The existing Azure package and `package\output\Install-DOMonitor.intunewin`
are not modified.

## Intune configuration

In Intune admin center, create **Windows app (Win32)** and upload the
`Install-DOMonitorLocal.intunewin` above.

| Setting | Value |
|---|---|
| Name | DO-Monitor Local Collector |
| App version | 2.8.6 |
| Install command | `Install-DOMonitorLocal.cmd` |
| Uninstall command | `Uninstall-DOMonitorLocal.cmd` |
| Install behavior | **System** |
| Device restart behavior | **No specific action** |
| Operating system architecture | **64-bit**; target supported Windows 10/11 devices |
| Detection rules | **Use a custom detection script** |
| Detection script | Generated `package\output\local\2.8.6\Detect-DOMonitorLocal.ps1` |
| Run script as 32-bit process on 64-bit clients | **No** |
| Enforce script signature check | **No**, unless you sign the generated scripts |
| Return code 0 | Success |
| Return code 1 | Failed |

The `.cmd` launchers select 64-bit PowerShell even when started by the 32-bit
Intune Management Extension. Use the generated detection script, **not the source
template**: the generated copy contains the exact collector SHA256. If your
organization requires signing, sign source/runtime scripts before packaging and
sign the generated detection script before uploading it. Group Policy-enforced
execution policies remain authoritative.

Assign as **Required** to the intended device group. This procedure does not
publish or assign the app automatically.

## What gets installed

| Component | Location / behavior |
|---|---|
| Collector | `%ProgramFiles%\DO-Monitor-Local\Collect-DOStatusLocal.ps1` |
| Package version marker | `%ProgramFiles%\DO-Monitor-Local\VERSION` |
| Scheduled task | `\DO-Monitor Local Collector` |
| Identity | SYSTEM, highest privileges; no stored user password |
| Frequency | Every **5 minutes**, with a daily repeating trigger (`PT5M`, `P1D`) |
| Initial run | Requested immediately after successful installation |
| Overlap | `IgnoreNew`; running instances cannot overlap |
| Runtime limit | Four minutes, below the five-minute interval |
| Offline / battery | No network requirement; allowed on batteries |
| Snapshots | `%ProgramData%\DO-Monitor-Local\DO-*.json` |

Installation and data directories are protected for SYSTEM and Administrators.
The installer refuses unsafe existing folders, reparse paths and unexpected
ACLs instead of silently taking over them. If the collector was previously run
manually and its data directory is owned by a user, archive its snapshots and
have an administrator migrate it to SYSTEM/Administrators ownership and access
before installing. **Do not delete uncollected snapshots.**

Reinstallation stops the old local task before replacing its script and
registering the five-minute definition. Detection verifies the version, script
hash, folder/file access rules, SYSTEM identity, action and five-minute task
settings. A disabled or changed task is not considered installed.

Uninstall removes only the local task, collector script and package version
marker. It preserves the empty protected installation folder, **all snapshots**
and unrelated files. The separate Azure task `DO-Monitor Collector` is untouched.
Uninstall using Intune or run `Uninstall-DOMonitorLocal.cmd` from the extracted
package as an administrator.

## Operational checks

```powershell
Get-ScheduledTask -TaskName 'DO-Monitor Local Collector' -TaskPath '\'
Get-ScheduledTaskInfo -TaskName 'DO-Monitor Local Collector' -TaskPath '\'
Get-ChildItem "$env:ProgramData\DO-Monitor-Local" -Filter 'DO-*.json' |
    Sort-Object Name -Descending | Select-Object -First 5 Name, Length, LastWriteTime
```

Install success means that files and the task passed detection and the first run
was requested, not that DO telemetry has already been collected. Task last-result
codes are the collector's: `0` complete, `1` failure, `2` partial JSON saved.
Use Intune Management Extension logs for installation failures and Task Scheduler
history/last result for collection failures.

Each run saves a full snapshot, not deltas. At five-minute intervals this is
approximately **288 JSON files per day per device** when the machine is running.
There is no automatic retention or upload. Arrange later pickup and cleanup with
your collection tool and monitor disk usage. See [Local collector](Local-Collector.md)
for schema, cumulative counters, access/privacy considerations and failure codes.
