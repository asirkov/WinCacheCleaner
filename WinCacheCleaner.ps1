#requires -Version 5.1
<#
WinCacheCleaner v1.0.0
Run in Windows Terminal / PowerShell (preferably as Administrator).
Space toggles a choice, Enter starts, Esc goes back.
AppData audit is report-only. GPU/game caches are reviewed individually before cleanup.
#>

param([switch]$AnalyzeOnly, [switch]$Version, [ValidateRange(1, 86400)][int]$ScanTimeoutSeconds = 120)

$script:AppVersion = '1.0.0'

$ErrorActionPreference = 'Stop'
$MinimumAgeDays = 7
$WERMinimumAgeDays = 14

function Confirm-Action([string]$Prompt) {
    return (Read-Host "$Prompt [y/N]") -ieq 'y'
}

function Format-Size([long]$Bytes) {
    if ($Bytes -lt 0) { return ('-{0}' -f (Format-Size ([long](-$Bytes)))) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N0} KB' -f ($Bytes / 1KB)) }
    return "$Bytes B"
}

function Test-SelectedDrive([string]$Path, [string]$DriveRoot) {
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try {
        return ([IO.Path]::GetPathRoot([IO.Path]::GetFullPath($Path)) -ieq $DriveRoot)
    } catch { return $false }
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function New-ScanProgress([string]$Title, [string]$Path) {
    return [pscustomobject]@{
        Title=$Title; Path=$Path; Files=0; Bytes=[long]0; Skipped=$false; Reason=''
        Clock=[Diagnostics.Stopwatch]::StartNew(); LastUpdate=[long]-500
        DeadlineUtc=[datetime]::UtcNow.AddSeconds($ScanTimeoutSeconds)
    }
}

function Test-ScanSkipRequested {
    try {
        if (-not [Console]::IsInputRedirected -and [Console]::KeyAvailable) {
            return [Console]::ReadKey($true).Key -eq [ConsoleKey]::Escape
        }
    } catch { } # Hosts without console input still receive progress.
    return $false
}

function Update-ScanProgress($State, $File = $null, [switch]$Force) {
    if ($null -eq $State) { return }
    if ($null -ne $File) {
        $State.Files++
        $State.Bytes += [long]$File.Length
    }
    $elapsed = $State.Clock.ElapsedMilliseconds
    if (-not $Force -and ($elapsed - $State.LastUpdate) -lt 250) { return }
    $State.LastUpdate = $elapsed
    if ([datetime]::UtcNow -ge $State.DeadlineUtc) {
        $State.Skipped = $true
        $State.Reason = 'scan time limit reached'
    } elseif (Test-ScanSkipRequested) {
        $State.Skipped = $true
        $State.Reason = 'Esc pressed'
    }
    $status = '{0} files, {1}, {2:N1}s | Esc: skip category' -f $State.Files, (Format-Size $State.Bytes), $State.Clock.Elapsed.TotalSeconds
    Write-Progress -Id 7 -Activity $State.Title -Status $status -CurrentOperation $State.Path
}

function Complete-ScanProgress($State) {
    if ($null -eq $State) { return }
    $State.Clock.Stop()
    Write-Progress -Id 7 -Activity $State.Title -Completed
    if ($State.Skipped) {
        Write-Warning "$($State.Title): skipped ($($State.Reason)); partial results excluded from cleanup."
    } else {
        Write-Host ('  {0} files scanned in {1:N1}s.' -f $State.Files, $State.Clock.Elapsed.TotalSeconds) -ForegroundColor DarkGray
    }
}

# Traverse filesystem metadata without reading contents or following reparse points.
# Optional scan state is never supplied by cleanup functions.
# Use a distinct callback name: $Action belongs to Visit-GpuTargetFiles.
function Visit-Files([string]$Root, [scriptblock]$Visitor, $ScanState = $null) {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    Update-ScanProgress $ScanState -Force
    if ($null -ne $ScanState -and $ScanState.Skipped) { return }
    $folders = New-Object 'System.Collections.Generic.Stack[System.String]'
    $folders.Push($Root)
    while ($folders.Count -gt 0) {
        if ($null -ne $ScanState -and $ScanState.Skipped) { break }
        $path = $folders.Pop()
        try {
            $dir = [System.IO.DirectoryInfo]::new($path)
            if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            foreach ($file in $dir.EnumerateFiles()) {
                try {
                    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    Update-ScanProgress $ScanState $file
                    if ($null -ne $ScanState -and $ScanState.Skipped) { break }
                    & $Visitor $file
                } catch { } # Locked and inaccessible files are skipped.
            }
            if ($null -ne $ScanState -and $ScanState.Skipped) { break }
            foreach ($subdir in $dir.EnumerateDirectories()) {
                try {
                    Update-ScanProgress $ScanState
                    if ($null -ne $ScanState -and $ScanState.Skipped) { break }
                    if (($subdir.Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) {
                        $folders.Push($subdir.FullName)
                    }
                } catch { }
            }
        } catch { } # Inaccessible directories are skipped.
    }
}

function Measure-Directory([string]$Path, $BeforeUtc = $null) {
    $result = [pscustomobject]@{ Bytes = [long]0; Count = 0 }
    Visit-Files $Path {
        param($file)
        if (($null -eq $BeforeUtc) -or ($file.LastWriteTimeUtc -lt [datetime]$BeforeUtc)) {
            $result.Bytes += [long]$file.Length
            $result.Count++
        }
    }
    return $result
}

function Get-CommonTargets([string]$DriveRoot) {
    $candidates = @(
        [pscustomobject]@{ Name = 'User TEMP'; Path = $env:TEMP; Days = $MinimumAgeDays }
        [pscustomobject]@{ Name = 'Windows TEMP'; Path = (Join-Path $env:WINDIR 'Temp'); Days = $MinimumAgeDays }
        [pscustomobject]@{ Name = 'WER ReportArchive'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportArchive'); Days = $WERMinimumAgeDays }
        [pscustomobject]@{ Name = 'WER ReportQueue'; Path = (Join-Path $env:ProgramData 'Microsoft\Windows\WER\ReportQueue'); Days = $WERMinimumAgeDays }
    )
    $seen = @{}
    $targets = @()
    foreach ($candidate in $candidates) {
        if (-not (Test-SelectedDrive $candidate.Path $DriveRoot)) { continue }
        if (-not (Test-Path -LiteralPath $candidate.Path -PathType Container)) { continue }
        $canonical = [IO.Path]::GetFullPath($candidate.Path).TrimEnd('\').ToLowerInvariant()
        if ($seen.ContainsKey($canonical)) { continue }
        $seen[$canonical] = $true
        $targets += $candidate
    }
    return @($targets)
}

function Scan-Common($Targets) {
    $found = @()
    $sum = [long]0
    foreach ($target in $Targets) {
        Write-Host "Scanning $($target.Name)..." -ForegroundColor DarkCyan
        $cutoff = [datetime]::UtcNow.AddDays(-$target.Days)
        $size = Measure-Directory $target.Path $cutoff
        $sum += [long]$size.Bytes
        $found += [pscustomobject]@{ Target = $target; Bytes = [long]$size.Bytes; Count = $size.Count }
    }
    return [pscustomobject]@{ Entries = $found; Total = $sum }
}

# Explicit, narrow cache targets only. Never delete an entire game/AppData folder.
# Pattern matches file names, not directory names. Recurse is only used for known cache folders.
function Get-GpuGameTargets([string]$DriveRoot) {
    $candidates = @(
        [pscustomobject]@{ Id='nvidia-dx'; Name='NVIDIA DirectX shader cache (DXCache)'; Path=(Join-Path $env:LOCALAPPDATA 'NVIDIA\DXCache'); Pattern='*'; Recurse=$true }
        [pscustomobject]@{ Id='nvidia-gl'; Name='NVIDIA OpenGL shader cache (GLCache)'; Path=(Join-Path $env:LOCALAPPDATA 'NVIDIA\GLCache'); Pattern='*'; Recurse=$true }
        [pscustomobject]@{ Id='nvidia-nv'; Name='NVIDIA shader cache (NV_Cache)'; Path=(Join-Path $env:LOCALAPPDATA 'NVIDIA Corporation\NV_Cache'); Pattern='*'; Recurse=$true }
        [pscustomobject]@{ Id='directx'; Name='Windows DirectX shader cache (D3DSCache)'; Path=(Join-Path $env:LOCALAPPDATA 'D3DSCache'); Pattern='*'; Recurse=$true }
        [pscustomobject]@{ Id='wardogs'; Name='Wardogs D3D bytecode cache'; Path=(Join-Path $env:LOCALAPPDATA 'Wardogs\Saved'); Pattern='D3DDriverByteCodeBlob*'; Recurse=$false }
        [pscustomobject]@{ Id='enshrouded'; Name='Enshrouded Vulkan pipeline cache'; Path=(Join-Path $env:LOCALAPPDATA 'enshrouded\caches'); Pattern='vk_pipeline_cache.bin'; Recurse=$false }
        [pscustomobject]@{ Id='bigwalk-log'; Name='Big Walk Player.log'; Path=(Join-Path $env:USERPROFILE 'AppData\LocalLow\House House\Big Walk'); Pattern='Player.log'; Recurse=$false }
    )
    $targets = @()
    foreach ($target in $candidates) {
        if (-not (Test-SelectedDrive $target.Path $DriveRoot)) { continue }
        if (-not (Test-Path -LiteralPath $target.Path -PathType Container)) { continue }
        try {
            $directory = [IO.DirectoryInfo]::new($target.Path)
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
        } catch { continue }
        $targets += $target
    }
    return @($targets)
}

function Visit-GpuTargetFiles($Target, [scriptblock]$Action, $ScanState = $null) {
    if ($Target.Recurse) {
        Visit-Files $Target.Path {
            param($file)
            if ($file.Name -like $Target.Pattern) { & $Action $file }
        } -ScanState $ScanState
    } else {
        Update-ScanProgress $ScanState -Force
        if ($null -ne $ScanState -and $ScanState.Skipped) { return }
        try {
            $dir = [IO.DirectoryInfo]::new($Target.Path)
            if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return }
            foreach ($file in $dir.EnumerateFiles()) {
                try {
                    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    Update-ScanProgress $ScanState $file
                    if ($null -ne $ScanState -and $ScanState.Skipped) { break }
                    if ($file.Name -like $Target.Pattern) { & $Action $file }
                } catch { } # Files in use / inaccessible files are skipped.
            }
        } catch { }
    }
}

function Scan-GpuGame([string]$DriveRoot) {
    $entries = @()
    $total = [long]0
    foreach ($target in @(Get-GpuGameTargets $DriveRoot)) {
        Write-Host "Scanning $($target.Name)..." -ForegroundColor DarkCyan
        $measurement = [pscustomobject]@{ Bytes=[long]0; Count=0 }
        $progress = New-ScanProgress $target.Name $target.Path
        try {
            Visit-GpuTargetFiles $target {
                param($file)
                $measurement.Bytes += [long]$file.Length
                $measurement.Count++
            } -ScanState $progress
        } finally { Complete-ScanProgress $progress }
        if ($progress.Skipped) { continue }
        if ($measurement.Count -gt 0) {
            $entries += [pscustomobject]@{
                Target=$target
                Bytes=[long]$measurement.Bytes
                Count=$measurement.Count
            }
            $total += [long]$measurement.Bytes
        }
    }
    return [pscustomobject]@{ Entries=@($entries); Total=$total }
}

# GPU cache selection is explicit: all entries start UNCHECKED, even if the group is enabled.
function Select-GpuEntries([string]$DriveRoot, $Scan, [string]$Title = 'GPU & Game Caches') {
    $entries = @($Scan.Entries | ForEach-Object {
        [pscustomobject]@{ Item=$_; Checked=$false }
    })
    if ($entries.Count -eq 0) { return ,@() }
    $cursor = 0
    while ($true) {
        Clear-Host
        Write-Host "WinCacheCleaner v$script:AppVersion / $Title" -ForegroundColor Cyan
        Write-Host "Disk: $DriveRoot - choose exact cache groups (nothing preselected)"
        Write-Host 'Close the affected applications. Only listed cache files will be removed.' -ForegroundColor Yellow
        Write-Host ''
        for ($i=0; $i -lt $entries.Count; $i++) {
            $entry = $entries[$i]
            $mark = if ($entry.Checked) { 'x' } else { ' ' }
            $line = ('[{0}] {1} - {2} ({3} files)' -f $mark, $entry.Item.Target.Name, (Format-Size $entry.Item.Bytes), $entry.Item.Count)
            if ($i -eq $cursor) { Write-Host "> $line" -ForegroundColor Cyan }
            else { Write-Host "  $line" }
        }
        Write-Host ''
        Write-Host ('Path: {0}\{1}' -f $entries[$cursor].Item.Target.Path, $entries[$cursor].Item.Target.Pattern) -ForegroundColor DarkGray
        Write-Host 'Arrows: navigate  Space: toggle  Enter: continue  Esc: back' -ForegroundColor DarkCyan
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            'UpArrow' { $cursor = ($cursor - 1 + $entries.Count) % $entries.Count }
            'DownArrow' { $cursor = ($cursor + 1) % $entries.Count }
            'Spacebar' { $entries[$cursor].Checked = -not $entries[$cursor].Checked }
            'Enter' { return ,@($entries | Where-Object { $_.Checked } | ForEach-Object { $_.Item }) }
            'Escape' { return $null }
        }
    }
}

function Clean-GpuEntries($Entries) {
    $removed = [pscustomobject]@{ Bytes=[long]0; Count=0; Failed=0 }
    foreach ($entry in $Entries) {
        Write-Host "Cleaning $($entry.Target.Name)..." -ForegroundColor DarkCyan
        Visit-GpuTargetFiles $entry.Target {
            param($file)
            try {
                $bytes = [long]$file.Length
                $file.Delete()
                $removed.Bytes += $bytes
                $removed.Count++
            } catch { $removed.Failed++ }
        }
    }
    return $removed
}

function Show-DriveMenu {
    $drives = @([IO.DriveInfo]::GetDrives() | Where-Object {
        $_.IsReady -and ($_.DriveType -eq [IO.DriveType]::Fixed -or $_.DriveType -eq [IO.DriveType]::Removable)
    })
    if ($drives.Count -eq 0) { throw 'No available drives.' }
    $cursor = 0
    while ($true) {
        Clear-Host
        Write-Host "WinCacheCleaner v$script:AppVersion" -ForegroundColor Cyan
        Write-Host 'Select a disk (arrows + Enter):' -ForegroundColor White
        Write-Host ''
        for ($i = 0; $i -lt $drives.Count; $i++) {
            $disk = $drives[$i]
            $text = ('{0}  total {1}, free {2}' -f $disk.Name, (Format-Size $disk.TotalSize), (Format-Size $disk.AvailableFreeSpace))
            if ($i -eq $cursor) { Write-Host " > $text" -ForegroundColor Cyan }
            else { Write-Host "   $text" }
        }
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            'UpArrow'   { $cursor = ($cursor - 1 + $drives.Count) % $drives.Count }
            'DownArrow' { $cursor = ($cursor + 1) % $drives.Count }
            'Enter'     { return $drives[$cursor].Name }
            'Escape'    { return $null }
        }
    }
}

function Get-HiberfileSize([string]$DriveRoot) {
    if ($DriveRoot -ine ([IO.Path]::GetPathRoot($env:WINDIR))) { return [long]0 }
    try {
        $file = Get-Item -LiteralPath (Join-Path $DriveRoot 'hiberfil.sys') -Force -ErrorAction Stop
        return [long]$file.Length
    } catch { return [long]0 }
}

function Select-Operations([string]$DriveRoot, $Scan, $GpuScan, $BrowserScan, $LeftoverScan) {
    $systemDisk = $DriveRoot -ieq ([IO.Path]::GetPathRoot($env:WINDIR))
    $appDataDisk = Test-SelectedDrive $env:USERPROFILE $DriveRoot
    $hiberBytes = Get-HiberfileSize $DriveRoot
    $opts = @(
        [pscustomobject]@{ Id='common'; Name='COMMON: old temp files, old error reports'; Info=(Format-Size $Scan.Total); Enabled=($Scan.Entries.Count -gt 0); Checked=$true }
        [pscustomobject]@{ Id='gpu'; Name='GPU & Game Caches: individually select cache groups'; Info=(Format-Size $GpuScan.Total); Enabled=($GpuScan.Entries.Count -gt 0); Checked=$false }
        [pscustomobject]@{ Id='browser'; Name='Browser caches: optional, close browsers first'; Info=(Format-Size $BrowserScan.Total); Enabled=($BrowserScan.Entries.Count -gt 0); Checked=$false }
        [pscustomobject]@{ Id='leftovers'; Name='Possible leftovers: old cache/temp files ONLY, manual review'; Info=(Format-Size $LeftoverScan.Total); Enabled=($LeftoverScan.Entries.Count -gt 0); Checked=$false }
        [pscustomobject]@{ Id='appdata'; Name='AppData audit: largest folders + possible leftovers (REPORT ONLY)'; Info='no deletion'; Enabled=$appDataDisk; Checked=$appDataDisk }
        [pscustomobject]@{ Id='recycle'; Name='Empty Recycle Bin on selected disk'; Info='irreversible'; Enabled=$true; Checked=$false }
        [pscustomobject]@{ Id='hibernation'; Name='Disable hibernation (also disables Fast Startup)'; Info=(Format-Size $hiberBytes); Enabled=($systemDisk -and $hiberBytes -gt 0); Checked=$false }
    )
    $cursor = 0
    while ($true) {
        Clear-Host
        $disk = [System.IO.DriveInfo]::new($DriveRoot)
        Write-Host "WinCacheCleaner v$script:AppVersion / Actions" -ForegroundColor Cyan
        Write-Host ("Disk: $DriveRoot   Free: $(Format-Size $disk.AvailableFreeSpace)")
        Write-Host ''
        for ($i=0; $i -lt $opts.Count; $i++) {
            $o = $opts[$i]
            $mark = if (-not $o.Enabled) { '-' } elseif ($o.Checked) { 'x' } else { ' ' }
            $line = ('[{0}] {1}  [{2}]' -f $mark, $o.Name, $o.Info)
            if (-not $o.Enabled) { $color='DarkGray' }
            elseif ($i -eq $cursor) { $color='Cyan' }
            else { $color='Gray' }
            Write-Host ("{0} {1}" -f $(if ($i -eq $cursor) { '>' } else { ' ' }), $line) -ForegroundColor $color
        }
        Write-Host ''
        Write-Host 'Arrows: navigate  Space: toggle  Enter: continue  Esc: change disk' -ForegroundColor DarkCyan
        Write-Host 'COMMON: files older than 7 days (WER: 14). GPU: manual sub-selection; all ages.' -ForegroundColor DarkGray
        $key = [Console]::ReadKey($true).Key
        switch ($key) {
            'UpArrow' { $cursor = ($cursor - 1 + $opts.Count) % $opts.Count }
            'DownArrow' { $cursor = ($cursor + 1) % $opts.Count }
            'Spacebar' { if ($opts[$cursor].Enabled) { $opts[$cursor].Checked = -not $opts[$cursor].Checked } }
            'Enter' { return ,@($opts | Where-Object { $_.Enabled -and $_.Checked } | ForEach-Object { $_.Id }) }
            'Escape' { return $null }
        }
    }
}

function Clean-Common($Scan) {
    $removed = [pscustomobject]@{ Bytes=[long]0; Count=0; Failed=0 }
    foreach ($entry in $Scan.Entries) {
        $target = $entry.Target
        $cutoff = [datetime]::UtcNow.AddDays(-$target.Days)
        Write-Host "Cleaning $($target.Name)..." -ForegroundColor DarkCyan
        Visit-Files $target.Path {
            param($file)
            if ($file.LastWriteTimeUtc -lt $cutoff) {
                try {
                    $bytes = [long]$file.Length
                    $file.Delete()
                    $removed.Bytes += $bytes
                    $removed.Count++
                } catch { $removed.Failed++ }
            }
        }
    }
    return $removed
}

function Normalize-Name([string]$Name) {
    return ($Name.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]','')
}

function Get-InstalledNames {
    $keys = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $names = New-Object 'System.Collections.Generic.List[System.String]'
    foreach ($key in $keys) {
        foreach ($program in @(Get-ItemProperty -Path $key -ErrorAction SilentlyContinue)) {
            if (-not [string]::IsNullOrWhiteSpace($program.DisplayName)) {
                $value = Normalize-Name $program.DisplayName
                if ($value.Length -ge 5) { $names.Add($value) }
            }
        }
    }
    if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
        try {
            foreach ($app in @(Get-AppxPackage -ErrorAction Stop)) {
                $names.Add((Normalize-Name $app.Name))
            }
        } catch { Write-Warning 'AppX inventory unavailable; unmatched folders remain uncertain.' }
    }
    return @($names)
}


