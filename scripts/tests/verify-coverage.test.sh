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
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl -XPOST /api/charge` | balance-10 | hand calc: 100-10 (spec §4) |
| 2 | J1 | `curl -XPOST /api/refund` | balance+refund | invariant: refund credits back |
| 3 | J2 | admin UI: approve payout #5515 | paid | spec: payout state=paid |
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

# BYPASS-3: a disguised skip status ('skipped'/'deferred') must NOT satisfy coverage (whitelist, not blacklist).
for badstatus in skipped deferred wontfix later pending; do
  cat > "$tmp/rep_$badstatus.md" <<MD
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | \`curl -XPOST /api/charge\` | pass | api-response | R1 | balance=90 |
| 2 | refund | \`curl -XPOST /api/refund\` | pass | api-response | R1 | balance=110 |
| 3 | payout | — | $badstatus | n/a | R1 | skipped it |
MD
  assert_eq "disguised skip status '$badstatus' -> exit 1" "1" "$(rc "$tmp/manifest.md" "$tmp/rep_$badstatus.md")"
done

# Valid terminal buckets other than pass (fail/blocked/flaky/N/A with a qualifier) still satisfy coverage.
cat > "$tmp/rep_buckets.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl -XPOST /api/charge` | fail | api-response | R1 | 500 error |
| 2 | refund | `curl -XPOST /api/refund` | blocked — no staging access | n/a | R1 | attempted, no creds |
| 3 | payout | admin UI | N/A (feature-flagged off) | n/a | R1 | n/a |
MD
assert_eq "valid buckets fail/blocked/N-A -> exit 0" "0" "$(rc "$tmp/manifest.md" "$tmp/rep_buckets.md")"

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
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | ok | spec |
| 2 |  | `psql -c 'select ...'` | ok | spec |
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
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | ok | spec |
| 2 | J9 | `curl /api/refund` | ok | spec |
MD
assert_eq "item refs undefined journey -> exit 1" "1" "$(rc "$tmp/man_badjourney.md" "$tmp/rep_two.md")"

# Manifest with zero journeys (code-rooted checklist) -> FAIL (1)
cat > "$tmp/man_nojourneys.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | ok | spec |
MD
assert_eq "zero journeys (code-rooted) -> exit 1" "1" "$(rc "$tmp/man_nojourneys.md" "$tmp/rep_two.md")"

# --- Oracle gate (independent expected source) ---
# Manifest with NO Expected source column -> FAIL (1)
cat > "$tmp/man_nosrccol.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl /api/charge` | balance-10 |
MD
cat > "$tmp/rep_one.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl /api/charge` | pass | api-response | R1 | balance=90 |
MD
assert_eq "no Expected source column -> exit 1" "1" "$(rc "$tmp/man_nosrccol.md" "$tmp/rep_one.md")"

# Item with an EMPTY expected source -> FAIL (1)
cat > "$tmp/man_emptysrc.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | balance-10 |  |
MD
assert_eq "empty expected source -> exit 1" "1" "$(rc "$tmp/man_emptysrc.md" "$tmp/rep_one.md")"

# Item whose oracle IS the implementation -> FAIL (1)
cat > "$tmp/man_implsrc.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | balance-10 | whatever the code returns |
MD
assert_eq "impl-as-oracle -> exit 1" "1" "$(rc "$tmp/man_implsrc.md" "$tmp/rep_one.md")"

# Blatant code-as-oracle paraphrases the tripwire catches (NB: this is best-effort, not exhaustive —
# true independence is a semantic check at step 6.5; the tripwire only trips obvious phrasings).
for phrase in "matches current behavior" "= system output" "per the running app" "as returned" "existing behaviour"; do
  cat > "$tmp/man_impl_para.md" <<MD
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | \`curl /api/charge\` | balance-10 | $phrase |
MD
  assert_eq "code-as-oracle paraphrase '$phrase' -> exit 1" "1" "$(rc "$tmp/man_impl_para.md" "$tmp/rep_one.md")"
done

# Metamorphic-rule oracle (no exact value) is a valid independent source -> exit 0
cat > "$tmp/man_metamorphic.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | debit == credit | metamorphic: double-entry invariant |
MD
assert_eq "metamorphic oracle -> exit 0" "0" "$(rc "$tmp/man_metamorphic.md" "$tmp/rep_one.md")"

# Localization (RU): a code-as-oracle written in Russian trips the tripwire.
cat > "$tmp/man_ru_code.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | balance-10 | hotCutoff() не вычитает (код) |
MD
assert_eq "RU code-as-oracle '(код)' -> exit 1" "1" "$(rc "$tmp/man_ru_code.md" "$tmp/rep_one.md")"

# Localization (RU): a report whose results heading is Russian is still matched for coverage.
cat > "$tmp/man_ru_ok.md" <<'MD'
# Checklist manifest
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | places a charge | balance debited |
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | `curl /api/charge` | balance-10 | ручной расчёт |
MD
cat > "$tmp/rep_ru.md" <<'MD'
# Отчёт
## Результаты по чек-листу
| # | Item | How | Result | Evidence | Round | Actual |
|---|------|-----|--------|----------|-------|--------|
| 1 | charge | run | pass | api-response | R1 | 90 |
MD
assert_eq "RU results heading matched for coverage -> exit 0" "0" "$(rc "$tmp/man_ru_ok.md" "$tmp/rep_ru.md")"

# Missing manifest / report files -> exit 1
assert_eq "missing manifest -> exit 1" "1" "$(rc "$tmp/nope.md" "$tmp/rep_full.md")"
assert_eq "missing report -> exit 1" "1" "$(rc "$tmp/manifest.md" "$tmp/nope.md")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
