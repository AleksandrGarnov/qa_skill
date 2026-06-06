#!/usr/bin/env bash
# Self-contained tests for branch-diff.sh — no external test framework.
# Builds a throwaway bare "origin" + working clone and asserts the script output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BD="$SCRIPT_DIR/branch-diff.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

# Build origin (bare) + a working clone whose default branch is $1 (default: main).
# Echoes the working-clone path.
setup() {
  local default="${1:-main}" root; root="$(mktemp -d)"
  git init -q --bare -b "$default" "$root/origin.git"
  git clone -q "$root/origin.git" "$root/work" 2>/dev/null
  git -C "$root/work" config user.email t@t.t
  git -C "$root/work" config user.name t
  git -C "$root/work" checkout -q -b "$default"
  printf 'base\n' > "$root/work/f.txt"
  git -C "$root/work" add .; git -C "$root/work" commit -q -m "init $default"
  git -C "$root/work" push -q -u origin "$default" 2>/dev/null
  git -C "$root/work" remote set-head origin "$default" 2>/dev/null
  printf '%s' "$root/work"
}

# --- Case 1: base auto-detected as main, head + changed files reported ---
w="$(setup main)"
git -C "$w" checkout -q -b feature
printf 'change\n' >> "$w/f.txt"; printf 'x\n' > "$w/new.txt"
git -C "$w" add .; git -C "$w" commit -q -m "feat: change"
git -C "$w" push -q -u origin feature 2>/dev/null
out="$(cd "$w" && "$BD" feature 2>/dev/null)"
assert_eq "auto-detect base = main" "yes" "$(echo "$out" | grep -q '^base: main' && echo yes || echo no)"
assert_eq "reports head_commit"     "yes" "$(echo "$out" | grep -q '^head_commit: [0-9a-f]\{40\}' && echo yes || echo no)"
assert_eq "lists changed file new.txt" "yes" "$(echo "$out" | grep -q 'new.txt' && echo yes || echo no)"

# --- Case 2: explicit base argument is honoured ---
out2="$(cd "$w" && "$BD" feature main 2>/dev/null)"
assert_eq "explicit base = main" "yes" "$(echo "$out2" | grep -q '^base: main' && echo yes || echo no)"

# --- Case 3: unknown branch -> exit 1 ---
( cd "$w" && "$BD" no-such-branch ) >/dev/null 2>&1
assert_eq "unknown branch -> exit 1" "1" "$?"

# --- Case 4: no resolvable base -> base UNKNOWN, exit 0 ---
# Default branch is 'trunk' (not main/master/develop) and origin/HEAD is removed.
w2="$(setup trunk)"
git -C "$w2" remote set-head origin -d 2>/dev/null || true
out3="$(cd "$w2" && "$BD" trunk 2>/dev/null)"
assert_eq "no base candidate -> UNKNOWN" "yes" "$(echo "$out3" | grep -q '^base: UNKNOWN' && echo yes || echo no)"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
