#!/usr/bin/env bash
# detect-upstream.sh
#
# Queries upstream ghostty-org/ghostty for the current state of the two
# channels we track (main + latest stable X.Y.x branch) and decides whether
# either needs a new build (based on whether a Release already exists for the
# current upstream SHA).
#
# Outputs are written to $GITHUB_OUTPUT in `key=value` form so downstream
# workflow jobs can consume them via `needs.detect-upstream.outputs.*`.
#
# Required env:
#   GH_TOKEN  - GitHub token with read access to upstream + write access to
#               our own fork's releases.

set -euo pipefail

UPSTREAM="ghostty-org/ghostty"

# --- main channel ----------------------------------------------------------
main_full_sha=$(gh api "repos/$UPSTREAM/commits/main" --jq .sha)
main_sha="${main_full_sha:0:7}"

# --- stable channel: highest X.Y.x branch ---------------------------------
stable_branch=$(
  gh api --paginate "repos/$UPSTREAM/branches" --jq '.[].name' \
    | grep -E '^[0-9]+\.[0-9]+\.x$' \
    | sort -V \
    | tail -1
)
if [[ -z "$stable_branch" ]]; then
  echo "ERROR: no X.Y.x branch found upstream" >&2
  exit 1
fi
stable_full_sha=$(gh api "repos/$UPSTREAM/branches/$stable_branch" --jq .commit.sha)
stable_sha="${stable_full_sha:0:7}"

# Latest semver tag reachable from the stable branch (e.g. v1.3.1 -> 1.3.1).
# We list all tags, keep those matching vX.Y.Z, sort, and pick the highest
# that is an ancestor of stable_full_sha.
stable_version=$(
  gh api --paginate "repos/$UPSTREAM/tags" --jq '.[] | select(.name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")) | .name' \
    | sed 's/^v//' \
    | sort -V \
    | tail -1
)
if [[ -z "$stable_version" ]]; then
  echo "ERROR: no vX.Y.Z tag found upstream" >&2
  exit 1
fi

# --- needs-build check: does a release with this SHA already exist? -------
release_exists() {
  local prefix="$1"
  local sha="$2"
  gh release list --limit 200 --json tagName --jq '.[].tagName' \
    | grep -E "^${prefix}-.*-${sha}$" \
    || true
}

# Extract the 7-char SHA from the most recent release tag for a channel.
last_built_sha() {
  local prefix="$1"
  gh release list --limit 200 --json tagName --jq '.[].tagName' \
    | grep -E "^${prefix}-" \
    | head -1 \
    | grep -oE '[a-f0-9]{7}$' \
    || true
}

# Paths that never affect the compiled binary.  If a commit touches ONLY
# files matching these patterns we skip the rebuild.
NON_CODE_PATTERNS=(
  # CI / GitHub infrastructure
  '^\.github/'
  '^\.agents/'
  # documentation & community files
  '^images/'
  '^example/'
  '^po/'
  '^dist/doxygen/'
  '[^/]*\.md$'
  '^LICENSE$'
  '^CODEOWNERS$'
  # dev tooling configs
  '^\.editorconfig$'
  '^\.shellcheckrc$'
  '^\.clang-format$'
  '^\.prettierignore$'
  '^\.gitattributes$'
  '^\.gitignore$'
  '^\.gitmodules$'
  '^\.envrc$'
  '^\.mailmap$'
  '^\.swiftlint\.yml$'
  # doc generation / analysis
  '^Doxyfile$'
  '^DoxygenLayout\.xml$'
  '^typos\.toml$'
  '^valgrind\.supp$'
)

# Returns 0 (true) if the diff between two SHAs contains code changes.
has_code_changes() {
  local prev_sha="$1"
  local curr_sha="$2"

  if [[ -z "$prev_sha" ]]; then
    return 0  # no previous build — always build
  fi

  local filter
  filter=$(printf '%s\n' "${NON_CODE_PATTERNS[@]}" | paste -sd'|' -)

  local code_files
  code_files=$(
    gh api "repos/$UPSTREAM/compare/${prev_sha}...${curr_sha}" \
      --jq '.files[].filename' 2>/dev/null \
    | grep -vE "$filter" \
    || true
  )

  if [[ -n "$code_files" ]]; then
    echo "  Code-affecting files changed:" >&2
    echo "$code_files" | head -20 | sed 's/^/    /' >&2
    return 0
  fi

  echo "  Only non-code files changed — skipping build" >&2
  return 1
}

if [[ -z "$(release_exists main "$main_sha")" ]]; then
  prev_main=$(last_built_sha main)
  if has_code_changes "$prev_main" "$main_full_sha"; then
    build_main=true
  else
    build_main=false
  fi
else
  build_main=false
fi

if [[ -z "$(release_exists stable "$stable_sha")" ]]; then
  prev_stable=$(last_built_sha stable)
  if has_code_changes "$prev_stable" "$stable_full_sha"; then
    build_stable=true
  else
    build_stable=false
  fi
else
  build_stable=false
fi

# --- emit outputs ----------------------------------------------------------
{
  echo "main_sha=$main_sha"
  echo "main_full_sha=$main_full_sha"
  echo "stable_branch=$stable_branch"
  echo "stable_sha=$stable_sha"
  echo "stable_full_sha=$stable_full_sha"
  echo "stable_version=$stable_version"
  echo "build_main=$build_main"
  echo "build_stable=$build_stable"
  echo "today=$(date -u +%Y-%m-%d)"
} | tee -a "${GITHUB_OUTPUT:-/dev/stdout}"
