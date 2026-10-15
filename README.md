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

Requirements: Bash, Git with full history/tags, base64, sed, sha256sum and PowerShell.
The default engine is `pwsh`; set `POWERSHELL=powershell.exe` to validate with
Windows PowerShell 5.1. PowerShell is used to inspect/run PowerShell source/tests
and create ZIP files; no separate PowerShell CI helper scripts are required.
`ci/git-notes` prints generated notes. `ci/release` publishes only in a main-branch
GitHub Actions context. Actions uses `fetch-depth: 0` for notes generation.

Pull requests targeting `develop` run source validation and tests on Linux
PowerShell 7, Windows PowerShell 7 and Windows PowerShell 5.1. After these checks,
the Windows packaging job builds the CMD/ZIP and tests the actual CMD launch with
`-Version`, including a path containing spaces. PRs do not upload release artifacts
or publish releases. Pushes to `develop` run source validation only; pushes to
`main` also package and publish releases.

CI packages use exact Git blob bytes so Windows CRLF conversion cannot change
release assets or their checksums.

## Contribution rules

See [AGENTS.md](AGENTS.md). Write all new commit messages in English using
[Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/),
for example `fix(browser): preserve profile settings` or `ci: validate release packages`.
Run `./ci/check-commits` before pushing. It installs pinned development-only
commitlint tools with `npm ci` (Node.js 20+) and checks commits after the documented
adoption baseline, including explicit merges. Existing released history is retained.
CI checks all new commits on the pushed `main` or `develop` branch. For pull
requests, it checks branch commits instead of GitHub's synthetic merge commit.

GPU/game scans show file counts, logical bytes and elapsed time. Press Esc to
skip the current GPU/game target; skipped targets are excluded from cleanup.
The per-target limit defaults to 120 seconds; for a slow disk, use
`powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\WinCacheCleaner.ps1 -ScanTimeoutSeconds 600`.
Scanning reads metadata, not file contents. The timer/Esc check runs between
filesystem operations; it cannot interrupt a single blocked OS call. Ctrl+C
stops the scan, before any cleanup confirmation.

## Latest release

After a successful main-branch publication, the movable Git tag `latest` points
to the exact commit of `v<VERSION>`, and that GitHub release is marked Latest.
Version tags and existing assets stay immutable. Older-release reruns cannot
move the alias backwards; concurrent tag changes are protected by an exact
`--force-with-lease`. Failed publication does not promote the alias.
If the GitHub marker update fails after the tag push, rerunning repairs it.

Download the standalone launcher from the latest GitHub release:
[WinCacheCleaner.cmd](https://github.com/asirkov/WinCacheCleaner/releases/latest/download/WinCacheCleaner.cmd).
`latest` is a Git alias, not a separate release with duplicate assets.

## Codex workflow skills

[development](.agents/skills/development/SKILL.md) documents feature branches,
local checks and PRs into develop. [release](.agents/skills/release/SKILL.md) is
manual-only; invoke `$release 0.5.0` after this skill is merged and when ready
to start that release. It does not activate from release/version mentions.

The release script creates a version PR into develop for normal review, then
a release-branch PR into main with auto-merge, then a main-to-develop PR with
auto-merge. It checks actual merges, CI, publication, assets and latest promotion.

```bash
.agents/skills/release/scripts/release run 0.5.0
```

Repeat to resume. Exit 20 means a pending review, merge, CI or publication; other
nonzero statuses indicate a blocker. The script never overrides protection or
creates releases/tags outside Actions. GitHub API access and repository auto-merge
settings are prerequisites. All helper scripts are extensionless Bash files.
