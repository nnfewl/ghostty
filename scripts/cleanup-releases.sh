#!/usr/bin/env bash
# cleanup-releases.sh
#
# Keeps a sliding window of the N most recent releases per channel.
# Older releases (and their git tags) are deleted.
#
# Usage:
#   cleanup-releases.sh [keep_count]
#
# Channels: 'main', 'stable'. Default keep_count = 5.
#
# Required env:
#   GH_TOKEN  - GitHub token with write access to fork releases.

set -euo pipefail

KEEP="${1:-5}"
CHANNELS=(main stable)

for prefix in "${CHANNELS[@]}"; do
  echo "=== channel: $prefix (keep $KEEP) ==="

  # gh release list sorts by createdAt descending by default. We filter to
  # this channel's tag prefix and skip the first $KEEP entries.
  victims=$(
    gh release list --limit 200 --json tagName,createdAt \
      --jq '.[] | select(.tagName | startswith("'"$prefix"'-")) | .tagName' \
      | tail -n +"$((KEEP + 1))"
  )

  if [[ -z "$victims" ]]; then
    echo "  nothing to delete"
    continue
  fi

  while IFS= read -r tag; do
    echo "  deleting $tag"
    gh release delete "$tag" --yes --cleanup-tag
  done <<< "$victims"
done

echo "cleanup complete"
