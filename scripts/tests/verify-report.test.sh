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
- Fingerprint: wallet · reconcile() · stale snapshot overwrites a fresh credit
- Repro provenance: executed — steps below run as written on R1
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

# --- Fingerprint + repro provenance (cross-run identity, honesty about the repro) ---
mkbug() { # $1=file  $2=fingerprint line  $3=provenance line
  cat > "$1" <<MD
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | reconcile | \`app reconcile --id=1\` | fail | observed-data | R1 | balance=-100 |
## Found bugs
### BUG-01 — reconcile loses a credit
$2
$3
- Repro steps:
  1. credit 50 via \`app credit --id=1 --amount=50\`
  2. read \`app balance --id=1\` -> shows 0, not 50
## Verdict
NO-GO
MD
}
FP='- **Fingerprint:** wallet · reconcile() · stale snapshot overwrites a fresh credit'
mkbug "$tmp/fp_missing.md" "" "- **Repro provenance:** executed"
assert_eq "bug without Fingerprint -> exit 1" "1" "$(rc "$tmp/fp_missing.md")"
mkbug "$tmp/fp_placeholder.md" "- **Fingerprint:** <component · symbol · root cause>" "- **Repro provenance:** executed"
assert_eq "bug with placeholder Fingerprint -> exit 1" "1" "$(rc "$tmp/fp_placeholder.md")"
mkbug "$tmp/prov_missing.md" "$FP" ""
assert_eq "bug without Repro provenance -> exit 1" "1" "$(rc "$tmp/prov_missing.md")"
mkbug "$tmp/prov_bogus.md" "$FP" "- **Repro provenance:** probably fine"
assert_eq "bug with unknown provenance value -> exit 1" "1" "$(rc "$tmp/prov_bogus.md")"
mkbug "$tmp/prov_placeholder.md" "$FP" "- **Repro provenance:** <executed / derived / script only>"
assert_eq "bug with placeholder provenance -> exit 1" "1" "$(rc "$tmp/prov_placeholder.md")"
mkbug "$tmp/prov_derived.md" "$FP" "- **Repro provenance:** derived — reconstructed from the API log, not re-run as written"
assert_eq "derived provenance -> exit 0" "0" "$(rc "$tmp/prov_derived.md")"
mkbug "$tmp/prov_script.md" "$FP" "- **Repro provenance:** script only — not reproducible by hand: needs a 20-request parallel burst"
assert_eq "script-only provenance -> exit 0" "0" "$(rc "$tmp/prov_script.md")"
mkbug "$tmp/prov_ru.md" "- **Отпечаток:** кошелёк · reconcile() · снапшот затирает кредит" "- **Происхождение repro:** выполнено — шаги прогнаны как записаны"
assert_eq "RU labels/values -> exit 0" "0" "$(rc "$tmp/prov_ru.md")"
out="$("$VR" "$tmp/prov_missing.md" 2>&1)"
case "$out" in *"BUG-01"*"provenance"*|*"provenance"*"BUG-01"*) echo "ok   - violation names the bug and the missing field"; pass=$((pass+1));;
  *) echo "FAIL - violation should name the bug and field: $out"; fail=$((fail+1));; esac

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

# BYPASS-4: a non-numeric / alpha item ID must NOT let empty cells escape the completeness check.
cat > "$tmp/alpha_empty.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| A1 | balance reconciles |  |  |  |  |  |
## Verdict
NO-GO
MD
assert_eq "alpha-ID row with empty cells -> exit 1" "1" "$(rc "$tmp/alpha_empty.md")"

# BYPASS-5: a clean GO written OUTSIDE the `**Verdict:` prefix must still block over a not-executed row.
cat > "$tmp/go_reformatted.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | check A | `app a` | pass | observed-data | R1 | ok |
| 2 | check B | `app b` | not executed | n/a | R1 | not run |
## Verdict
GO — shipping it
MD
assert_eq "reformatted clean GO + not-executed -> exit 1" "1" "$(rc "$tmp/go_reformatted.md")"

# Missing file -> exit 1
# Localization (RU): a report following the template with Russian headings + basis line passes.
cat > "$tmp/ru_ok.md" <<'MD'
# Отчёт
**Основа теста:** RE-TEST of LM-10213
## Результаты по чек-листу
| # | Пункт | Как | Итог | Evidence | Раунд | Факт |
|---|-------|-----|------|----------|-------|------|
| 1 | буфер | рефлексия | pass | observed-data | R1 | 14:28 |
## Вердикт
GO
MD
assert_eq "RU-headed complete report -> exit 0" "0" "$(rc "$tmp/ru_ok.md")"

# Localization (RU): a clean GO over a 'не выполнен' row still blocks.
cat > "$tmp/ru_notrun.md" <<'MD'
# Отчёт
**Основа теста:** RE-TEST
## Результаты по чек-листу
| # | Пункт | Как | Итог | Evidence | Раунд | Факт |
|---|-------|-----|------|----------|-------|------|
| 1 | a | x | pass | api | R1 | ok |
| 2 | b | y | не выполнен | n/a | R1 | - |
## Вердикт
GO
MD
assert_eq "RU clean GO over 'не выполнен' -> exit 1" "1" "$(rc "$tmp/ru_notrun.md")"

assert_eq "missing report -> exit 1" "1" "$(rc "$tmp/does-not-exist.md")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
