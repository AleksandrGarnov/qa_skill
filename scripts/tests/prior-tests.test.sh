#!/usr/bin/env bash
# Self-contained tests for prior-tests.sh — no external test framework.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PT="$SCRIPT_DIR/prior-tests.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

docs="$(mktemp -d)"
printf '# checklist\n' > "$docs/checklist-QA-9801-2026-06-01.md"   # filename match
printf 'see ticket QA-9801 for context\n' > "$docs/report-OTHER-2.md"  # content match
printf 'unrelated notes\n' > "$docs/random.md"                     # no match

out="$("$PT" "$docs" QA-9801 2>/dev/null)"
assert_eq "reports PRIOR-DOCS header" "yes" "$(printf '%s' "$out" | grep -q '^PRIOR-DOCS' && echo yes || echo no)"
assert_eq "finds filename match"      "yes" "$(printf '%s' "$out" | grep -q 'checklist-QA-9801' && echo yes || echo no)"
assert_eq "finds content match"       "yes" "$(printf '%s' "$out" | grep -q 'report-OTHER-2'   && echo yes || echo no)"
assert_eq "excludes non-match"        "no"  "$(printf '%s' "$out" | grep -q 'random.md'         && echo yes || echo no)"

# no match -> NONE
assert_eq "no prior doc -> NONE" "NONE" "$("$PT" "$docs" ZZ-0000 2>/dev/null)"

# missing docs dir -> DOCS-PATH-MISSING (not silently NONE)
miss_out="$("$PT" "$docs/nope-subdir" QA-9801 2>/dev/null)"
assert_eq "missing dir -> DOCS-PATH-MISSING" "yes" "$(printf '%s' "$miss_out" | grep -q '^DOCS-PATH-MISSING' && echo yes || echo no)"

# case-insensitive key match
assert_eq "case-insensitive key" "yes" "$("$PT" "$docs" qa-9801 2>/dev/null | grep -q 'checklist-QA-9801' && echo yes || echo no)"

rm -rf "$docs"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
