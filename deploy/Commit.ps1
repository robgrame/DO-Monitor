<#
.SYNOPSIS
    DO-Monitor — Commit with automatic semantic versioning.
.DESCRIPTION
    Increments the version in the VERSION file, updates the README badge,
    stages all changes, commits with the version tag, and optionally pushes.

    Version format: MAJOR.MINOR.PATCH
    - Patch: bug fixes, minor changes (default)
    - Minor: new features, non-breaking changes
    - Major: breaking changes
.EXAMPLE
    .\Commit.ps1 -Message "Fix SB binding issue"
    .\Commit.ps1 -Message "Add health endpoint" -Bump Minor
    .\Commit.ps1 -Message "Migrate to .NET 10" -Bump Major
    .\Commit.ps1 -Message "Fix typo" -NoPush
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Message,

    [ValidateSet("Patch", "Minor", "Major")]
    [string]$Bump = "Patch",

    [switch]$NoPush,
    [switch]$NoTag
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$RepoRoot = $PSScriptRoot | Split-Path
$VersionFile = Join-Path $RepoRoot "VERSION"
$ReadmeFile = Join-Path $RepoRoot "README.md"

# ---- Read current version ----
if (-not (Test-Path $VersionFile)) {
    "1.0.0" | Out-File -FilePath $VersionFile -Encoding utf8 -NoNewline
}

$CurrentVersion = (Get-Content $VersionFile -Raw).Trim()
$Parts = $CurrentVersion.Split('.')
if ($Parts.Count -ne 3) {
    Write-Error "Invalid version format in VERSION file: '$CurrentVersion'. Expected MAJOR.MINOR.PATCH"
    exit 1
}

$Major = [int]$Parts[0]
$Minor = [int]$Parts[1]
$Patch = [int]$Parts[2]

# ---- Bump version ----
switch ($Bump) {
    "Major" { $Major++; $Minor = 0; $Patch = 0 }
    "Minor" { $Minor++; $Patch = 0 }
    "Patch" { $Patch++ }
}

$NewVersion = "$Major.$Minor.$Patch"

Write-Host ""
Write-Host "  Version: $CurrentVersion → $NewVersion ($Bump)" -ForegroundColor Cyan
Write-Host "  Message: $Message" -ForegroundColor White
Write-Host ""

# ---- Update VERSION file ----
$NewVersion | Out-File -FilePath $VersionFile -Encoding utf8 -NoNewline

# ---- Update README version badge ----
if (Test-Path $ReadmeFile) {
    $ReadmeContent = Get-Content $ReadmeFile -Raw
    $ReadmeUpdated = $ReadmeContent -replace '\*\*v\d+\.\d+\.\d+\*\*', "**v$NewVersion**"
    if ($ReadmeUpdated -ne $ReadmeContent) {
        $ReadmeUpdated | Out-File -FilePath $ReadmeFile -Encoding utf8 -NoNewline
        Write-Host "  README version updated." -ForegroundColor Gray
    }
}

# ---- Git commit ----
Push-Location $RepoRoot
try {
    git add -A

    $Status = git status --porcelain
    if (-not $Status) {
        Write-Host "  Nothing to commit." -ForegroundColor Yellow
        exit 0
    }

    $CommitMessage = "v$NewVersion — $Message`n`nCo-authored-by: Copilot <223556219+Copilot@users.noreply.github.com>"
    git commit -m $CommitMessage

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Git commit failed!"
        exit 1
    }

    # ---- Tag ----
    if (-not $NoTag) {
        git tag -a "v$NewVersion" -m "v$NewVersion — $Message"
        Write-Host "  Tagged: v$NewVersion" -ForegroundColor Green
    }

    # ---- Push ----
    if (-not $NoPush) {
        Write-Host "  Pushing..." -ForegroundColor Gray
        git push
        if (-not $NoTag) { git push --tags }
        Write-Host "  Pushed to origin." -ForegroundColor Green
    }

    Write-Host ""
    Write-Host "  ✓ v$NewVersion committed successfully." -ForegroundColor Green
    Write-Host ""
} finally {
    Pop-Location
}
