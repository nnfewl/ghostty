# Twemoji builds of Ghostty

Automated builds of [Ghostty](https://github.com/ghostty-org/ghostty) with the
default Noto Color Emoji replaced by Twemoji.

This branch (`twemoji-pipeline`) is the default branch of this fork; it holds
only the CI pipeline. The actual patches live on:

- `twemoji-emoji` — Linux (Twemoji CBDT) + macOS (Twemoji Mozilla COLRv0)
- `twemoji-sbix`  — Linux (Twemoji CBDT) + macOS (Twemoji repacked as sbix)

Upstream Ghostty source is **never** modified here; CI extracts our patches
from those branches at build time and applies them on top of upstream
`main` and the latest stable `X.Y.x` branch.

## Where to download

GitHub Releases page: <https://github.com/nnfewl/ghostty/releases>

- **Latest stable** (recommended): the release flagged `[Latest]` —
  built from the highest `X.Y.x` upstream branch.
- **Latest main** (preview / unstable): the most recent `main-*` release —
  built from upstream `main` HEAD.

Stable always-latest URL (auto-redirects to the newest stable release):

```
https://github.com/nnfewl/ghostty/releases/latest/download/<filename>
```

…where `<filename>` is one of:

| File | Platform | Emoji variant |
|---|---|---|
| `ghostty-linux-x86_64.tar.gz` | Linux x86_64 | Twemoji CBDT |
| `ghostty-macos-arm64-colr.zip` | macOS arm64 | Twemoji Mozilla (vector COLRv0; small, sharp) |
| `ghostty-macos-arm64-sbix.zip` | macOS arm64 | Twemoji-as-sbix (bitmap; larger, ultra-compatible) |

## How the pipeline works

```
hourly cron
    │
    ▼
detect-upstream:
  • upstream main HEAD?       → main_sha
  • highest X.Y.x branch?     → stable_branch + stable_sha + stable_version
  • do releases already exist for these SHAs? → build_main / build_stable
    │
    ├─ build_main=true ─→ build 3 main artifacts ─→ release-main (pre-release)
    └─ build_stable=true ─→ build 3 stable artifacts ─→ release-stable (latest)
                                            │
                                            ▼
                                  cleanup (keep 5 newest per channel)
```

When upstream hasn't moved, `detect-upstream` short-circuits the whole matrix
and no builds run. No state files; the existence of a release tag _is_ the
state.

## Updating patches

Patches live on the dev branches as normal git commits. To update:

```sh
git fetch
git checkout twemoji-emoji          # or twemoji-sbix
# edit / commit / amend as needed
git push --force-with-lease
```

The next hourly pipeline run will see a fresh upstream SHA (or, if upstream
hasn't moved, you can manually re-trigger via the Actions tab) and rebuild
with the updated patches.

If `git am` fails because upstream has changed something our patches touch,
the corresponding build job will fail loudly with a clear error. Fix the
patches on the dev branch, force-push, then re-trigger.

## Manual rebuild

If you need to force a rebuild of an SHA that already has a release
(typically only useful when iterating on the pipeline itself):

1. Delete the existing release on GitHub.
2. Trigger the workflow via "Run workflow" in the Actions tab.

The pipeline will see "no release for this SHA" and rebuild.

## Pipeline files

| File | Purpose |
|---|---|
| `.github/workflows/release.yml` | Single workflow doing detect → build → release → cleanup |
| `scripts/detect-upstream.sh` | Reads upstream state and existing releases |
| `scripts/generate-patches.sh` | `git format-patch` from a dev branch's merge-base with `origin/main` |
| `scripts/cleanup-releases.sh` | Sliding-window release retention (5 per channel) |

## Why two macOS variants?

CoreText (macOS's font renderer) cannot render Google's CBDT bitmap format,
so the Linux Twemoji font won't work on macOS. Two replacements:

- **COLR (Twemoji Mozilla)**: vector emoji, ~2 MB; needs a small patch to
  `src/font/face/coretext.zig` to bypass an early-exit guard that assumes
  all color glyphs have non-empty GLYF entries.
- **sbix**: a third-party Twemoji repack into Apple Color Emoji's sbix
  format, ~23 MB after stripping unused strikes; works with zero changes
  to `coretext.zig` because sbix is CoreText's native color emoji format.

We publish both so users can pick — COLR for smaller binaries / sharper
glyphs at all sizes, sbix for maximum compatibility / no rendering patches.
