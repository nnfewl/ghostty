# Patch Pipeline Rebase Design

**Date:** 2026-05-20
**Status:** Draft

## Problem

The current patch pipeline generates patches from dev branches based on `origin/main` and applies them to both main and stable upstream targets. This means:

1. Stable and main builds produce nearly identical binaries — the two channels are meaningless.
2. Patches carry context lines from main's lineage but are applied to the stable branch (a different lineage), risking silent offset application or hard failures.
3. `generate-patches.sh` hardcodes `origin/main` as the merge-base ref.
4. No automation detects stale patches, failed rebases, or silent offset application.

## Design

### Branch Structure

Replace the current 2 dev branches with 4 channel-specific branches:

| Branch | Based on | Used by |
|---|---|---|
| `twemoji-emoji-stable` | latest stable tag (e.g. `v1.3.1`) | stable Linux + macOS COLR builds |
| `twemoji-emoji-main` | upstream main HEAD | main Linux + macOS COLR builds |
| `twemoji-sbix-stable` | latest stable tag | stable macOS sbix builds |
| `twemoji-sbix-main` | upstream main HEAD | main macOS sbix builds |

The old `twemoji-emoji` and `twemoji-sbix` branches become the initial source for the stable variants (rebased onto the latest stable tag). The main variants are created by rebasing the same commits onto main HEAD.

The `twemoji-emoji-rebased` and `twemoji-sbix-rebased` branches are deleted — superseded by this naming scheme.

### New Job: `rebase-dev-branches`

Runs after `detect-upstream`, before all build jobs. All build jobs depend on it.

**Steps:**

1. Checkout fork with full history (`fetch-depth: 0`).
2. Add upstream remote, fetch main + stable branch.
3. Read the latest stable tag from `detect-upstream` outputs (`stable_version` — the highest `vX.Y.Z` semver tag upstream, as resolved by `detect-upstream.sh`).
4. For each of the 4 dev branches, rebase onto its target:
   - `twemoji-emoji-stable` and `twemoji-sbix-stable`: `git rebase --onto v<stable_version> <current-base> origin/<branch>`
   - `twemoji-emoji-main` and `twemoji-sbix-main`: `git rebase --onto upstream/main <current-base> origin/<branch>`
5. Force-push all successfully rebased branches with `--force-with-lease`.
6. If any rebase fails:
   - Abort the rebase (`git rebase --abort`).
   - Open a GitHub Issue (or comment on an existing one — dedup by title).
   - Continue with remaining branches.
7. Output success flags per branch: `emoji_stable_ok`, `emoji_main_ok`, `sbix_stable_ok`, `sbix_main_ok`.

**Determining `<current-base>`:** The merge-base between the dev branch and its previous target ref. After the first rebase cycle, the base of each branch IS the target ref, so subsequent rebases are `--onto <new-target> <old-target> <branch>`. The old target is discoverable as the merge-base between the dev branch and the previous stable tag or main ref.

### Updated `generate-patches.sh`

**New signature:**

```
generate-patches.sh <dev-branch> <base-ref> <output-dir>
```

The merge-base computation changes from:

```bash
MERGE_BASE=$(git merge-base "origin/main" "origin/$DEV_BRANCH")
```

to:

```bash
MERGE_BASE=$(git merge-base "$BASE_REF" "origin/$DEV_BRANCH")
```

Since dev branches are freshly rebased onto their target, the merge-base equals the target ref. Patches have context lines from the exact code they'll be applied to.

### Build Job Changes

**Stable builds** (linux-stable, macos-colr-stable, macos-sbix-stable):

- Add dependency: `needs: [detect-upstream, rebase-dev-branches]`
- Add condition: `rebase-dev-branches.outputs.emoji_stable_ok == 'true'` (or `sbix_stable_ok` for sbix jobs)
- Worktree target: `stable_full_sha` (unchanged)
- Patch generation: `generate-patches.sh twemoji-emoji-stable v<stable_version> /tmp/patches`

**Main builds** (linux-main, macos-colr-main, macos-sbix-main):

- Add dependency: `needs: [detect-upstream, rebase-dev-branches]`
- Add condition: `rebase-dev-branches.outputs.emoji_main_ok == 'true'`
- Worktree target: `main_full_sha` (unchanged)
- Patch generation: `generate-patches.sh twemoji-emoji-main origin/main /tmp/patches`

**Patch application safety:** Change `git am` to `git am --3way` in all build jobs. This makes conflicts a hard failure instead of allowing silent offset application.

### GitHub Issue on Rebase Failure

**Title:** `Rebase failed: <branch> onto <target-ref>`

**Body:** The branch that failed, the target ref, and the conflict output from `git rebase`.

**Dedup:** Before creating, search for an open issue with the same title using `gh issue list --search`. If found, add a comment instead of creating a duplicate.

**Labels:** `rebase-conflict` (auto-created if it doesn't exist).

### Unchanged

- `sync-fork` job: still mirrors upstream branches (main + stable X.Y.x). Unrelated to dev branches.
- `detect-upstream.sh`: no changes needed. Already outputs `stable_version`.
- `cleanup-releases.sh`: no changes.
- Release jobs: no changes beyond updated `needs` dependencies.

## Migration

1. Create the 4 new dev branches by rebasing existing `twemoji-emoji` and `twemoji-sbix` onto `v1.3.1` (stable) and current main HEAD (main).
2. Push the new branches.
3. Update `generate-patches.sh` and `release.yml`.
4. Delete old branches: `twemoji-emoji`, `twemoji-sbix`, `twemoji-emoji-rebased`, `twemoji-sbix-rebased`.
5. Verify by running the workflow manually via `workflow_dispatch`.
