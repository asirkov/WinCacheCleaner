# Build a standalone CMD containing the exact UTF-8 PowerShell source.
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '../../dist'))
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$version = (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()
if ($version -notmatch '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$') { throw 'Invalid release version' }
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
[void][IO.Directory]::CreateDirectory($OutputDirectory)
$files = @('WinCacheCleaner.ps1', 'README.md', 'LICENSE', 'CHANGELOG.md', 'VERSION')
foreach ($file in $files) { Copy-Item -LiteralPath (Join-Path $repoRoot $file) -Destination (Join-Path $OutputDirectory $file) -Force }
$payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $repoRoot 'WinCacheCleaner.ps1')))
# Decode in memory; no installation, temporary PS1 or execution-policy changes.
# Only known switches are accepted; argument text is never evaluated as code.
$launcher = @'
@echo off
setlocal
set "WCC_LAUNCHER=%~f0"
set "WCC_MODE=%~1"
powershell.exe -NoLogo -NoProfile -Command "$ErrorActionPreference='Stop'; $mode=$env:WCC_MODE; if ($mode -and $mode -notin @('-Version','-AnalyzeOnly')) { throw 'Use no arguments, -Version or -AnalyzeOnly.' }; $parts=[IO.File]::ReadAllText($env:WCC_LAUNCHER) -split '(?m)^::WCC_PAYLOAD\r?$'; if ($parts.Count -ne 2) { throw 'Invalid launcher payload' }; $source=[Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($parts[1].Trim())).TrimStart([char]0xFEFF); $parameters=@{}; if ($mode -eq '-Version') { $parameters.Version=$true }; if ($mode -eq '-AnalyzeOnly') { $parameters.AnalyzeOnly=$true }; & ([scriptblock]::Create($source)) @parameters"
set "WCC_EXIT=%ERRORLEVEL%"
if not defined WCC_MODE pause
exit /b %WCC_EXIT%
::WCC_PAYLOAD
'@
$cmdPath = Join-Path $OutputDirectory 'WinCacheCleaner.cmd'
$cmdText = ($launcher.TrimEnd() + "`n" + $payload + "`n") -replace "`r?`n", "`r`n"
[IO.File]::WriteAllText($cmdPath, $cmdText, [Text.Encoding]::ASCII)
$notes = New-Object 'System.Collections.Generic.List[System.String]'
$collect = $false
foreach ($line in Get-Content -LiteralPath (Join-Path $repoRoot 'CHANGELOG.md') -Encoding UTF8) {
    if ($line -ceq "## $version") { $collect = $true; continue }
    if ($collect -and $line -match '^## ') { break }
    if ($collect) { $notes.Add($line) }
}
if (-not $collect -or [string]::IsNullOrWhiteSpace(($notes -join "`n"))) { throw "Missing changelog for $version" }
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'RELEASE_NOTES.md'), (($notes -join "`n").Trim() + "`n"), [Text.UTF8Encoding]::new($false))
$files += @('WinCacheCleaner.cmd', 'RELEASE_NOTES.md')
$checksumLines = foreach ($file in $files) {
    $hash = (Get-FileHash -LiteralPath (Join-Path $OutputDirectory $file) -Algorithm SHA256).Hash.ToLowerInvariant()
    '{0}  {1}' -f $hash, $file
}
[IO.File]::WriteAllText((Join-Path $OutputDirectory 'SHA256SUMS.txt'), (($checksumLines -join "`n") + "`n"), [Text.Encoding]::ASCII)
$files += 'SHA256SUMS.txt'
$paths = @($files | ForEach-Object { Join-Path $OutputDirectory $_ })
Compress-Archive -LiteralPath $paths -DestinationPath (Join-Path $OutputDirectory "WinCacheCleaner-v$version.zip") -Force
Write-Host "Built WinCacheCleaner v$version in $OutputDirectory"
