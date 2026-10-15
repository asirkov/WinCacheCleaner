# WinCacheCleaner

Interactive Windows 10/11 cleaner, PowerShell 5.1+, no runtime dependencies.
Run from the directory containing the script:

```powershell
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1 -AnalyzeOnly
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1
```

If Windows reports that running scripts is disabled, after reviewing/trusting the
downloaded script you can allow it for this process only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File ".\WinCacheCleaner.ps1" -AnalyzeOnly
```

Omit `-AnalyzeOnly` to open cleanup. `-ExecutionPolicy Bypass` here does not change
the saved user/machine policy; organizational Group Policy can still override it.
There is no need to set a permanent `Unrestricted` policy. The standalone CMD
runs the embedded source in memory rather than loading a PS1 file.

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

Current version: **0.4.0**. Display it with:

```powershell
powershell.exe -NoProfile -File .\WinCacheCleaner.ps1 -Version
```

Use `develop` for subsequent changes. Promote releases in this order:
`develop -> release-<VERSION> -> main -> develop`. Release branches run validation;
packaging and publication run only on `main`.
Before a new release, increment `VERSION` and `$script:AppVersion` in the script
using MAJOR.MINOR.PATCH. Keep the header version aligned. Write clear commit
subjects: release notes are generated from Git commits after the previous
ancestor version tag, with commit links and a comparison link. There is no
separate manually maintained changelog. The first release includes all commits;
rerunning an existing version excludes its own tag when computing the range.
The standalone script includes its version; it needs no external version file at runtime.

GitHub Actions validates syntax, version consistency and safety fixtures on Linux
PowerShell 7, Windows PowerShell 7 and Windows PowerShell 5.1. After successful
checks on `main`, it automatically creates `v<VERSION>` on the exact tested commit
and publishes the standalone CMD, script, SHA256 checksums and a ZIP with documentation/license.
Existing release tags and assets are preserved; bump the version for another release.
An existing tag without a release is published using source/docs from that exact tag.
For an existing release, Actions refreshes only its notes from the tagged commit,
using English headings and link labels.
`develop` and pull requests run source validation only, without building release packages or publishing. The workflow can
also be rerun manually from `main`. GitHub Actions must be enabled with permission
for the release job to write repository contents.

## Standalone Windows download

Download `WinCacheCleaner.cmd` from a release and double-click it. It contains the
complete script and requires only built-in Windows PowerShell 5.1; no installer
or separate PS1 file is needed. It decodes the script in memory, preserves the
interactive confirmations, and does not change execution policy or elevate itself.
If your organization blocks PowerShell, its policy still applies.

```cmd
WinCacheCleaner.cmd -AnalyzeOnly
WinCacheCleaner.cmd -Version
```

CI entry points are Bash scripts without extensions under `ci/`. Run from
Bash (Git Bash on Windows); each entry point resolves the project root itself:

```bash
./ci/validate
./ci/build
./ci/test-package
```

Requirements: Bash, Git with full history/tags, base64, sed, sha256sum and PowerShell.
The default engine is `pwsh`; set `POWERSHELL=powershell.exe` to validate with
Windows PowerShell 5.1. PowerShell is used to inspect/run PowerShell source/tests
and create ZIP files; no separate PowerShell CI helper scripts are required.
`ci/git-notes` prints generated notes. `ci/release` publishes only in a main-branch
GitHub Actions context. Actions uses `fetch-depth: 0` for notes generation.

The main-branch packaging job builds on Windows and tests the actual CMD launch
with `-Version`, including a path containing spaces, before release publication.

## Contribution rules

See [AGENTS.md](AGENTS.md). Write all new commit messages in English using
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/),
for example `fix(browser): preserve profile settings` or `ci: validate release packages`.
Run `./ci/check-commits` before pushing. It installs pinned development-only
commitlint tools with `npm ci` (Node.js 20+) and checks commits after the documented
adoption baseline, including explicit merges. Existing released history is retained.
CI checks PR branch commits instead of GitHub's synthetic merge commit.

GPU/game scans show file counts, logical bytes and elapsed time. Press Esc to
skip the current GPU/game target; skipped targets are excluded from cleanup.
The per-target limit defaults to 120 seconds; for a slow disk, use
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinCacheCleaner.ps1 -ScanTimeoutSeconds 600`.
Scanning reads metadata, not file contents. The timer/Esc check runs between
filesystem operations; it cannot interrupt a single blocked OS call. Ctrl+C
stops the scan, before any cleanup confirmation.

Planned for 0.4.1: support a `latest` tag. This is separate from the 0.4.0 release.
