# Changelog

[简体中文](CHANGELOG.md) | English

This file is the single source of truth for tack harness release notes:

- One section per release, heading format `## Vx.y.z (YYYY-MM-DD)`; entries are user-facing feature points tagged Added/Improved/Fixed instead of commit dumps
- `release.sh` verifies before releasing that the target tag has corresponding sections in both `CHANGELOG.md` (Chinese) and `CHANGELOG.en.md` (English); release aborts if either is missing
- CI extracts the corresponding sections from both changelogs and concatenates them as the bilingual GitHub Release body; the `check-update.sh` reminder and the `update` command's "What's new" view are sourced from both files

## V0.0.14 (Unreleased)

- Improved: Hook space/workspace resolution is now stateless and determined in real time from the cwd of each invocation; the `TACK_ROOT`/`TACK_WORK` path environment variables written by SessionStart via ENV_FILE were removed—session-level caches cannot express "which space/workspace does this call belong to" with multiple project windows or multiple parallel workspaces in one space, and cache validation only checked their own validity without checking containment of the cwd, so mismatches never triggered fallback. All three Hooks now probe upward from the payload cwd for the space root; a workspace is matched exactly when the cwd lies inside `space/<name>/` (parallel workspaces never interfere), and when the cwd is outside any workspace SessionStart/UserPromptSubmit fall back to the most recently active one with a confirmation prompt while PreToolUse leaves it blank and skips scanning; commands are assembled using the absolute paths in the injected text, and the two mode switches `TACK_HOOK_LOG`/`TACK_HOOK_ENFORCE` are unchanged
- Added: English README `README.en.md`—a complete English counterpart of the Chinese README with a language-switch link in both files; the install (`install.sh`), local skill upgrade (`skill-update.sh`), and space initialization (`init-tack.sh`) pipelines all distribute and materialize both READMEs
- Added: English triggers for the routes—26 commands and 5 workflows now carry corresponding English triggers in their front matter alongside the Chinese ones, so English input is routed directly (e.g. `requirement planning` → `spec`, `fix bug` → the bugfix workflow); both READMEs list the bilingual triggers
- Added: Bilingual changelog and release pipeline—new `CHANGELOG.en.md` mirrors the Chinese file entry for entry; `release.sh` gates releases on both changelogs containing the target version section; the CI Release body is assembled from both languages; `check-update.sh` and the `update` command fetch and show both Chinese and English "what's new" sections; `install.sh`/`skill-update.sh` distribution lists include both changelog files

## V0.0.13 (2026-10-03)

- Added: The `code-review` command (short `rv`, triggers "code review / review report")—using `plan.md`/`tech-design.md` as the spec and the three-dot diff against the target branch as facts, it analyzes changes function by function along "repository → file → function" (with code anchors), logic correctness, obvious bugs, and code-level hazards (security/performance/compatibility), and assesses affected interfaces and business scenarios, producing the standalone report `$work/code-review.md`; large cross-module changes can be delegated to the code-reviewer for three perspectives in parallel, and the `merge` gate may reuse the report's conclusions when the review baseline is identical
- Added: The `release-check` go-live checklist command (short `rc`, triggers "release check / go-live check")—item by item it identifies database changes (with executable migration and rollback statements, target environments and timing), config changes (with key/value example/environment templates), new outbound API calls (permissions and allowlists to request), and new middleware (resources to provision in advance), plus backstops such as scheduled jobs, credentials, canary rollout, and rollback plans, producing `$work/release-check.md` as an itemized checklist plus a suggested go-live order
- Added: The shared script `git-diff-context.sh`—resolves the target branch (local first, then origin/ fallback, auto-detects master/main), computes the merge-base, and exports the three-dot diff and its statistics, providing deterministic facts for review commands; E2E covers local-only / remote-only / no-diff / error paths
- Added: Unified Hook logging—with `TACK_HOOK_LOG=1`, every invocation of the three Hooks records the full payload: time, event, pid, cwd, environment variables, raw input payload, raw injection/interception output, exit code, and duration to `.tack/log/hook.log` (a mutex lock appends whole blocks serially so concurrent writes never interleave); when logging is off, Hook output is byte-for-byte unchanged
- Improved: `TACK_ROOT`/`TACK_WORK` are wired into actual consumption—the environment variables only act as a SessionStart cache, and before use the space marker, path containment, and workspace state (not completed) are validated, with automatic fallback to real-time probing when invalid; UserPromptSubmit/PreToolUse save repeated upward probes and full space scans

## V0.0.12 (2026-10-01)

- Improved: The `commit` command no longer asks for a second confirmation—issuing the command confirms the commit intent; the message is auto-generated (user argument first, otherwise derived from the actual diff and `current.task` in Conventional Commits style) and committed directly, with the commit hash, message, and changed file list reported afterward; remote-affecting operations such as `push` still require an explicit instruction
- Improved: The space-root `.gitignore` explicitly ignores `local/` directories at any level (`local/` → `**/local/`), covering sensitive-data directories at all locations such as `run/local/` and `space/*/local/`
- Improved: The `update` command merges the space-root `.gitignore`—new templates are diffed against the user's local file into added/modified/identical categories and follow the same add/overwrite/keep/merge flow as harness files; the `.tack/` entry is a mandatory framework fallback that must be appended even if the user chooses to keep their local `.gitignore`, preventing runtime data from entering the space repository

