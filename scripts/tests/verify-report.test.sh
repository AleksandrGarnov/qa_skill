#!/usr/bin/env bash
# Self-contained tests for verify-report.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VR="$SCRIPT_DIR/verify-report.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VR" "$1" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"

# A complete report (filled prior-test basis + one full execution-record row) -> OK (0)
cat > "$tmp/good.md" <<'MD'
# Test Report
**Prior-test basis (REQUIRED):** FRESH — first test (prior-tests.sh = NONE)
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | balance reconciles | `cli wallet:check-balances --wallet=42469` | pass | observed-data | R1 | Repaired: 1; balance=600000000 |
## Verdict
GO
MD
assert_eq "complete report -> exit 0" "0" "$(rc "$tmp/good.md")"

# Empty cell in a results row -> FAIL (1)
cat > "$tmp/empty.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | balance reconciles |  | pass | observed-data | R1 | Repaired: 1 |
## Verdict
GO
MD
assert_eq "empty cell -> exit 1" "1" "$(rc "$tmp/empty.md")"

# Unfilled <placeholder> cell -> FAIL (1)
cat > "$tmp/placeholder.md" <<'MD'
# Test Report
**Prior-test basis:** RE-TEST of QA-9801 on f032c57bd
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | balance reconciles | <how> | pass | observed-data | R1 | <actual output> |
## Verdict
GO
MD
assert_eq "placeholder cell -> exit 1" "1" "$(rc "$tmp/placeholder.md")"

# Missing Prior-test basis value -> FAIL (1)
cat > "$tmp/nopt.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | balance reconciles | `cli ...` | pass | observed-data | R1 | Repaired: 1 |
## Verdict
GO
MD
assert_eq "no prior-test basis -> exit 1" "1" "$(rc "$tmp/nopt.md")"

# No data rows at all -> FAIL (1)
cat > "$tmp/norows.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
## Verdict
GO
MD
assert_eq "no data rows -> exit 1" "1" "$(rc "$tmp/norows.md")"

# A bug block WITH exact repro steps -> OK (0)
cat > "$tmp/bug_ok.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | reconcile | `app reconcile --id=1` | fail | observed-data | R1 | balance=-100 |
## Found bugs
### BUG-01 — reconcile loses a credit
- Repro steps:
  1. set balance to 0 via `app set-balance --id=1 --to=0`
  2. credit 50 via `app credit --id=1 --amount=50`
  3. read `app balance --id=1` -> shows 0, not 50
## Verdict
NO-GO
MD
assert_eq "bug with exact repro -> exit 0" "0" "$(rc "$tmp/bug_ok.md")"

# A bug block with only PLACEHOLDER repro steps -> FAIL (1)
cat > "$tmp/bug_norepro.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | reconcile | `app reconcile --id=1` | fail | observed-data | R1 | balance=-100 |
## Found bugs
### BUG-01 — reconcile loses a credit
- Mechanism: stale snapshot overwrites fresh DB.
- Repro steps:
  1. <...>
  2. <...>
## Verdict
NO-GO
MD
assert_eq "bug without exact repro -> exit 1" "1" "$(rc "$tmp/bug_norepro.md")"

# Clean GO with a 'not executed' row -> FAIL (1)
cat > "$tmp/cleango_notrun.md" <<'MD'
# Test Report
**Verdict:** ✅ GO
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | check A | `app a` | pass | observed-data | R1 | ok |
| 2 | check B | `app b` | not executed | n/a | R1 | not run — no data |
## Verdict
GO
MD
assert_eq "clean GO + not-executed -> exit 1" "1" "$(rc "$tmp/cleango_notrun.md")"

# Clean GO with all executed -> OK (0)
cat > "$tmp/cleango_ok.md" <<'MD'
# Test Report
**Verdict:** ✅ GO
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | check A | `app a` | pass | observed-data | R1 | ok |
| 2 | check B | `app b` | pass | observed-data | R1 | ok |
## Verdict
GO
MD
assert_eq "clean GO + all run -> exit 0" "0" "$(rc "$tmp/cleango_ok.md")"

# Missing file -> exit 1
assert_eq "missing report -> exit 1" "1" "$(rc "$tmp/does-not-exist.md")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
