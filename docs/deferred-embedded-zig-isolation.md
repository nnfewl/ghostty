# Deferred: move Twemoji definitions out of `embedded.zig`

> **Status:** assessed 2026-09-23, **deferred** — not worth doing yet.
> Revisit if any trigger under [When to revisit](#when-to-revisit) fires.

## Background: why patch shape matters

The dev branches (`twemoji-{emoji,sbix}-{main,stable}`) are rebased onto
upstream every night by `scripts/rebase-dev-branches.sh`. A rebase fails
whenever a commit in our stack collides with something upstream changed,
and each failure stops that channel's builds until someone resolves it by
hand. Two such outages so far:

| When | Upstream change | What our stack did | Cost |
|---|---|---|---|
| 2026-08-09 | `afc79b8cc` added a fast-path inside the `apple_emoji:` block in `SharedGridSet.zig` | **deleted** that whole block | ~10 days of no main builds |
| 2026-08-27 | `28b5bf905` updated `res/NotoColorEmoji.ttf` | **overwrote** the binary, then restored it 9 commits later (net zero) | ~26 days of no main builds |

Both were fixed by reshaping the patch rather than just resolving the
conflict:

- The `SharedGridSet.zig` change now **inserts** a Twemoji block ahead of
  upstream's Apple Color Emoji discovery instead of deleting it. Fallback
  order is priority order (`Collection.getIndex` returns the first face
  with the codepoint), so inserting earlier is enough to win.
- No commit touches `NotoColorEmoji.ttf` any more.

The lesson: **insertions rebase cleanly almost always; modifications to
upstream lines are what conflict.**

## The one remaining modification

After those fixes, every hunk in the stack is a pure insertion except one
line in `src/font/embedded.zig`:

```diff
-pub const emoji = @embedFile("res/NotoColorEmoji.ttf");
+pub const emoji = @embedFile("res/TwemojiCBDT.ttf");
+pub const emoji_macos = @embedFile("res/TwemojiMozilla.ttf");
```

Redefining `emoji` is how Linux gets Twemoji: upstream's own Linux
fallback in `SharedGridSet.zig` loads `font.embedded.emoji`, so no
`SharedGridSet.zig` change is needed on Linux at all.

### Upstream exposure (measured 2026-09-23)

| File | Upstream commits, prior 12 months | Our change | Shape |
|---|---|---|---|
| `src/font/embedded.zig` | 1 | +8 −1 | **modifies an upstream line** |
| `src/font/SharedGridSet.zig` | 6 | +41 −0 | insertion |
| `src/font/face/coretext.zig` | 10 | +36 −0 | insertion |
| `.gitignore` (sbix only) | 8 | +1 −0 | insertion |

To re-measure, from a checkout with `upstream` and the fork's branches
fetched:

```sh
for f in src/font/embedded.zig src/font/SharedGridSet.zig \
         src/font/face/coretext.zig .gitignore; do
  printf '%-28s %s commits/12mo\n' "$f" \
    "$(git log --since='12 months ago' --oneline upstream/main -- "$f" | wc -l)"
done
```

## The option considered

1. Add `src/font/twemoji.zig` (ours alone) holding the Twemoji
   `@embedFile` constants.
2. Revert `embedded.zig` to upstream verbatim — `emoji` is Noto again.
3. Make the existing inserted block in `SharedGridSet.zig` run on all
   platforms (it is currently `isDarwin`-only), importing `twemoji.zig`
   directly so no other upstream file (e.g. `font/main.zig`) is touched.
4. Rewrite all four dev branches and force-push, as in the earlier fixes.

**Pros**

- The stack becomes insertion-only: no upstream line modified anywhere.
- The seven upstream tests that load `font.embedded.emoji` (in
  `CodepointResolver.zig`, `Collection.zig`, `face/freetype.zig`,
  `shaper/coretext.zig`, `shaper/harfbuzz.zig`) would exercise real Noto
  again. Today they silently run against Twemoji.
- Linux would fall back to Noto for codepoints Twemoji lacks instead of
  showing tofu — the same trade-off macOS already makes with Apple Color
  Emoji.

**Cons**

- **The Linux binary grows by ~10.7 MB.** `@embedFile` is only evaluated
  when referenced; today nothing references Noto on Linux so it is left
  out. After the change upstream's fallback references it again, so both
  fonts ship. (`NotoColorEmoji.ttf` 10,673,480 B vs `TwemojiCBDT.ttf`
  3,857,500 B; the Linux tarball was ~14 MB.) Bitmap font data compresses
  poorly, so most of that lands in the download.
- Linux Twemoji would then depend on `SharedGridSet.zig` (6 upstream
  commits/yr) rather than `embedded.zig` (1/yr). The change there is an
  insertion so conflicts stay unlikely, but the file churns more.
- Linux behaviour changes: Noto becomes a lower-priority fallback where
  today it is absent.
- Another rewrite and force-push of all four dev branches.

## Decision

Deferred. The size cost is permanent and paid on every Linux download;
the benefit guards against a conflict that is both rare (one upstream
commit to the file in a year) and cheap — a one-line text conflict, not a
deleted block or a binary like the two real outages.

## When to revisit

Reconsider if any of these become true:

- Upstream starts editing `embedded.zig` more often, or edits the `emoji`
  line itself (rerun the measurement above).
- We want upstream's test suite to run meaningfully on the fork (the
  inherited `Test` workflow currently never completes here).
- Linux coverage gaps show up — emoji Twemoji lacks rendering as tofu.
- Linux binary size stops mattering, or upstream shrinks/replaces Noto.

If a conflict does hit this line in the meantime, resolve it by keeping
upstream's surrounding changes and re-pointing `emoji` at
`res/TwemojiCBDT.ttf` with `emoji_macos` below it.
