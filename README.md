# WinCacheCleaner

Interactive cache cleaner for **Windows 10/11**. Runs on PowerShell 5.1+ with no
installer or runtime dependencies.

**[Download WinCacheCleaner.cmd](https://github.com/asirkov/WinCacheCleaner/releases/latest/download/WinCacheCleaner.cmd)**
· [All releases](https://github.com/asirkov/WinCacheCleaner/releases)
· [MIT license](LICENSE)

## Quick start

Download the standalone CMD above and double-click it. The launcher includes the
complete script and uses built-in Windows PowerShell.

To scan without deleting files or writing reports, run it from its directory:

```cmd
WinCacheCleaner.cmd -AnalyzeOnly
```

Or run the source script from the repository directory:

```powershell
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1 -AnalyzeOnly
```

Omit `-AnalyzeOnly` to open cleanup. If Windows blocks the PS1, review and trust
the script before adding `-ExecutionPolicy Bypass` before `-File`. This applies
only to that process; organizational policies still apply.

Use **arrows** to navigate, **Space** to select, **Enter** to continue and **Esc**
to go back. Cleanup shows a preview and requires **Y** or **y** at the `[y/N]`
prompt; Enter or any other input cancels.

## What it does

| Target | Behavior |
| --- | --- |
| Temporary files | TEMP files older than 7 days; Windows error reports older than 14 days. |
| GPU and game caches | Known paths, reviewed individually. Shaders may rebuild afterward. |
| Browser caches | Standard Chrome, Edge and Firefox profile caches. Off by default; running browsers are skipped. |
| Possible leftovers | Cache files older than 30 days in unmatched app folders. Off by default; paths require individual selection and an extra confirmation. |
| AppData audit | Lists the largest folders on screen; no deletion or report files. |
| System options | Empty the Recycle Bin or disable hibernation, which also disables hybrid sleep and Fast Startup. Both are optional. |

## Before cleaning

- Close affected applications. Browser cleanup excludes cookies, passwords,
  history, bookmarks and sessions; custom/portable profile paths are not discovered.
- Whole application folders, settings and saves are never cleanup targets.
  Links and junctions are skipped.
- An unmatched app folder is **not proof of an uninstall**. Review possible
  leftovers carefully; portable apps and shared components may still use them.
- Administrator rights are needed only for protected system targets and disabling
  hibernation. Emptying the Recycle Bin permanently deletes its contents.
- Sizes are logical file sizes, not allocated disk usage. Inaccessible or locked
  files are skipped; actual space recovered can differ from the estimate.

GPU/game scans show progress and stop after **120 seconds per target**. Press
**Esc** during a scan to skip that target; partial results are excluded from cleanup.
The timer and Esc are checked between filesystem operations, so a blocked OS call
can delay them. Use these options with either the CMD launcher or PS1 script:

| Option | Purpose |
| --- | --- |
| `-AnalyzeOnly` | Scan without deleting files or writing reports. |
| `-ScanTimeoutSeconds 600` | Allow up to 10 minutes per GPU/game target on slower disks. |
| `-Version` | Print the application version. |

## Development

See [AGENTS.md](AGENTS.md) for contribution and release rules. Create a feature
branch from `develop` and open a PR back into `develop`.

Run checks with Bash/Git Bash, PowerShell 7 and Node.js 20+:

```bash
./ci/check-commits
./ci/validate
```

Tests use isolated temporary fixtures. Linux checks do not verify Windows
PowerShell 5.1, CMD startup, registry/AppX or Windows file locking.
