$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '../WinCacheCleaner.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$root = Join-Path ([IO.Path]::GetTempPath()) ('wcc-scan-' + [guid]::NewGuid())
try {
    [void][IO.Directory]::CreateDirectory($root)
    foreach ($i in 1..300) { [IO.File]::WriteAllBytes((Join-Path $root "$i.nvph"), [byte[]](1,2,3)) }
    $state = New-ScanProgress 'Fixture' $root
    $result = [pscustomobject]@{ Count=0; Bytes=[long]0 }
    Visit-Files $root { param($file) $result.Count++; $result.Bytes += $file.Length } -ScanState $state
    Complete-ScanProgress $state
    Assert ($result.Count -eq 300 -and $state.Files -eq 300 -and $state.Bytes -eq 900) 'Progress scan omitted files'
    $state = New-ScanProgress 'Expired fixture' $root
    $state.DeadlineUtc = [datetime]::UtcNow.AddSeconds(-1)
    Visit-Files $root { throw 'Expired scan visited a file' } -ScanState $state
    Assert ($state.Skipped -and $state.Files -eq 0) 'Expired scan was not skipped'
    [IO.File]::WriteAllText((Join-Path $root 'save.dat'), 'save')
    function Get-GpuGameTargets {
        param($DriveRoot)
        return [pscustomobject]@{ Name='Fixture GPU'; Path=$root; Pattern='*.nvph'; Recurse=$true }
    }
    $scan = Scan-GpuGame ([IO.Path]::GetPathRoot($root))
    Assert ($scan.Total -eq 900 -and $scan.Entries.Count -eq 1) 'Normal GPU scan failed'
    $completeScan = $scan
    function Test-ScanSkipRequested { return $true }
    $scan = Scan-GpuGame ([IO.Path]::GetPathRoot($root))
    Assert ($scan.Total -eq 0 -and $scan.Entries.Count -eq 0) 'Skipped GPU target was available for cleanup'
    Assert ((Get-ChildItem -LiteralPath $root -File).Count -eq 301) 'Scanning changed files'
    $removed = Clean-GpuEntries $completeScan.Entries
    Assert ($removed.Count -eq 300 -and $removed.Bytes -eq 900) 'GPU cleanup callback did not complete'
    Assert (Test-Path (Join-Path $root 'save.dat')) 'GPU pattern removed unrelated data'
    'PASS: GPU cleanup and non-cache preservation; scan counts, timeout cancellation, Escape cancellation, skipped-target exclusion, scan remains read-only'
} finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
