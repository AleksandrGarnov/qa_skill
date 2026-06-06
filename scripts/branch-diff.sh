#!/usr/bin/env bash
# Deterministic branch/diff context for the QA skills.
# Fetches, checks out the target branch, resolves the base branch, and prints
# the diff stat + changed files. Read-only against history: never merges, pushes,
# rebases, or resets. Output is meant to be read by the model instead of having
# it run ad-hoc git commands and guess the base.
#
# Usage: branch-diff.sh <branch> [base]
#   <branch>  branch to test (required)
#   [base]    base branch to diff against (optional; auto-detected if omitted)
set -euo pipefail

branch="${1:?usage: branch-diff.sh <branch> [base]}"
base="${2:-}"

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: not inside a git repository" >&2
  exit 1
}

git fetch --quiet --all --prune

# Verify the branch exists (locally or on origin) before switching.
if ! git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null \
   && ! git rev-parse --verify --quiet "refs/remotes/origin/$branch" >/dev/null; then
  echo "ERROR: branch '$branch' not found locally or on origin" >&2
  exit 1
fi

git checkout --quiet "$branch"
git pull --quiet --ff-only 2>/dev/null || true

# Auto-detect base only if not given: origin/HEAD, then common names.
if [ -z "$base" ]; then
  for cand in \
    "$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')" \
    develop main master; do
    [ -n "$cand" ] || continue
    if git show-ref --verify --quiet "refs/remotes/origin/$cand"; then
      base="$cand"
      break
    fi
  done
fi

echo "branch: $branch"
echo "head: $(git log -1 --oneline)"
echo "head_commit: $(git rev-parse HEAD)"

if [ -z "$base" ]; then
  echo "base: UNKNOWN"
  echo "WARN: could not auto-detect base branch — ask the user / read CLAUDE.md" >&2
  exit 0
fi

echo "base: $base"
echo "--- diff stat vs origin/$base ---"
git diff --stat "origin/$base...HEAD"
echo "--- changed files ---"
git diff --name-only "origin/$base...HEAD"
