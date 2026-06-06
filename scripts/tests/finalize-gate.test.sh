#!/usr/bin/env bash
# Self-contained tests for finalize-gate.sh (PreToolUse hook handler that blocks merge/push
# until the QA gates are green). Feeds a PreToolUse JSON on stdin + a QA_RUN_STATE file.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GATE="$SCRIPT_DIR/finalize-gate.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
# rc <command> [state-file]
rc() {
  local cmd="$1" state="${2:-}"
  local json; json="$(printf '{"tool_name":"Bash","tool_input":{"command":"%s"},"cwd":"/tmp"}' "$cmd")"
  if [ -n "$state" ]; then printf '%s' "$json" | QA_RUN_STATE="$state" bash "$GATE" >/dev/null 2>&1
  else printf '%s' "$json" | QA_RUN_STATE="/nonexistent/qa-run.json" bash "$GATE" >/dev/null 2>&1; fi
  echo "$?"
}

tmp="$(mktemp -d)"

# --- fixtures: a GREEN manifest + report (all three gates pass) ---
cat > "$tmp/manifest.md" <<'MD'
# Checklist manifest
## Context
### Discussion — GitHub PR + Jira
PR #3146: reviewer flagged Redis desync. Jira: dev says repair runs on worker.
### Prior tests
FRESH — first test (prior-tests.sh = NONE)
### Research (Exa)
Octane RollbackOpenTransactions leaks tx across requests -> item 1.
## Journeys
| J | Actor | Action | Outcome |
|---|-------|--------|---------|
| J1 | customer | charge/refund | balance correct |
## Items
| ID | Journey | What to run | Expected |
|----|---------|-------------|----------|
| 1 | J1 | `curl /charge` | balance-10 |
| 2 | J1 | `curl /refund` | balance+refund |
MD

cat > "$tmp/report_green.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl /charge` | pass | observed-data | R1 | balance=90 |
| 2 | refund | `curl /refund` | pass | observed-data | R1 | balance=110 |
## Verdict
GO
MD

# report where item 1 was skipped (not executed)
cat > "$tmp/report_skipreq.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | charge | `curl /charge` | not executed | n/a | R1 | - |
| 2 | refund | `curl /refund` | pass | observed-data | R1 | balance=110 |
## Verdict
GO
MD

# report missing item 1 entirely (coverage + required both fail)
cat > "$tmp/report_missing.md" <<'MD'
# Test Report
**Prior-test basis:** FRESH
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 2 | refund | `curl /refund` | pass | observed-data | R1 | balance=110 |
## Verdict
GO
MD

state() { printf '{"manifest":"%s","report":"%s","branch":"feature/x"}' "$tmp/manifest.md" "$1" > "$tmp/state.json"; echo "$tmp/state.json"; }

# Non-git command -> allow (0), even with a red run-state
assert_eq "non-git command -> allow (0)" "0" "$(rc "ls -la" "$(state "$tmp/report_skipreq.md")")"

# git merge but NO run-state -> allow (0): no QA in progress
assert_eq "git merge, no run-state -> allow (0)" "0" "$(rc "git merge feature/x")"

# git merge + GREEN run-state -> allow (0)
assert_eq "git merge, all gates green -> allow (0)" "0" "$(rc "git merge feature/x" "$(state "$tmp/report_green.md")")"

# git merge + run-state where an item was 'not executed' -> BLOCK (2)
assert_eq "git merge, item not executed -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$(state "$tmp/report_skipreq.md")")"

# git push + run-state with a dropped item (coverage fail) -> BLOCK (2)
assert_eq "git push, checklist item dropped -> BLOCK (2)" "2" "$(rc "git push origin develop" "$(state "$tmp/report_missing.md")")"

# gh pr merge + a not-executed item -> BLOCK (2)
assert_eq "gh pr merge, item not executed -> BLOCK (2)" "2" "$(rc "gh pr merge 42 --squash" "$(state "$tmp/report_skipreq.md")")"

# git merge + run-state but the report file doesn't exist yet -> BLOCK (2)
assert_eq "git merge, no report yet -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$(state "$tmp/nope_report.md")")"

# git merge + run-state but manifest missing -> BLOCK (2)
printf '{"manifest":"%s","report":"%s"}' "$tmp/nope_manifest.md" "$tmp/report_green.md" > "$tmp/state_nomani.json"
assert_eq "git merge, manifest missing -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$tmp/state_nomani.json")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
