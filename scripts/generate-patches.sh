#!/usr/bin/env bash
# generate-patches.sh
#
# Extracts our Twemoji patch series from a dev branch (twemoji-emoji or
# twemoji-sbix) as a directory of .patch files. The patches are taken from
# the branch's merge-base with upstream main, so anything we added since
# branching off upstream is included.
#
# Usage:
#   generate-patches.sh <dev-branch> <output-dir>
#
# The caller is expected to have a checkout of our fork with both `main`
# and the dev branch fetched as remote-tracking refs (`origin/main`,
# `origin/twemoji-emoji`, `origin/twemoji-sbix`).

set -euo pipefail

DEV_BRANCH="${1:?dev branch required (twemoji-emoji | twemoji-sbix)}"
OUT_DIR="${2:?output directory required}"

mkdir -p "$OUT_DIR"

MERGE_BASE=$(git merge-base "origin/main" "origin/$DEV_BRANCH")
echo "merge-base with origin/main: $MERGE_BASE"
echo "tip of origin/$DEV_BRANCH:    $(git rev-parse "origin/$DEV_BRANCH")"

git format-patch \
  --output-directory "$OUT_DIR" \
  --no-signature \
  --binary \
  "$MERGE_BASE..origin/$DEV_BRANCH"

echo "generated patches:"
ls -1 "$OUT_DIR"
