---
name: development
description: Follow the WinCacheCleaner development workflow for features, fixes, documentation and CI changes, including checks and a pull request into develop.
---

Read the repository's `AGENTS.md` and `.github/pull_request_template.md` first.
Use the existing isolated checkout; do not create a Git worktree unless requested.
Preserve user changes and existing authentication. Never print secrets or replace
injected Git/proxy credentials. Native Git access does not prove GitHub API access.

## Development pipeline

1. Inspect status and fetch the current `develop`. Start each change in a separate
   branch based on `origin/develop`; never push change commits to main/develop.
   Use `scripts/develop start feat/<name>` (or fix/docs/ci/chore prefix).
2. Implement the requested scope and inspect the diff. Keep PowerShell 5.1+
   compatibility, safe cache paths, previews, Y/N confirmation, read-only analysis
   and protected user data. Do not run real cleanup as a development check.
3. Run `scripts/develop validate`. For packaging/release changes, add `--package`.
   These commands reuse `ci/validate`, `ci/check-commits`, `ci/build` and
   `ci/test-package`. Use `actionlint` for Actions changes when available.
4. Commit in English using Conventional Commits 1.0.0. Rerun commitlint after
   committing. Use honest test results; Linux does not validate Windows CMD,
   PowerShell 5.1, registry/AppX or Windows locking.
5. Fill the repository PR template in English. Mark `[x]` only for completed
   operations; leave pending/manual items `[ ]`, and explain N/A items.
6. Call `scripts/develop pr '<conventional title>' /path/to/body.md` to push the
   feature branch and open/reuse a PR targeting `develop`. Do not merge a feature
   PR unless the user has authorized that action. Report the PR link and checks.

Actions starts on pushes to `main`/`develop` and pull requests targeting `develop`.
PRs run validation and build/test Windows packages without uploading release
artifacts or publishing. Develop pushes run validation; main pushes also package
Windows assets, create/update versioned releases and promote `latest`. Feature
and release branch pushes and manual Actions triggers do not start Actions.

## Release boundary

Do not start a release as a side effect of development, a version mentioned in
conversation, or a merged PR. The `$release` skill is manual-only. The user invokes
it explicitly after changes are merged into develop. Its version PR, release PR
and main-to-develop sync are separate from this development PR.
