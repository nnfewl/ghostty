#!/usr/bin/env bash
# rebase-dev-branches.sh
#
# Rebases the 4 dev branches onto their channel targets and force-pushes.
# Outputs success flags to $GITHUB_OUTPUT for downstream jobs.
# On failure: opens (or comments on) a GitHub Issue and continues.
#
# Usage:
#   rebase-dev-branches.sh <stable-version>
#
# Expects:
#   - upstream remote already added and fetched (main + stable branch)
#   - origin remote has the dev branches
#   - GH_TOKEN set for gh CLI (issue creation)
#   - GITHUB_OUTPUT set (CI) or defaults to stdout

set -euo pipefail

STABLE_TAG="v${1:?stable version required (e.g. 1.3.1)}"

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/stdout}"

BRANCHES=(
  "twemoji-emoji-stable:$STABLE_TAG"
  "twemoji-emoji-main:upstream/main"
  "twemoji-sbix-stable:$STABLE_TAG"
  "twemoji-sbix-main:upstream/main"
)

open_or_comment_issue() {
  local branch="$1"
  local target="$2"
  local details="$3"
  local title="Rebase failed: $branch onto $target"

  local body
  body=$(cat <<ISSUE_EOF
Automated rebase of \`$branch\` onto \`$target\` failed.

\`\`\`
$details
\`\`\`

**To fix:** resolve conflicts locally, force-push the branch, and re-run the workflow.
ISSUE_EOF
  )

  gh label create rebase-conflict --description "Automated rebase failed" --color D93F0B 2>/dev/null || true

  local existing
  existing=$(gh issue list --state open --search "in:title \"$title\"" --json number --jq '.[0].number' 2>/dev/null || true)

  if [[ -n "$existing" ]]; then
    echo "Commenting on existing issue #$existing"
    gh issue comment "$existing" --body "$body"
  else
    echo "Opening new issue: $title"
    gh issue create --title "$title" --body "$body" --label rebase-conflict
  fi
}

rebase_one() {
  local branch="$1"
  local target="$2"
  local flag_name
  flag_name=$(echo "$branch" | tr '-' '_' | sed 's/^twemoji_//')

  echo "=== Rebasing $branch onto $target ==="

  local current_base
  current_base=$(git merge-base "$target" "origin/$branch" 2>/dev/null || true)

  if [[ -z "$current_base" ]]; then
    echo "ERROR: no common ancestor between $target and origin/$branch"
    echo "${flag_name}_ok=false" >> "$OUTPUT_FILE"
    return
  fi

  local target_sha
  target_sha=$(git rev-parse "$target")

  if [[ "$current_base" == "$target_sha" ]]; then
    echo "$branch is already based on $target — no rebase needed"
    echo "${flag_name}_ok=true" >> "$OUTPUT_FILE"
    return
  fi

  git checkout -B "$branch" "origin/$branch"

  if git rebase --onto "$target" "$current_base" "$branch" 2>/tmp/rebase-err.log; then
    echo "$branch rebased successfully onto $target"
    git push origin "$branch" --force-with-lease
    echo "${flag_name}_ok=true" >> "$OUTPUT_FILE"
  else
    echo "ERROR: rebase of $branch onto $target failed"
    cat /tmp/rebase-err.log
    git rebase --abort 2>/dev/null || true

    local conflict_log
    conflict_log=$(cat /tmp/rebase-err.log 2>/dev/null || echo "(no details)")
    open_or_comment_issue "$branch" "$target" "$conflict_log"

    echo "${flag_name}_ok=false" >> "$OUTPUT_FILE"
  fi
}

git config user.email "twemoji-pipeline@local"
git config user.name  "twemoji-pipeline"

for entry in "${BRANCHES[@]}"; do
  branch="${entry%%:*}"
  target="${entry##*:}"
  rebase_one "$branch" "$target"
done
