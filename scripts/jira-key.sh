#!/usr/bin/env bash
# Deterministic Jira issue-key resolver for the QA skills.
# Extracts a Jira key (official format: 2+ uppercase letters, '-', digits) from,
# in priority order: the branch name -> the PR title (via gh) -> non-merge commit
# messages on the branch. Read-only: never writes to git, gh, or Jira. Output is
# meant to be read by the model instead of having it guess the ticket key.
#
# Usage: jira-key.sh <branch> [base]
#   <branch>  branch to inspect (required)
#   [base]    base branch for the commit-range scan (optional)
#
# Output:
#   key: <KEY|NONE>
#   source: <branch|pr|commit|none>
# Exit codes: 0 = key found, 3 = no key (NONE), 1 = usage/not-a-git-repo.
set -euo pipefail

branch="${1:?usage: jira-key.sh <branch> [base]}"
base="${2:-}"

# Official Jira key format: project key (2+ uppercase) + '-' + number.
KEY_RE='[A-Z][A-Z]+-[0-9]+'

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: not inside a git repository" >&2
  exit 1
}

first_key() { grep -oE "$KEY_RE" | head -n1; }

# 1. Branch name (canonical when present).
key="$(printf '%s' "$branch" | first_key || true)"
if [ -n "$key" ]; then
  echo "key: $key"; echo "source: branch"; exit 0
fi

# 2. PR title via gh, if installed and the branch has a PR.
if command -v gh >/dev/null 2>&1; then
  pr_title="$(gh pr view "$branch" --json title --jq .title 2>/dev/null || true)"
  key="$(printf '%s' "$pr_title" | first_key || true)"
  if [ -n "$key" ]; then
    echo "key: $key"; echo "source: pr"; exit 0
  fi
fi

# 3. Non-merge commit messages on the branch (scoped to base if known).
range="$branch"
if [ -n "$base" ] && git show-ref --verify --quiet "refs/remotes/origin/$base"; then
  range="origin/$base..$branch"
fi
commit_msgs="$(git log --no-merges --format='%s %b' "$range" 2>/dev/null || true)"
key="$(printf '%s' "$commit_msgs" | first_key || true)"
if [ -n "$key" ]; then
  echo "key: $key"; echo "source: commit"; exit 0
fi

echo "key: NONE"
echo "source: none"
echo "WARN: no Jira key (format ${KEY_RE}) in branch/PR/commits — ask the user or paste the ticket" >&2
exit 3
