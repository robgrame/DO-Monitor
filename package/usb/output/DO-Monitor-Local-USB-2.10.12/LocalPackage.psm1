#requires -Version 5.1
# Local-only package helpers. Version: 2.8.6
$ErrorActionPreference = 'Stop'

function Assert-DOLocalPackageHost {
    if ($env:OS -ne 'Windows_NT' -or -not [Environment]::Is64BitProcess) {
        throw 'Use 64-bit PowerShell on Windows. Configure Intune to run the app as System.'
    }
    $Principal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Installation and uninstallation require SYSTEM or an elevated administrator.'
    }
}

function Open-DOLocalPackageDirectory {
    param([Parameter(Mandatory)][string]$Path, [switch]$Create)

    if (-not ('DOMonitor.LocalPackage.NativeMethods' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace DOMonitor.LocalPackage {
    public static class NativeMethods {
        [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern SafeFileHandle CreateFile(
            string path, uint access, uint share, IntPtr security,
            uint disposition, uint flags, IntPtr template);
    }
}
'@ -ErrorAction Stop
    }
    $Handles = [Collections.Generic.List[IDisposable]]::new()
    try {
        $FullPath = [IO.Path]::GetFullPath($Path).TrimEnd('\')
        if ($Path -notmatch '^[A-Za-z]:\\' -or $Path.IndexOf(':', 2) -ge 0 -or
            $FullPath -eq [IO.Path]::GetPathRoot($FullPath).TrimEnd('\') -or
            ([IO.DriveInfo]::new([IO.Path]::GetPathRoot($FullPath))).DriveType -ne 'Fixed') {
            throw "Not a dedicated fixed-drive directory: $Path"
        }
        $Ancestors = [Collections.Generic.List[string]]::new()
        $Ancestor = $FullPath
        while ($Ancestor) {
            $Ancestors.Add($Ancestor)
            $Ancestor = Split-Path -Path $Ancestor -Parent
        }
        for ($Index = $Ancestors.Count - 1; $Index -ge 0; $Index--) {
            $Directory = $Ancestors[$Index]
            if ($Index -eq 0 -and -not (Test-Path -LiteralPath $Directory)) {
                if (-not $Create) { throw "Directory missing: $Directory" }
                $Acl = [Security.AccessControl.DirectorySecurity]::new()
                $Acl.SetAccessRuleProtection($true, $false)
                $Acl.SetOwner([Security.Principal.SecurityIdentifier]::new('S-1-5-32-544'))
                foreach ($Sid in @('S-1-5-18', 'S-1-5-32-544')) {
                    $Acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                        [Security.Principal.SecurityIdentifier]::new($Sid),
                        [Security.AccessControl.FileSystemRights]::FullControl,
                        [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit',
                        [Security.AccessControl.PropagationFlags]::None,
                        [Security.AccessControl.AccessControlType]::Allow))
                }
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    $null = [IO.FileSystemAclExtensions]::Create([IO.DirectoryInfo]::new($Directory), $Acl)
                } else {
                    $null = [IO.Directory]::CreateDirectory($Directory, $Acl)
                }
            }
            $Handle = [DOMonitor.LocalPackage.NativeMethods]::CreateFile(
                $Directory, 2147483648, 3, [IntPtr]::Zero, 3, 0x02200000, [IntPtr]::Zero)
            if ($Handle.IsInvalid) {
                $Code = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
                $Handle.Dispose()
                throw [ComponentModel.Win32Exception]::new($Code, "Cannot lock directory: $Directory")
            }
            $Handles.Add($Handle)
            $Item = Get-Item -LiteralPath $Directory -Force
            if (-not $Item.PSIsContainer -or ($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw "Refusing a file, junction or symlink in package path: $Directory"
            }
        }
        $Acl = Get-Acl -LiteralPath $FullPath
        $Allowed = @('S-1-5-18', 'S-1-5-32-544')
        if (-not $Acl.AreAccessRulesProtected -or
            $Acl.GetOwner([Security.Principal.SecurityIdentifier]).Value -notin $Allowed) {
            throw "Directory must be owned by SYSTEM/Administrators with inheritance disabled: $FullPath"
        }
        foreach ($Rule in $Acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
            if ($Rule.AccessControlType -eq 'Allow' -and $Rule.IdentityReference.Value -notin $Allowed) {
                throw "Directory grants access to another principal: $FullPath"
            }
        }
        Write-Verbose "Validated and locked directory: $FullPath; owner: $($Acl.Owner); ACL: SYSTEM/Administrators"
        return [pscustomobject]@{ Path = $FullPath; Handles = $Handles }
    } catch {
        for ($Index = $Handles.Count - 1; $Index -ge 0; $Index--) { $Handles[$Index].Dispose() }
        throw
    }
}

function Close-DOLocalPackageDirectory {
    param($Directory)
    if ($Directory) {
        for ($Index = $Directory.Handles.Count - 1; $Index -ge 0; $Index--) {
            $Directory.Handles[$Index].Dispose()
        }
    }
}

function Stop-DOLocalPackageTask {
    $TaskName = 'DO-Monitor Local Collector'
    $Existing = @(Get-ScheduledTask -TaskPath '\' -ErrorAction Stop | Where-Object TaskName -eq $TaskName)
    if ($Existing.Count -eq 0) { return $false }
    Disable-ScheduledTask -TaskName $TaskName -TaskPath '\' | Out-Null
    Stop-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction Stop
    $Deadline = (Get-Date).AddSeconds(30)
    do {
        $Task = Get-ScheduledTask -TaskName $TaskName -TaskPath '\' -ErrorAction Stop
        if ($Task.State -ne 'Running') { return $true }
        Start-Sleep -Milliseconds 200
    } while ((Get-Date) -lt $Deadline)
    throw 'Existing local collector did not stop within 30 seconds.'
}

Export-ModuleMember -Function Assert-DOLocalPackageHost, Open-DOLocalPackageDirectory, Close-DOLocalPackageDirectory, Stop-DOLocalPackageTask