## V0.0.11 (2026-10-01)

- Added: Defect-origin tracing in the bugfix workflow—given a defective code line, `harness/script/git-bug-trace.sh` traces with one command the commit that introduced the defect, its time and author, the related requirement/ticket ID (`#123`/`MEEGO-456` etc.), the commit URL, and the MR URL that merged it into the main branch (GitHub/GitLab/Bitbucket supported); results are written to the `bug_origin` block of `status.yaml`, and the diagnosing reference `diagnosing-bugs.md` gains the corresponding stage
- Added: The `test` system-test command (turns test descriptions into an actionable `$work/test.md` plan) and the `run` script-execution command (a `run/` directory plus the `run.md` execution checklist, with sensitive data in gitignored `run/local/`)
- Added: An optional IDE Hook acceleration layer—`harness/script/hook/` provides SessionStart (preloads the route table and workspace snapshot, exports TACK_ROOT/TACK_WORK), UserPromptSubmit (zero-roundtrip `scan-routes resolve` injecting the cmd/workflow body), and PreToolUse (boundary observation: Git dual boundary / --force / --no-verify) events; observe mode with zero interception by default, `TACK_HOOK_LOG=1` probes calibrate real payloads, and `TACK_HOOK_ENFORCE=1` reserves the deny path
- Added: `install-hooks.sh` generates `.trae/hooks.json` and `.claude/settings.json` automatically during space initialization; they take effect only after manual enablement in the IDE under "Settings > Hooks"
- Improved: Workspace directories now use a date-prefix naming `space/<YYYYMMDD>-<branch>/` (e.g. `space/20261001-user-login/`), so sorting by name sorts by creation time; git branch names and work_id stay without the date prefix, `status.yaml` gains a `work_dir` field, `work.sh` prints `WORKSPACE`/`BRANCH` result lines at the end for callers to resolve actual paths, and the parameters of `git-worktree-helper.sh` and `check-guidance.sh` switch to the workspace directory name accordingly
- Improved: `testcode`/`test`/`run` are repositioned as **on-demand commands**—removed from the main development-chain stage mapping; they occupy no state and never block commit/push/merge/close, and the AI does not proactively ask about or guide to them after code completes; users trigger them directly when needed or use the testing workflow, and skipping them needs no marker; the `testcode_skipped` mechanism and field are deleted, while the capabilities and artifacts of all three commands are unchanged
- Improved: Framework runtime data is consolidated under `.tack/` (log logs / backup rollback backups / tmp temp files / state local state), never committed and safe to clean anytime
- Improved: Skill updates now overwrite `script/`, `template/`, `reference/`, and `workflow/` wholesale (`cmd/` is additive only; `rule/` and AGENTS.md are preserved), with temporary artifacts placed in the space backup dir and cleaned promptly
- Improved: Reliability of space-marker probing is fixed—`hook_grep_mark` uniformly uses `LC_ALL=C grep` byte matching to avoid unstable behavior of GNU grep with Chinese patterns under UTF-8 locales
- Fixed: The space-marker text in SKILL.md and the hook constants did not match the actual text in AGENTS.md (a missing space); synchronized to "This space is driven by the tack harness"

## V0.0.10 (2026-09-30)

- Added: Automatic update checks via check-update.sh—when the close / evolution / record / help commands finish, a new version is checked silently (7-day throttle; each version reminded at most once; never preempts the task at session start), and the reminder includes all release-note sections in the range from the local version to the latest
- Added: release.sh verifies the CHANGELOG section for the target version before releasing and aborts if it is missing; CI automatically extracts the corresponding section as the Release body when creating the release
- Added: Release conventions (root AGENTS.md)—before a release the AI scans the whole repository for new capabilities and merges them into the README without changing its structure, covering the script list, commands, workflows, and core features
- Added: The git fetch command automatically repairs the upstream association between a local branch and the same-named remote branch
- Fixed: The fetch upstream check now requires the same-named branch and automatically corrects a mismatched name

## V0.0.9 (2026-09-30)

- No functional changes (release process maintenance)

## V0.0.8 (2026-09-29)

- Fixed: The update command gains the local skill update step, closing the design gap where the version number was not updated after an update

## V0.0.7 (2026-09-29)

- No functional changes (release process maintenance)

## V0.0.6 (2026-09-29)

- No functional changes (release process maintenance)

## V0.0.5 (2026-09-29)

- Added: install.sh supports pipe installation (`curl | sh` one-line install without cloning, source downloaded automatically)
- Added: skill_version is automatically backfilled into the AGENTS.md project info block during space initialization

## V0.0.4 (2026-09-29)

- Improved: Updated documentation conventions and configuration; refined the wiki content definition

## V0.0.3 (2026-09-28)

- No functional changes (release process maintenance)

## V0.0.2 (2026-09-28)

- Added: The release.sh release script—automatically squashes unpushed commits, syncs the version number, creates the tag, and pushes
- Improved: Refactored the tack skill—workflow state machines, dependency-injection routing, and a self-evolution mechanism
- Added: Workflow constraints—no code changes during the req-context phase, develop preconditions, editing inside worktrees

## V0.0.1 (2026-08-28)

- Added: First version of the tack skill—programming workflow guidance, the harness skeleton, and the install script
- Added: GitHub Actions release workflow (pushing a tag automatically packages and publishes the release)
