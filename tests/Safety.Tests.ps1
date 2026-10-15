$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../WinCacheCleaner.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('wcc-test-' + [guid]::NewGuid())
try {
    $env:LOCALAPPDATA = Join-Path $root 'Local'
    $env:APPDATA = Join-Path $root 'Roaming'
    $env:USERPROFILE = $root
    $env:ProgramData = Join-Path $root 'ProgramData'
    $profile = Join-Path $env:LOCALAPPDATA 'Google/Chrome/User Data/Default'
    $cache = Join-Path $profile 'Cache'
    New-Item $cache -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $cache 'cached') 'cache'
    Set-Content (Join-Path $profile 'Cookies') 'private'
    $drive = [IO.Path]::GetPathRoot($root)
    $targets = @(Get-BrowserTargets $drive)
    Assert ($targets.Count -eq 1) 'Expected exactly one Chrome cache'
    $scan = Scan-CacheTargets $targets
    Assert ($scan.Entries.Count -eq 1 -and $scan.Total -gt 0) 'Browser scan empty'
    Assert (Test-Path (Join-Path $cache 'cached')) 'Scan changed files'
    # A running browser blocks removal; do not depend on host process names.
    function Get-Process { param($Name, $ErrorAction) return [pscustomobject]@{Name=$Name} }
    $blocked = Clean-CacheEntries $scan.Entries
    Assert ($blocked.Count -eq 0 -and (Test-Path (Join-Path $cache 'cached'))) 'Running browser was cleaned'
    Remove-Item Function:Get-Process
    $clean = Clean-CacheEntries $scan.Entries
    Assert ($clean.Count -eq 1) 'Cache not removed'
    Assert (Test-Path (Join-Path $profile 'Cookies')) 'Cookies removed'
    function Get-InstalledNames { return @('installedapplication') }
    $app = Join-Path $env:LOCALAPPDATA 'RemovedApplication'
    $temp = Join-Path $app 'Temp'
    New-Item $temp -ItemType Directory -Force | Out-Null
    Set-Content (Join-Path $temp 'old.tmp') 'old'
    Set-Content (Join-Path $temp 'fresh.tmp') 'fresh'
    Set-Content (Join-Path $app 'save.dat') 'save'
    (Get-Item (Join-Path $temp 'old.tmp')).LastWriteTimeUtc = [datetime]::UtcNow.AddDays(-40)
    $targets = @(Get-LeftoverTargets $drive)
    Assert ($targets.Count -eq 1) 'Unexpected leftover candidates'
    $scan = Scan-CacheTargets $targets
    Assert ($scan.Entries[0].Count -eq 1) 'Fresh files counted as old'
    $clean = Clean-CacheEntries $scan.Entries
    Assert ($clean.Count -eq 1) 'Old temporary file not cleaned'
    Assert (Test-Path (Join-Path $temp 'fresh.tmp')) 'Fresh file removed'
    Assert (Test-Path (Join-Path $app 'save.dat')) 'Save removed'
    $outside = Join-Path $root 'outside'
    New-Item $outside -ItemType Directory | Out-Null
    Set-Content (Join-Path $outside 'keep') 'keep'
    New-Item (Join-Path $temp 'linked') -ItemType SymbolicLink -Target $outside | Out-Null
    $result = Measure-Directory $temp
    Assert ($result.Count -eq 1) 'Traversal followed directory link'
    Assert (-not (Test-SafeCachePath (Join-Path $temp 'linked'))) 'Linked target accepted'
    'PASS: browser detection, read-only scan, running-browser guard, cache removal, cookies/saves/fresh-file preservation, age filter, symlink exclusion'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
