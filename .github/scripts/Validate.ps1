$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tokens = $null
$errors = $null
$scriptPath = Join-Path $repoRoot 'WinCacheCleaner.ps1'
[void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
$version = (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') {
    throw 'VERSION must be MAJOR.MINOR.PATCH'
}
$actual = & $scriptPath -Version
if ($actual -cne $version) { throw 'Script version differs from VERSION' }
& (Join-Path $repoRoot 'tests/Safety.Tests.ps1')
