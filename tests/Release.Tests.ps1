# Main-branch packaging check. Never starts the interactive cleaner.
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '../dist'))
$ErrorActionPreference = 'Stop'
$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$cmdPath = Join-Path $OutputDirectory 'WinCacheCleaner.cmd'
$text = [IO.File]::ReadAllText($cmdPath)
$parts = $text -split '(?m)^::WCC_PAYLOAD\r?$'
if ($parts.Count -ne 2) { throw 'Invalid CMD payload marker' }
$payload = [Convert]::FromBase64String($parts[1].Trim())
$original = [IO.File]::ReadAllBytes((Join-Path $repoRoot 'WinCacheCleaner.ps1'))
if ([Convert]::ToBase64String($payload) -cne [Convert]::ToBase64String($original)) { throw 'Embedded source differs from the release source' }
$source = [Text.Encoding]::UTF8.GetString($payload).TrimStart([char]0xFEFF)
$version = (Get-Content (Join-Path $repoRoot 'VERSION') -Raw).Trim()
$actual = & ([scriptblock]::Create($source)) -Version
if ($actual -cne $version) { throw 'Embedded script reports the wrong version' }
foreach ($line in Get-Content (Join-Path $OutputDirectory 'SHA256SUMS.txt')) {
    if ($line -notmatch '^([a-f0-9]{64}) [ *](.+)$') { throw 'Invalid checksum line' }
    $expected = $Matches[1]
    $file = $Matches[2]
    if ((Get-FileHash -LiteralPath (Join-Path $OutputDirectory $file) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $expected) { throw "Checksum mismatch: $file" }
}
$notes = Get-Content (Join-Path $OutputDirectory 'RELEASE_NOTES.md') -Encoding UTF8 -Raw
if ([string]::IsNullOrWhiteSpace($notes) -or $notes -notmatch ('(?m)^## .*v' + [regex]::Escape($version) + '$')) { throw 'Git release notes are empty or report the wrong version' }
$archive = Join-Path $OutputDirectory "WinCacheCleaner-v$version.zip"
$unpack = Join-Path ([IO.Path]::GetTempPath()) ('wcc-package-' + [guid]::NewGuid())
try {
    Expand-Archive -LiteralPath $archive -DestinationPath $unpack
    foreach ($file in @('WinCacheCleaner.cmd','WinCacheCleaner.ps1','README.md','LICENSE','VERSION','RELEASE_NOTES.md','SHA256SUMS.txt')) {
        if (-not (Test-Path -LiteralPath (Join-Path $unpack $file))) { throw "ZIP missing $file" }
    }
    if ([Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT) {
        # Execute the real CMD using a directory containing spaces; no cleanup.
        $spacePath = Join-Path $unpack 'directory with spaces'
        [void][IO.Directory]::CreateDirectory($spacePath)
        $standalone = Join-Path $spacePath 'WinCacheCleaner.cmd'
        Copy-Item -LiteralPath $cmdPath -Destination $standalone
        $output = & $standalone -Version
        if ($LASTEXITCODE -ne 0 -or (($output | Out-String).Trim() -cne $version)) { throw 'Standalone CMD -Version failed on Windows' }
        $savedPreference = $ErrorActionPreference
        try {
            $ErrorActionPreference = 'Continue'
            $failure = & $standalone -Unsupported 2>&1
        } finally { $ErrorActionPreference = $savedPreference }
        if ($LASTEXITCODE -eq 0) { throw 'Launcher accepted an unsupported switch' }
        # The rejected switch is an expected failure. Do not let Actions inherit it.
        $global:LASTEXITCODE = 0
        Write-Host 'PASS: real Windows CMD launch and invalid-switch exit status'
    } else {
        Write-Host 'Windows CMD execution unrun on this platform; covered by the main-branch Windows packaging job.'
    }
    Write-Host 'PASS: exact embedded source, embedded version, checksums and ZIP contents'
} finally { Remove-Item -LiteralPath $unpack -Recurse -Force -ErrorAction SilentlyContinue }