# Cache directories only: never remove whole application folders or profile data.
function Test-SafeCachePath([string]$Path) {
    try {
        $dir = [IO.DirectoryInfo]::new($Path)
        if (-not $dir.Exists) { return $false }
        while ($null -ne $dir) {
            if (($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            $dir = $dir.Parent
        }
        return $true
    } catch { return $false }
}

function New-CacheTarget($Name, $Path, $Days, $ProcessName = '') {
    return [pscustomobject]@{ Id=$Path; Name=$Name; Path=$Path; Pattern='*'; Recurse=$true; Days=$Days; ProcessName=$ProcessName }
}

function Get-BrowserTargets([string]$DriveRoot) {
    $browsers = @(
        @{ Name='Chrome'; Root=(Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data'); Process='chrome' },
        @{ Name='Edge'; Root=(Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data'); Process='msedge' },
        @{ Name='Firefox'; Root=(Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'); Process='firefox' }
    )
    foreach ($browser in $browsers) {
        if (-not (Test-SelectedDrive $browser.Root $DriveRoot)) { continue }
        if (-not (Test-SafeCachePath $browser.Root)) { continue }
        foreach ($profile in @(Get-ChildItem -LiteralPath $browser.Root -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($browser.Name -ne 'Firefox' -and $profile.Name -ne 'Default' -and $profile.Name -notlike 'Profile *' -and $profile.Name -ne 'Guest Profile') { continue }
            $cacheNames = if ($browser.Name -eq 'Firefox') { @('cache2') } else { @('Cache', 'Code Cache', 'GPUCache') }
            foreach ($cacheName in $cacheNames) {
                $path = Join-Path $profile.FullName $cacheName
                if (Test-SafeCachePath $path) {
                    New-CacheTarget "$($browser.Name) / $($profile.Name) / $cacheName" $path 0 $browser.Process
                }
            }
        }
    }
}

function Get-LeftoverTargets([string]$DriveRoot) {
    $installed = @(Get-InstalledNames)
    # No match is a heuristic, including portable apps. Selection is always manual.
    $roots = @($env:LOCALAPPDATA, $env:APPDATA, (Join-Path $env:USERPROFILE 'AppData\LocalLow'), $env:ProgramData)
    $protected = @('Microsoft','Windows','Packages','Package Cache','Google','Mozilla','NVIDIA','NVIDIA Corporation','Temp','D3DSCache')
    foreach ($root in $roots) {
        if (-not (Test-SelectedDrive $root $DriveRoot) -or -not (Test-SafeCachePath $root)) { continue }
        foreach ($folder in @(Get-ChildItem -LiteralPath $root -Directory -Force -ErrorAction SilentlyContinue)) {
            if ($protected -contains $folder.Name -or -not (Test-SafeCachePath $folder.FullName)) { continue }
            $normalized = Normalize-Name $folder.Name
            if ($normalized.Length -lt 5 -or $installed.Count -eq 0) { continue }
            $matched = @($installed | Where-Object { $_.Contains($normalized) -or $normalized.Contains($_) }).Count -gt 0
            if ($matched) { continue }
            foreach ($cacheName in @('Cache','Code Cache','GPUCache','Temp')) {
                $path = Join-Path $folder.FullName $cacheName
                if (Test-SafeCachePath $path) {
                    New-CacheTarget "Possibly orphaned: $($folder.Name) / $cacheName (30+ days)" $path 30
                }
            }
        }
    }
}

function Scan-CacheTargets($Targets) {
    $entries = @()
    $total = [long]0
    foreach ($target in $Targets) {
        $cutoff = if ($target.Days -gt 0) { [datetime]::UtcNow.AddDays(-$target.Days) } else { $null }
        $size = Measure-Directory $target.Path $cutoff
        if ($size.Count -gt 0) {
            $entries += [pscustomobject]@{ Target=$target; Bytes=$size.Bytes; Count=$size.Count }
            $total += $size.Bytes
        }
    }
    return [pscustomobject]@{ Entries=@($entries); Total=$total }
}

function Clean-CacheEntries($Entries) {
    $removed = [pscustomobject]@{ Bytes=[long]0; Count=0; Failed=0 }
    foreach ($entry in $Entries) {
        $target = $entry.Target
        if (-not (Test-SafeCachePath $target.Path)) { $removed.Failed++; continue }
        if ($target.ProcessName -and (Get-Process -Name $target.ProcessName -ErrorAction SilentlyContinue)) {
            Write-Warning "Close $($target.ProcessName); skipping $($target.Path)"
            $removed.Failed++
            continue
        }
        $cutoff = [datetime]::UtcNow.AddDays(-$target.Days)
        Visit-Files $target.Path {
            param($file)
            if ($target.Days -gt 0 -and $file.LastWriteTimeUtc -ge $cutoff) { return }
            try {
                # Recheck ancestor links immediately before deletion.
                if (-not (Test-SafeCachePath $file.DirectoryName)) { $removed.Failed++; return }
                $length = $file.Length
                $file.Delete()
                $removed.Bytes += $length
                $removed.Count++
            } catch { $removed.Failed++ }
        }
    }
    return $removed
}

function Invoke-AppDataAudit([string]$DriveRoot) {
    if (-not (Test-SelectedDrive $env:USERPROFILE $DriveRoot)) { return }
    $installed = @(Get-InstalledNames)
    $roots = @(
        [pscustomobject]@{ Name='Local'; Path=$env:LOCALAPPDATA },
        [pscustomobject]@{ Name='Roaming'; Path=$env:APPDATA },
        [pscustomobject]@{ Name='LocalLow'; Path=(Join-Path $env:USERPROFILE 'AppData\LocalLow') }
    )
    $report = @()
    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root.Path -PathType Container)) { continue }
        Write-Host "AppData audit: $($root.Name)..." -ForegroundColor DarkCyan
        $topFolders = @(Get-ChildItem -LiteralPath $root.Path -Directory -Force -ErrorAction SilentlyContinue)
        $n = 0
        foreach ($folder in $topFolders) {
            $n++
            Write-Progress -Activity "Scanning AppData\$($root.Name)" -Status "$n / $($topFolders.Count): $($folder.Name)" -PercentComplete ([int](100 * $n / [math]::Max(1, $topFolders.Count)))
            if (($folder.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            $measurement = Measure-Directory $folder.FullName
            if ($measurement.Bytes -lt 10MB) { continue }
            $normalized = Normalize-Name $folder.Name
            $matched = $false
            if ($normalized.Length -ge 5) {
                foreach ($name in $installed) {
                    if ($name.Contains($normalized) -or $normalized.Contains($name)) {
                        $matched = $true
                        break
                    }
                }
            }
            $report += [pscustomobject]@{
                Area=$root.Name
                Folder=$folder.Name
                SizeGB=[math]::Round($measurement.Bytes / 1GB, 3)
                SizeBytes=[long]$measurement.Bytes
                FolderModified=$folder.LastWriteTime.ToString('yyyy-MM-dd')
                RegistryNameMatch=$matched
                Path=$folder.FullName
            }
        }
        Write-Progress -Activity "Scanning AppData\$($root.Name)" -Completed
    }
    $report = @($report | Sort-Object -Property SizeBytes -Descending)
    Write-Host ''
    Write-Host 'Largest AppData folders (not matched = NOT proof that an app was uninstalled):' -ForegroundColor Yellow
    $i=0
    foreach ($folder in ($report | Select-Object -First 30)) {
        $i++
        $label = if ($folder.RegistryNameMatch) { 'name match' } else { 'verify' }
        Write-Host ('{0,2}. {1,-8} {2,-30} {3,10}  {4}' -f $i, $folder.Area, $folder.Folder, (Format-Size $folder.SizeBytes), $label)
    }
    if ($report.Count -eq 0) { Write-Host 'No AppData folders above 10 MB found.' }
    Write-Host 'Do not delete AppData folders solely based on the registry-name match.' -ForegroundColor Yellow
}

if ($MyInvocation.InvocationName -eq '.') { return }
if ($Version) { Write-Output $script:AppVersion; return }
if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { throw 'Run this script on Windows 10/11 with PowerShell 5.1+.' }

try {
    while ($true) {
        $driveRoot = Show-DriveMenu
        if ($null -eq $driveRoot) { break }
        Clear-Host
        Write-Host "Scanning safe cleanup candidates on $driveRoot ..." -ForegroundColor Cyan
        $targets = @(Get-CommonTargets $driveRoot)
        $scan = Scan-Common $targets
        $gpuScan = Scan-GpuGame $driveRoot
        $browserScan = Scan-CacheTargets @(Get-BrowserTargets $driveRoot)
        $leftoverScan = Scan-CacheTargets @(Get-LeftoverTargets $driveRoot)
        if ($AnalyzeOnly) {
            foreach ($group in @($scan, $gpuScan, $browserScan, $leftoverScan)) {
                foreach ($entry in $group.Entries) {
                    Write-Host ('{0}: {1} - {2}' -f $entry.Target.Name, (Format-Size $entry.Bytes), $entry.Target.Path)
                }
            }
            [void](Read-Host 'Analysis only: no changes. Enter to return')
            continue
        }
        $selected = Select-Operations $driveRoot $scan $gpuScan $browserScan $leftoverScan
        if ($null -eq $selected) { continue }
        if ($selected.Count -eq 0) { continue }
        $gpuPicked = @()
        if ($selected -contains 'gpu') {
            $gpuPicked = Select-GpuEntries $driveRoot $gpuScan
            if ($null -eq $gpuPicked) { continue } # Esc returns to disk selection without deleting.
            if ($gpuPicked.Count -eq 0) { $selected = @($selected | Where-Object { $_ -ne 'gpu' }) }
        }
        $cachePicked = @()
        $cancelled = $false
        foreach ($kind in @('browser','leftovers')) {
            if ($selected -notcontains $kind) { continue }
            $group = if ($kind -eq 'browser') { $browserScan } else { $leftoverScan }
            $picked = Select-GpuEntries $driveRoot $group $kind
            if ($null -eq $picked) { $cancelled = $true; break }
            $cachePicked += @($picked)
            if ($picked.Count -eq 0) { $selected = @($selected | Where-Object { $_ -ne $kind }) }
        }
        if ($cancelled) { continue }
        if ($selected -contains 'leftovers') {
            Write-Host 'No installed-app match is NOT proof of an uninstall. Portable/shared caches may still be used.' -ForegroundColor Yellow
            if (-not (Confirm-Action 'Accept these manually reviewed cache paths?')) { continue }
        }
        $writes = @($selected | Where-Object { $_ -ne 'appdata' })
        if ($writes.Count -gt 0) {
            Clear-Host
            Write-Host "Selected disk: $driveRoot" -ForegroundColor White
            Write-Host "Actions: $($writes -join ', ')" -ForegroundColor Yellow
            if ($writes -contains 'common') {
                Write-Host ('COMMON: up to {0} of old temporary/cache files will be deleted.' -f (Format-Size $scan.Total))
                foreach ($item in $scan.Entries) {
                    Write-Host ('  {0}: {1} ({2} files)' -f $item.Target.Name, (Format-Size $item.Bytes), $item.Count)
                }
            }
            if ($writes -contains 'gpu') {
                Write-Host 'GPU & GAME: selected cache files (will be regenerated when required):' -ForegroundColor Yellow
                foreach ($entry in $gpuPicked) {
                    Write-Host ('  {0}: {1} ({2} files)' -f $entry.Target.Name, (Format-Size $entry.Bytes), $entry.Count)
                    Write-Host ('    {0}\{1}' -f $entry.Target.Path, $entry.Target.Pattern) -ForegroundColor DarkGray
                }
            }
            foreach ($entry in $cachePicked) {
                Write-Host ('  {0}: {1} ({2} files)' -f $entry.Target.Name, (Format-Size $entry.Bytes), $entry.Count)
                Write-Host $entry.Target.Path -ForegroundColor DarkGray
            }
            if ($writes -contains 'recycle') { Write-Host 'Recycle Bin deletion is permanent.' -ForegroundColor Yellow }
            if ($writes -contains 'hibernation') { Write-Host 'Hibernate, hybrid sleep, and Fast Startup will be disabled.' -ForegroundColor Yellow }
            Write-Host ''
            if (-not (Confirm-Action 'Execute the selected actions?')) {
                Write-Host 'Cancelled; no changes made.'
                [void](Read-Host 'Press Enter to continue')
                continue
            }
        }
        $before = ([System.IO.DriveInfo]::new($driveRoot)).AvailableFreeSpace
        if ($selected -contains 'common') {
            $removed = Clean-Common $scan
            Write-Host ('COMMON: removed {0} files ({1} logical size), {2} failed/skipped.' -f $removed.Count, (Format-Size $removed.Bytes), $removed.Failed) -ForegroundColor Green
        }
        if ($selected -contains 'gpu') {
            $gpuRemoved = Clean-GpuEntries $gpuPicked
            Write-Host ('GPU & GAME: removed {0} files ({1} logical size), {2} failed/skipped.' -f $gpuRemoved.Count, (Format-Size $gpuRemoved.Bytes), $gpuRemoved.Failed) -ForegroundColor Green
        }
        if ($cachePicked.Count -gt 0) {
            $result = Clean-CacheEntries $cachePicked
            Write-Host ('CACHE: removed {0} files ({1} logical size); {2} failed/skipped targets or files.' -f $result.Count, (Format-Size $result.Bytes), $result.Failed)
        }
        if ($selected -contains 'recycle') {
            try {
                $letter = $driveRoot.Substring(0,1)
                Clear-RecycleBin -DriveLetter $letter -Force -Confirm:$false -ErrorAction Stop
                Write-Host 'Recycle Bin cleared.' -ForegroundColor Green
            } catch { Write-Host "Recycle Bin: $($_.Exception.Message)" -ForegroundColor Yellow }
        }
        if ($selected -contains 'hibernation') {
            if (-not (Test-Admin)) { Write-Host 'Hibernation: restart PowerShell as Administrator.' -ForegroundColor Yellow }
            else {
                & powercfg.exe /hibernate off
                if ($LASTEXITCODE -eq 0) { Write-Host 'Hibernation disabled.' -ForegroundColor Green }
                else { Write-Host "Hibernation command failed (exit code $LASTEXITCODE)." -ForegroundColor Yellow }
            }
        }
        $after = ([System.IO.DriveInfo]::new($driveRoot)).AvailableFreeSpace
        Write-Host ('Free space: {0} -> {1} (delta {2})' -f (Format-Size $before), (Format-Size $after), (Format-Size ([long]($after - $before)))) -ForegroundColor Cyan
        if ($selected -contains 'appdata') { Invoke-AppDataAudit $driveRoot }
        [void](Read-Host 'Press Enter to return to disk selection')
    }
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    [void](Read-Host 'Press Enter to exit')
}
