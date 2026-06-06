#!/usr/bin/env bash
# Self-contained tests for learned-checks.sh (the feedback-loop store).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LC="$SCRIPT_DIR/learned-checks.sh"
pass=0; fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
tmp="$(mktemp -d)"; f="$tmp/learned.md"

# list on a missing file -> NONE
assert_eq "list missing -> NONE" "NONE" "$("$LC" list "$f")"

# add #1 -> creates file, reports #1
out="$("$LC" add "$f" "wallet/balance" "concurrent debit in the window doesn't double-count" "QA-8771 balance drift escaped GO" 2026-06-05)"
assert_eq "add #1 -> reports #1" "LEARNED-CHECK-ADDED: #1 (wallet/balance)" "$out"
assert_eq "file created" "0" "$([ -f "$f" ]; echo $?)"

# list -> exactly one data row
assert_eq "list after 1 add -> 1 row" "1" "$("$LC" list "$f" | grep -c '^|')"

# add #2 -> increments
out2="$("$LC" add "$f" "payout" "verifyCode is actually checked, not auto-approved" "B2 never run" 2026-06-05)"
assert_eq "add #2 -> reports #2" "LEARNED-CHECK-ADDED: #2 (payout)" "$out2"
assert_eq "list after 2 adds -> 2 rows" "2" "$("$LC" list "$f" | grep -c '^|')"

# match by component keyword -> finds the wallet row, not the payout row
assert_eq "match 'wallet' -> 1 row" "1" "$("$LC" match "$f" wallet | grep -c '^|')"
# match by a word in the check text
assert_eq "match 'verifyCode' (in check) -> 1 row" "1" "$("$LC" match "$f" verifyCode | grep -c '^|')"
# match multiple keywords (OR)
assert_eq "match wallet|payout -> 2 rows" "2" "$("$LC" match "$f" wallet payout | grep -c '^|')"
# match a keyword that hits nothing -> NONE
assert_eq "match 'nonexistent' -> NONE" "NONE" "$("$LC" match "$f" nonexistent)"

# a check containing a pipe is sanitized (stays one valid row) and still matches
"$LC" add "$f" "search" "query a|b|c returns rows" "i18n escape bug" 2026-06-05 >/dev/null
assert_eq "pipe-containing check stays 1 row" "3" "$("$LC" list "$f" | grep -c '^|')"
assert_eq "match the sanitized row" "1" "$("$LC" match "$f" "i18n" | grep -c '^|')"

# --- scan (backfill from existing reports) ---
docs="$tmp/docs"; mkdir -p "$docs"
cat > "$docs/QA-100-report.md" <<'MD'
# Test Report
## Found bugs
### QA-100-BUG-01 — [Payments] balance double-counted under concurrency
### QA-100-BUG-02 — [Payments] payout approved without code
## Verdict
NO-GO
MD
cat > "$docs/QA-200-report.md" <<'MD'
# Test Report
## Found bugs
### QA-200-BUG-01 — [Search] unicode query returns 500
## Verdict
NO-GO
MD
cat > "$docs/QA-300-report.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | smoke | x | pass | observed-data | R1 | ok |
## Verdict
GO
MD
assert_eq "scan -> 3 bug candidates across reports" "3" "$("$LC" scan "$docs" | grep -c '	')"
assert_eq "scan finds the concurrency bug" "1" "$("$LC" scan "$docs" | grep -c 'double-counted')"

# scan an empty dir -> NONE
mkdir -p "$tmp/empty"
assert_eq "scan empty dir -> NONE" "NONE" "$("$LC" scan "$tmp/empty")"
# scan a missing dir -> exit 1
"$LC" scan "$tmp/nope-dir" >/dev/null 2>&1; assert_eq "scan missing dir -> exit 1" "1" "$?"

# usage errors -> exit 2
"$LC" add "$f" "only-component" >/dev/null 2>&1; assert_eq "add missing args -> exit 2" "2" "$?"
"$LC" bogus "$f" >/dev/null 2>&1; assert_eq "unknown command -> exit 2" "2" "$?"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
