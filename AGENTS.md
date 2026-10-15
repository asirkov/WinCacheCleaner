# Working on WinCacheCleaner

## Repository and branches

Use the existing checkout. Cloud tasks are isolated; do not create Git worktrees
unless the user explicitly requests one. Every feature, fix, documentation or CI
change must start on a separate branch based on `develop` and enter `develop`
through a pull request. Never push change commits directly to `develop` or `main`.
Open feature PRs with `develop` as the base; use an English Conventional Commit
title and describe behavior and validation. For an authorized release, promote
in this order, using the manually invoked `$release` skill:
version-bump PR -> `develop`, then `release-<VERSION>` -> PR into `main`
(auto-merge), then `main` -> PR into `develop` (auto-merge). The version PR uses
normal review; do not auto-merge it unless the user separately requests that.
Use merge commits and Conventional Commit subjects for release/sync ancestry.
Never start the release skill implicitly or merely because a version is mentioned.
Actions may start only for pushes to `main` and `develop`: no release-branch,
pull request or workflow_dispatch triggers. Never build or publish releases
automatically from `develop`.
Preserve unrelated user changes. Do not rewrite published history without an
explicit user request; use exact `--force-with-lease` expectations when authorized.

## Commit messages

Every new commit must follow [Conventional Commits 1.0.0](https://www.conventionalcommits.org/en/v1.0.0/).
Write the subject, body and footers in English. Release-note headings and link labels must also be in English. Use this format:

```text
<type>[optional scope][!]: <short description>

[optional body]

[optional footers]
```

Use lowercase types: `feat`, `fix`, `docs`, `style`, `refactor`, `perf`, `test`,
`build`, `ci`, `chore`, or `revert`. Use `feat` for new functionality and `fix` for
bug fixes. A scope is optional; useful scopes include `browser`, `cleanup`, `ci`,
`release`, and `tests`. Keep the header at most 100 characters, without a trailing
period. Separate the body and footers with blank lines. Mark incompatible changes
with `!` before `:` or an uppercase `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer.
Examples:

```text
fix(release): accept binary SHA256 checksum markers
ci: use English workflow run titles
docs: explain analysis-only mode
feat(browser)!: require explicit profile selection
```

Prefer fast-forward or squash integration. Squash titles and any explicit merge
commits must also use Conventional Commits; do not use Git's default merge title.
Existing history through `16a7da26b3c2d67eb150634f0b6758fb5241b9c3` predates this
rule and is the CI baseline. All subsequent commits are checked, including merge
commits. Do not move the baseline to bypass a failure. Release notes come from Git
subjects, so describe the concrete change; do not add a separate changelog.

## Pull requests

Use `.github/pull_request_template.md` for PR descriptions. Fill in the summary,
breaking changes, documentation changes, and manual changes sections; write
`None` where there are no relevant changes. Mark manual-operation checkboxes
`[x]` only for steps the agent has already completed in the current PR. Leave
`[ ]` for incomplete work, steps requiring manual action, or work deferred to
future features, and describe what remains. For inapplicable checklist items,
leave `[ ]` and append `N/A` with a short reason instead of marking them complete.

## Implementation and safety

The application supports Windows PowerShell 5.1+ and has no runtime dependencies.
Keep PowerShell 5.1 compatibility. CI entry points belong in root `ci/`, are Bash
scripts with no `.sh` extension, use LF endings, and must propagate failures.
Actions YAML should call those scripts. Keep workflow, job, step and run titles
in English.

Data safety takes priority. Never delete entire unknown app/profile folders based
on name matching, age or size. Use narrow known cache paths, skip reparse points,
protect cookies/settings/saves, and preserve previews and explicit confirmations.
`-AnalyzeOnly` must not delete files or write reports. Test cleanup only against
isolated temporary fixtures. Never run real Windows cleanup as a CI/setup check.

## Validation

Use Bash / Git Bash. PowerShell 7 is selected by default; set
`POWERSHELL=powershell.exe` on Windows to check PowerShell 5.1. Node.js 20+ and npm
are development tools used for pinned commitlint dependencies, not app runtime
requirements.

```bash
./ci/check-commits
./ci/validate
```

For changes to packaging, release notes or release validation, also run:

```bash
./ci/build
./ci/test-package
```

Inspect the diff and repository status. Validate Actions changes with `actionlint`
when available. Preserve meaningful assertions, checksums and failure exit codes.
Report checks that passed, failed or could not run; Linux does not validate real
Windows CMD startup, PowerShell 5.1, registry/AppX or file-locking behavior.

## Releases

Keep `VERSION`, `$script:AppVersion`, and the script header aligned. Use semantic
versions: fixes increment PATCH, features MINOR, incompatible changes MAJOR.
Do not bump a version just to edit documentation or rerun an existing workflow.
Main-only packaging validates real CMD startup on Windows before publishing.
Keep full Git history and tags for release notes. Never move versioned release tags or replace their assets. Release descriptions may be corrected using the tagged commit, excluding
later branch changes. A successful local build or push does not prove Actions or publication
completed.

## Latest tag

After successful main publication, promote the movable `latest` alias to the
version tag's exact commit and mark that GitHub release Latest. Use an exact
remote-object lease; never force blindly. An older rerun must not roll latest
backwards. Keep versioned tags and assets immutable. Test against local bare Git
repositories and a mocked GitHub CLI; never mutate real release metadata in tests.

## Repository Codex skills

- `.agents/skills/development/SKILL.md` describes the development and feature-PR flow.
- `.agents/skills/release/SKILL.md` is manual-only (`allow_implicit_invocation: false`).
  The user explicitly invokes `$release <version>` after the skill's PR is merged.
  Its bundled script owns deterministic version/branch/PR/auto-merge/verification
  steps; call it rather than improvising release commands. Editing/installing
  release skills does not authorize executing the release flow.
