# Upstream bug: U+FE0F variation selector leaks as visible text

> **Scope:** this is a pre-existing bug in upstream Ghostty, not caused by
> the Twemoji patches in this fork. Reproduces identically in stock
> Ghostty. Documented here as a future TODO if I want to take a swing at
> fixing it and sending the patch upstream.

## Symptom

Some emoji render with a stray `<fe0f>` appearing immediately after them:

```
$ echo "🦀 😀 🚀 ❤️ ♻️ ⚠️ ☀️"
🦀 😀 🚀 ❤<fe0f> ♻<fe0f> ⚠<fe0f> ☀<fe0f>
```

The emoji glyph itself draws correctly — the variation selector just
isn't absorbed into the emoji cluster and leaks out as a separate cell.
Ghostty falls back to rendering an unknown-glyph placeholder, which it
draws as the codepoint name `<fe0f>`.

## Cause

Affected codepoints are BMP characters that have **both** a text and
emoji presentation and require **U+FE0F (variation selector-16)** to
force the emoji form. The sequence is two codepoints:

| Sequence | Meaning |
|---|---|
| U+2764 alone | ❤  text-presentation heart |
| U+2764 + U+FE0F | ❤️ emoji-presentation heart |

A correct shaper combines `U+2764 U+FE0F` into one cluster, looks up
the cluster in the emoji font, and emits one glyph. Ghostty's shaper
emits the emoji glyph for U+2764 but does not absorb the trailing
U+FE0F — it becomes a standalone cell with no glyph in any loaded
font, so the renderer prints `<fe0f>`.

Pure-emoji codepoints in the supplementary range (U+1F000+) like
🦀 (U+1F980), 🚀 (U+1F680), 😀 (U+1F600) are **not affected** because
they don't carry a variation selector — no VS to leak.

## Reproduction

Stock Ghostty + default NotoColorEmoji on Linux:

```
echo "❤️ ♻️ ⚠️ ☀️ ☁️ ✈️ ♟️ ⌚"
```

Affected characters (visible `<fe0f>` after the emoji):
- ❤️ U+2764 + U+FE0F (heart)
- ♻️ U+267B + U+FE0F (recycling)
- ⚠️ U+26A0 + U+FE0F (warning)
- ☀️ U+2600 + U+FE0F (sun)
- ☁️ U+2601 + U+FE0F (cloud)
- ✈️ U+2708 + U+FE0F (airplane)
- ♟️ U+265F + U+FE0F (chess pawn)

Unaffected (already emoji-default, no VS needed):
- ⌚ U+231A (watch)
- ⚡ U+26A1 (lightning)
- ⚽ U+26BD (soccer ball)
- ☕ U+2615 (coffee)

## Reference behavior

Same `echo` in GNOME Terminal (VTE + Pango) renders all of the above
with no `<fe0f>` leak. So the shaper logic in Pango / HarfBuzz **can**
handle this when given the right configuration. The bug is in how
Ghostty drives its shaper — most likely either:

1. The text-run segmentation is splitting U+FE0F into a separate run
   from the preceding BMP codepoint, so the shaper never sees the
   pair together; or
2. The cluster information from HarfBuzz is being discarded, so the
   shaper outputs one glyph for the base + one (missing) glyph for
   the VS instead of one glyph covering both codepoints.

## Where to look in Ghostty's source

Start points for investigation:

- `src/font/shaper/` — the shaper backends (HarfBuzz on Linux,
  CoreText on macOS). Look at how runs are built and how clusters
  are mapped back to cells.
- `src/terminal/cell.zig` (or wherever `Cell` lives) — how
  multi-codepoint clusters get stored. Variation selectors are
  zero-width and should attach to the preceding cell.
- `src/font/CodepointResolver.zig` — where codepoints get matched
  to fonts. If U+FE0F is being resolved separately (instead of as
  part of an emoji cluster), the resolver might be returning a "no
  font" result that triggers the `<fe0f>` placeholder.

The symptom on both Linux (HarfBuzz) and macOS (CoreText) suggests
the bug is **above** the shaper backend — in Ghostty's run
segmentation or cell-mapping logic — not in HarfBuzz / CoreText
themselves.

## Notes for a future fix

- Unicode Emoji TR51 defines the "emoji presentation sequence":
  `<emoji base> U+FE0F`. The grapheme cluster boundary should NOT
  split between these. Check that whatever Ghostty uses for cluster
  boundaries (ICU? a hand-rolled UAX#29 implementation?) treats
  these as one cluster.
- Consider also U+FE0E (text variation selector) for completeness;
  same kind of issue could arise in reverse (forcing text
  presentation on an emoji-default codepoint).
- A useful test corpus is the full emoji-presentation sequence list
  in <https://unicode.org/Public/emoji/latest/emoji-variation-sequences.txt>.

## Filing upstream

If/when this gets fixed, file at <https://github.com/ghostty-org/ghostty/issues>
with a minimal repro of `echo "❤️"` and the visible `<fe0f>` output,
plus a side-by-side screenshot vs. GNOME Terminal showing it rendered
correctly.
