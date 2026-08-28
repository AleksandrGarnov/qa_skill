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
### Adversarial
Landed: double-spend via concurrent /charge -> item 1 (repro test attached). Not landed: negative amount rejected.
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

mkdir -p "$tmp/runs/feature-x/run-01"
cat > "$tmp/manifest.json" <<'JSON'
{
  "schemaVersion": 1,
  "items": [
    {"id": "1", "journeyRef": "J1", "acRefs": ["AC1"], "criticalPath": true},
    {"id": "2", "journeyRef": "J1", "acRefs": ["AC2"], "criticalPath": false}
  ],
  "acceptanceCriteria": [
    {"id": "AC1", "kind": "runtime"},
    {"id": "AC2", "kind": "runtime"}
  ]
}
JSON
cat > "$tmp/report.json" <<'JSON'
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "api-response", "round": "R1", "rawQuote": "HTTP 200 balance=90", "artifactRefs": ["api-R1-1"]},
    {"itemId": "2", "result": "pass", "evidenceType": "observed-data", "round": "R1", "rawQuote": "balance=110", "artifactRefs": ["api-R1-2"]}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]},
    {"acId": "AC2", "status": "pass", "coveringItemIds": ["2"]}
  ],
  "independentReexecution": [
    {"itemId": "1", "status": "agree", "artifactRefs": ["reexec-R1-1"]}
  ]
}
JSON
cat > "$tmp/runs/feature-x/run-01/artifacts.json" <<JSON
{
  "artifacts": [
    {"id": "api-R1-1", "path": "$tmp/api-R1-1.txt", "kind": "api"},
    {"id": "api-R1-2", "path": "$tmp/api-R1-2.txt", "kind": "observed-data"},
    {"id": "reexec-R1-1", "path": "$tmp/reexec-R1-1.txt", "kind": "independent-reexecution"}
  ]
}
JSON
printf 'HTTP 200 balance=90\n' > "$tmp/api-R1-1.txt"
printf 'balance=110\n' > "$tmp/api-R1-2.txt"
printf 'independent rerun agrees\n' > "$tmp/reexec-R1-1.txt"

state() { printf '{"manifest":"%s","report":"%s","branch":"feature/x"}' "$tmp/manifest.md" "$1" > "$tmp/state.json"; echo "$tmp/state.json"; }
state_rich() {
  printf '{"schemaVersion":1,"runId":"run-01","status":"approved","branch":"feature/x","bundleDir":"%s","manifest":"%s","manifestMd":"%s","manifestJson":"%s","report":"%s","reportMd":"%s","reportJson":"%s","artifactsIndexJson":"%s","currentRound":"R1","gates":{"context":"pending","coverage":"pending","report":"pending","evidence":"pending"}}' \
    "$tmp/runs/feature-x/run-01" "$tmp/manifest.md" "$tmp/manifest.md" "$2" "$1" "$1" "$3" "$tmp/runs/feature-x/run-01/artifacts.json" > "$tmp/state_rich.json"
  echo "$tmp/state_rich.json"
}

# Non-git command -> allow (0), even with a red run-state
assert_eq "non-git command -> allow (0)" "0" "$(rc "ls -la" "$(state "$tmp/report_skipreq.md")")"

# git merge but NO run-state -> allow (0): no QA in progress
assert_eq "git merge, no run-state -> allow (0)" "0" "$(rc "git merge feature/x")"

# git merge + GREEN run-state -> allow (0)
assert_eq "git merge, all gates green -> allow (0)" "0" "$(rc "git merge feature/x" "$(state "$tmp/report_green.md")")"

# richer sidecar-aware run-state also requires structured evidence to be green
assert_eq "git merge, richer sidecar state -> allow (0)" "0" "$(rc "git merge feature/x" "$(state_rich "$tmp/report_green.md" "$tmp/manifest.json" "$tmp/report.json")")"

cat > "$tmp/report_bad_evidence.json" <<'JSON'
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "unit:mocked", "round": "R1", "rawQuote": "mock says ok", "artifactRefs": []},
    {"itemId": "2", "result": "pass", "evidenceType": "observed-data", "round": "R1", "rawQuote": "balance=110", "artifactRefs": ["api-R1-2"]}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]},
    {"acId": "AC2", "status": "pass", "coveringItemIds": ["2"]}
  ],
  "independentReexecution": [
    {"itemId": "1", "status": "agree", "artifactRefs": ["reexec-R1-1"]}
  ]
}
JSON
assert_eq "git merge, richer state with red evidence gate -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$(state_rich "$tmp/report_green.md" "$tmp/manifest.json" "$tmp/report_bad_evidence.json")")"

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

# richer state with declared manifestJson missing on disk -> BLOCK (2)
printf '{"schemaVersion":1,"runId":"run-01","status":"approved","branch":"feature/x","bundleDir":"%s","manifest":"%s","manifestMd":"%s","manifestJson":"%s","report":"%s","reportMd":"%s","reportJson":"%s","artifactsIndexJson":"%s","currentRound":"R1","gates":{"context":"pending","coverage":"pending","report":"pending","evidence":"pending"}}' \
  "$tmp/runs/feature-x/run-01" "$tmp/manifest.md" "$tmp/manifest.md" "$tmp/nope_manifest.json" "$tmp/report_green.md" "$tmp/report_green.md" "$tmp/report.json" "$tmp/runs/feature-x/run-01/artifacts.json" > "$tmp/state_missing_manifest_json.json"
assert_eq "git merge, declared manifestJson missing -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$tmp/state_missing_manifest_json.json")"

# richer state with missing artifacts index -> BLOCK (2)
printf '{"schemaVersion":1,"runId":"run-01","status":"approved","branch":"feature/x","bundleDir":"%s","manifest":"%s","manifestMd":"%s","manifestJson":"%s","report":"%s","reportMd":"%s","reportJson":"%s","artifactsIndexJson":"%s","currentRound":"R1","gates":{"context":"pending","coverage":"pending","report":"pending","evidence":"pending"}}' \
  "$tmp/runs/feature-x/run-01" "$tmp/manifest.md" "$tmp/manifest.md" "$tmp/manifest.json" "$tmp/report_green.md" "$tmp/report_green.md" "$tmp/report.json" "$tmp/nope_artifacts.json" > "$tmp/state_missing_artifacts.json"
assert_eq "git merge, richer state missing artifacts index -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$tmp/state_missing_artifacts.json")"

# BYPASS-11: a sidecar-aware run-state (schemaVersion/manifestJson set) with an EMPTY reportJson
# must not silently opt out of the evidence gate -> BLOCK (2), not allow.
printf '{"schemaVersion":1,"runId":"run-01","status":"approved","branch":"feature/x","bundleDir":"%s","manifest":"%s","manifestMd":"%s","manifestJson":"%s","report":"%s","reportMd":"%s","reportJson":"","artifactsIndexJson":"%s","currentRound":"R1","gates":{"context":"pending","coverage":"pending","report":"pending","evidence":"pending"}}' \
  "$tmp/runs/feature-x/run-01" "$tmp/manifest.md" "$tmp/manifest.md" "$tmp/manifest.json" "$tmp/report_green.md" "$tmp/report_green.md" "$tmp/runs/feature-x/run-01/artifacts.json" > "$tmp/state_empty_reportjson.json"
assert_eq "sidecar-aware but empty reportJson -> BLOCK (2)" "2" "$(rc "git merge feature/x" "$tmp/state_empty_reportjson.json")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
