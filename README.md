# WinCacheCleaner

Interactive Windows 10/11 cleaner, PowerShell 5.1+, no runtime dependencies.
Run from the directory containing the script:

```powershell
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1 -AnalyzeOnly
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1
```

Use arrows to navigate, Space to select, Enter to continue, Esc to return.
Scan-only mode does not delete files or export reports. Normal cleanup requires
`CLEAN` after a preview. Administrator rights are needed only for protected
system targets and disabling hibernation.

- Common: TEMP files older than 7 days, WER reports older than 14 days.
- GPU/game caches: individually selected known paths; shaders may rebuild.
- Browser cache (off by default): Chrome/Edge Default, Profile *, Guest Profile;
  Firefox profiles under LocalAppData. Only Cache, Code Cache, GPUCache or
  Firefox cache2 contents. Close the browser first; running browsers are skipped.
  Cookies, passwords, history, bookmarks and sessions are outside these targets.
  Custom/portable browser locations are not discovered.
- Possible leftovers (off by default): direct Cache, Code Cache, GPUCache and
  Temp children of unmatched application folders in Local/Roaming/LocalLow
  AppData and ProgramData. Only files older than 30 days. Uses Uninstall registry
  names and current-user AppX names. Requires individual selection, `LEFTOVERS`,
  then `CLEAN`. No name match is **not proof of an uninstall**; portable apps,
  shared components and incomplete inventories make this heuristic uncertain.
  Empty inventories produce no deletion candidates. Shared system/vendor roots
  are excluded. Whole application folders, settings and saves are never targets.
- AppData audit: largest folders, report only. No automatic report files.
- Recycle Bin and hibernation: explicit optional existing operations.

Candidate sizes are **logical file sizes**, not allocated disk usage. The final
free-space delta is measured from the drive and may include unrelated activity.
Inaccessible files may be omitted from scanning; estimates can be incomplete.
Links/junctions are skipped. Files can change between scan and cleanup; this is
not a snapshot. Close affected applications before cleaning. Arbitrary hostile
filesystem changes during cleanup are outside this tool's guarantees.

Windows Update/DISM, developer caches, Docker/WSL diagnostics and allocated-size
accounting from the broader design document are not implemented in this version.

## Validation

```powershell
pwsh -NoProfile -File .\tests\Safety.Tests.ps1
```

The fixture suite uses temporary data only. It checks discovery, read-only scans,
closed-browser enforcement, age filtering, deletion of selected cache contents,
preservation of cookies/saves/new files, and directory-link exclusion. Creating
the test symbolic link on Windows may require Developer Mode or elevation.
Linux PowerShell 7 validation does not establish Windows PowerShell 5.1, real
registry/AppX, Windows file-locking or interactive terminal compatibility.

## Versions and branches

Current version: **0.3.0**. Display it with:

```powershell
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1 -Version
```

Use `develop` for subsequent changes and merge reviewed changes into `main`.
Before a new release, increment `VERSION` and `$script:AppVersion` in the script
using MAJOR.MINOR.PATCH and update `CHANGELOG.md`. Keep the header version aligned.
The standalone script includes its version; it needs no external version file at runtime.

GitHub Actions validates syntax, version consistency and safety fixtures on Linux
PowerShell 7, Windows PowerShell 7 and Windows PowerShell 5.1. After successful
checks on `main`, it automatically creates `v<VERSION>` on the exact tested commit
and publishes the script, SHA256 checksum and a ZIP with documentation/license.
An existing version/tag is left untouched; bump the version for another release.
`develop` and pull requests run validation without publishing. The workflow can
also be rerun manually from `main`. GitHub Actions must be enabled with permission
for the release job to write repository contents.
