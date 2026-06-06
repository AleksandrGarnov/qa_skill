#!/usr/bin/env bash
# Self-contained tests for verify-coverage.sh (manifest <-> report coverage set-diff).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VC="$SCRIPT_DIR/verify-coverage.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VC" "$1" "$2" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"

# A well-formed manifest: 3 items, all journey-rooted across 2 journeys.
cat > "$tmp/manifest.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
| J2 | admin | processes a payout | funds released |
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl -XPOST /api/charge` | balance-10 |
| 2 | J1 | `curl -XPOST /api/refund` | balance+refund |
| 3 | J2 | admin UI: approve payout #5515 | paid |
MD

# Report that accounts for all 3 ids -> COVERAGE-OK (0)
cat > "$tmp/rep_full.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl -XPOST /api/charge` | pass | api-response | R1 | balance=90 |
| 2 | refund | `curl -XPOST /api/refund` | pass | api-response | R1 | balance=110 |
| 3 | payout | admin UI approve #5515 | pass | observed-data | R1 | paid |
MD
assert_eq "all approved items accounted -> exit 0" "0" "$(rc "$tmp/manifest.md" "$tmp/rep_full.md")"

# Report where item 3 is present but 'not executed' -> FAIL (1, a skip)
cat > "$tmp/rep_notrun.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl -XPOST /api/charge` | pass | api-response | R1 | balance=90 |
| 2 | refund | `curl -XPOST /api/refund` | pass | api-response | R1 | balance=110 |
| 3 | payout | — | not executed | n/a | R1 | not run |
MD
assert_eq "item present but not executed -> exit 1" "1" "$(rc "$tmp/manifest.md" "$tmp/rep_notrun.md")"

# Report missing item 3 -> FAIL (1)
cat > "$tmp/rep_missing.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl -XPOST /api/charge` | pass | api-response | R1 | balance=90 |
| 2 | refund | `curl -XPOST /api/refund` | pass | api-response | R1 | balance=110 |
MD
assert_eq "skipped item (3 not in report) -> exit 1" "1" "$(rc "$tmp/manifest.md" "$tmp/rep_missing.md")"

# Report with an extra item 4 (drift) but all approved present -> OK (0, drift is a NOTE)
cat > "$tmp/rep_drift.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl -XPOST /api/charge` | pass | api-response | R1 | balance=90 |
| 2 | refund | `curl -XPOST /api/refund` | pass | api-response | R1 | balance=110 |
| 3 | payout | admin UI approve #5515 | pass | observed-data | R1 | paid |
| 4 | found mid-run | `curl /api/refund` | pass | api-response | R1 | ok |
MD
assert_eq "drift item added during run -> exit 0 (note)" "0" "$(rc "$tmp/manifest.md" "$tmp/rep_drift.md")"

# Manifest item with no journey ref -> FAIL (1)
cat > "$tmp/man_nojourney.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl /api/charge` | ok |
| 2 |  | `psql -c 'select ...'` | ok |
MD
cat > "$tmp/rep_two.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl /api/charge` | pass | api-response | R1 | ok |
| 2 | query | `psql ...` | pass | observed-data | R1 | ok |
MD
assert_eq "item with no journey ref -> exit 1" "1" "$(rc "$tmp/man_nojourney.md" "$tmp/rep_two.md")"

# Manifest item referencing an undefined journey -> FAIL (1)
cat > "$tmp/man_badjourney.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl /api/charge` | ok |
| 2 | J9 | `curl /api/refund` | ok |
MD
assert_eq "item refs undefined journey -> exit 1" "1" "$(rc "$tmp/man_badjourney.md" "$tmp/rep_two.md")"

# Manifest with zero journeys (code-rooted checklist) -> FAIL (1)
cat > "$tmp/man_nojourneys.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl /api/charge` | ok |
MD
assert_eq "zero journeys (code-rooted) -> exit 1" "1" "$(rc "$tmp/man_nojourneys.md" "$tmp/rep_two.md")"

# Missing manifest / report files -> exit 1
assert_eq "missing manifest -> exit 1" "1" "$(rc "$tmp/nope.md" "$tmp/rep_full.md")"
assert_eq "missing report -> exit 1" "1" "$(rc "$tmp/manifest.md" "$tmp/nope.md")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
