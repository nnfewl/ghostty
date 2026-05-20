#!/usr/bin/env bash
# generate-patches.sh
#
# Extracts our Twemoji patch series from a dev branch as a directory of
# .patch files. The patches are taken from the branch's merge-base with
# the given base ref, so anything we added since branching off upstream
# is included.
#
# Usage:
#   generate-patches.sh <dev-branch> <base-ref> <output-dir>
#
# Examples:
#   generate-patches.sh twemoji-emoji-stable v1.3.1 /tmp/patches
#   generate-patches.sh twemoji-emoji-main   origin/main /tmp/patches

set -euo pipefail

DEV_BRANCH="${1:?dev branch required (e.g. twemoji-emoji-stable)}"
BASE_REF="${2:?base ref required (e.g. v1.3.1 or origin/main)}"
OUT_DIR="${3:?output directory required}"

mkdir -p "$OUT_DIR"

MERGE_BASE=$(git merge-base "$BASE_REF" "origin/$DEV_BRANCH")
echo "merge-base with $BASE_REF: $MERGE_BASE"
echo "tip of origin/$DEV_BRANCH: $(git rev-parse "origin/$DEV_BRANCH")"

git format-patch \
  --output-directory "$OUT_DIR" \
  --no-signature \
  --binary \
  "$MERGE_BASE..origin/$DEV_BRANCH"

echo "generated patches:"
ls -1 "$OUT_DIR"
