#!/usr/bin/env bash
# Self-contained tests for jira-key.sh — no external test framework.
# Builds throwaway git repos in temp dirs and asserts the resolver output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JIRA_KEY="$SCRIPT_DIR/jira-key.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

new_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  git -C "$dir" commit -q --allow-empty -m "init"
  printf '%s' "$dir"
}

run_key() { ( cd "$1" && "$JIRA_KEY" "$2" "${3:-}" 2>/dev/null | sed -n 's/^key: //p' ); }
run_src() { ( cd "$1" && "$JIRA_KEY" "$2" "${3:-}" 2>/dev/null | sed -n 's/^source: //p' ); }

# Case 1: key in branch name -> source branch (canonical)
r="$(new_repo)"; git -C "$r" checkout -q -b feature/PROJ-123-add-login
assert_eq "key from branch name" "PROJ-123" "$(run_key "$r" feature/PROJ-123-add-login)"
assert_eq "source is branch"     "branch"   "$(run_src "$r" feature/PROJ-123-add-login)"

# Case 2: no key in branch, key in a non-merge commit -> source commit
r="$(new_repo)"; git -C "$r" checkout -q -b plain-branch
git -C "$r" commit -q --allow-empty -m "fix bug ABC-9 in parser"
assert_eq "key from commit msg"  "ABC-9"  "$(run_key "$r" plain-branch)"
assert_eq "source is commit"     "commit" "$(run_src "$r" plain-branch)"

# Case 3: nothing anywhere -> NONE
r="$(new_repo)"; git -C "$r" checkout -q -b nothing-here
git -C "$r" commit -q --allow-empty -m "no ticket here"
assert_eq "no key -> NONE"        "NONE" "$(run_key "$r" nothing-here)"
assert_eq "no key -> source none" "none" "$(run_src "$r" nothing-here)"

# Case 4: lowercase / single-letter prefix must NOT match (format discipline)
r="$(new_repo)"; git -C "$r" checkout -q -b proj-5-lower
assert_eq "lowercase not a key -> NONE" "NONE" "$(run_key "$r" proj-5-lower)"

# Case 5: key in BOTH branch and commit -> branch wins (documented precedence)
r="$(new_repo)"; git -C "$r" checkout -q -b feature/PROJ-1-thing
git -C "$r" commit -q --allow-empty -m "fix also relates to OTHER-2"
assert_eq "branch beats commit (key)"    "PROJ-1" "$(run_key "$r" feature/PROJ-1-thing)"
assert_eq "branch beats commit (source)" "branch" "$(run_src "$r" feature/PROJ-1-thing)"

# Case 6: multi-letter project prefix and long number still match
r="$(new_repo)"; git -C "$r" checkout -q -b bugfix/ABCD-12345
assert_eq "long prefix+number" "ABCD-12345" "$(run_key "$r" bugfix/ABCD-12345)"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
