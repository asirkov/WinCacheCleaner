---
name: release
description: Manually orchestrate a version PR into develop, a release branch PR into main with auto-merge, and a main-to-develop sync PR with auto-merge.
---

## Manual invocation only

Use this skill only when the user explicitly invokes `$release` (or selects it
manually). `agents/openai.yaml` disables implicit invocation. A request to write
or edit this skill is not authorization to run it. Do not invoke it automatically
because changes were merged, a version was mentioned, or another skill suggests
releasing. Take the target version from the invocation or the user's explicit
session instructions; never invent a target. Example: `$release 0.5.0`.

Read `AGENTS.md` and the PR template. Use the existing checkout, not a worktree.
Do not stash/reset user work, rewrite history, move version tags, override branch
protection, auto-approve PRs, or use `--admin`. Respect existing authentication and
proxy routes; check GitHub API access separately from native Git. No credentials
in scripts, PRs, logs or chat.

## Authorized release flow

Use the bundled Bash script for all deterministic Git/GitHub/version/check steps:

```bash
.agents/skills/release/scripts/release run 0.5.0
```

The same command resumes the flow. Commands work from any directory. Dependencies:
Bash, Git, gh with repository API access, jq, sed, and the tools required by `ci/`.
Auto-merge and merge commits must be enabled in repository settings for the last
two PRs; the script reports missing settings instead of changing them.

1. **Compare the target with develop.** If `origin/develop:VERSION` equals the
   requested version, verify the script metadata agrees and skip the version PR,
   regardless of which PR prepared it. If develop is lower, use the version PR
   below; do not bump on the release branch. If develop is higher, stop rather
   than downgrade.
2. **Version PR into develop (only when develop is lower).** Create `chore/version-<VERSION>` from current
   `origin/develop`. Update `VERSION`, `$script:AppVersion`, and the script header
   together. Keep README unversioned; do not add, update or validate a
   current-version field there. Run repository validation, packaging and commitlint.
   Commit `chore(release): prepare version <VERSION>`, push and create/reuse a PR
   targeting `develop`, with the actual repository PR-template sections.
   This first PR is for normal review; do not enable its auto-merge automatically.
3. **Wait for version readiness and develop CI to succeed.** A queued PR or
   a run with no result is not a successful merge/check. When the version already
   matches, there is no version-PR review gate, but successful CI on the exact
   develop snapshot is still required. Do not cut a release early.
4. **Release PR.** Freeze `release-<VERSION>` at the validated develop commit.
   Open/reuse `release-<VERSION> -> main`, and request auto-merge using a merge
   commit and a Conventional Commit subject. Pin the PR head SHA. Never update an
   existing release branch silently or push change commits directly to main.
5. **Sync PR.** Only after the release PR actually merges, open/reuse
   `main -> develop`, and request auto-merge with a Conventional Commit merge
   subject and a pinned head SHA. This may run while main's publication job runs.
6. **Verify completion.** Confirm the sync merged, shared Git ancestry, successful
   main Actions on the release merge commit, the exact immutable version tag,
   published CMD/PS1/checksum/ZIP assets, the `latest` Git alias, and GitHub's Latest
   marker. Publication remains owned by `ci/release`/Actions; do not publish assets
   or create version/latest tags manually from this skill.

## Progress and recovery

`run` and each individual phase return **20** for an expected pending prerequisite
(version PR review, queued auto-merge, CI or publication). Report the PR URL and
pending stage; this is not a failed test. Exit **1** or another nonzero value is a
real blocker to investigate. Do not suppress failed checks or label pending work
complete. Individual commands: `prepare`, `promote`, `sync`, `verify`, `status`.

Continue after prerequisites arrive; reuse the same branches/PRs. Poll with brief
read-only status calls, yielding between them and updating the user at least every
60 seconds. Never use an unbounded blocking sleep. If a required manual review,
permission or disabled repository setting prevents further progress, finish
independent work and report the precise action needed. A failed API request does
not authorize bypassing networking or inventing credentials.

Only report a release complete when verification succeeds. Distinguish version
PR readiness, auto-merge requested, actual merges, successful Actions, publication,
latest promotion and develop synchronization. Do not infer later steps from an
earlier success.
