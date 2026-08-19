#!/usr/bin/env bash
# Self-contained tests for verify-evidence.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VE="$SCRIPT_DIR/verify-evidence.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VE" "$1" "$2" "$3" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"
mkdir -p "$tmp/artifacts"
printf 'raw http response\n' > "$tmp/artifacts/api-R1-1.txt"
printf 'independent rerun output\n' > "$tmp/artifacts/reexec-R1-1.txt"
cat > "$tmp/artifacts.json" <<JSON
{
  "artifacts": [
    {"id": "api-R1-1", "path": "$tmp/artifacts/api-R1-1.txt", "kind": "api"},
    {"id": "reexec-R1-1", "path": "$tmp/artifacts/reexec-R1-1.txt", "kind": "independent-reexecution"}
  ]
}
JSON

cat > "$tmp/manifest_good.json" <<JSON
{
  "schemaVersion": 1,
  "items": [
    {"id": "1", "journeyRef": "J1", "acRefs": ["AC1"], "criticalPath": true},
    {"id": "2", "journeyRef": "J1", "acRefs": ["AC2"], "criticalPath": false}
  ],
  "acceptanceCriteria": [
    {"id": "AC1", "kind": "runtime"},
    {"id": "AC2", "kind": "static"}
  ]
}
JSON

cat > "$tmp/report_good.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "api-response", "round": "R1", "rawQuote": "HTTP 200 balance=90", "artifactRefs": ["api-R1-1"]},
    {"itemId": "2", "result": "pass", "evidenceType": "code-read", "round": "R1", "rawQuote": "Button label matches spec", "artifactRefs": []}
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
assert_eq "runtime AC + corroborated critical path -> exit 0" "0" "$(rc "$tmp/manifest_good.json" "$tmp/report_good.json" "$tmp/artifacts.json")"

cat > "$tmp/report_mocked_runtime.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "unit:mocked", "round": "R1", "rawQuote": "mock returned 200", "artifactRefs": []}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]}
  ],
  "independentReexecution": [
    {"itemId": "1", "status": "agree", "artifactRefs": ["reexec-R1-1"]}
  ]
}
JSON
assert_eq "runtime AC with mocked-only evidence -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/report_mocked_runtime.json" "$tmp/artifacts.json")"

cat > "$tmp/report_missing_reexec.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "observed-data", "round": "R1", "rawQuote": "balance=90", "artifactRefs": ["api-R1-1"]}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]}
  ],
  "independentReexecution": []
}
JSON
assert_eq "critical-path pass without corroboration -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/report_missing_reexec.json" "$tmp/artifacts.json")"

cat > "$tmp/report_acceptance_test_equivalent.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "log", "round": "R1", "rawQuote": "accepted by black-box suite", "artifactRefs": ["api-R1-1"], "acceptanceTestEquivalent": true}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]}
  ],
  "independentReexecution": []
}
JSON
assert_eq "critical-path acceptance-test equivalent bypasses corroboration -> exit 0" "0" "$(rc "$tmp/manifest_good.json" "$tmp/report_acceptance_test_equivalent.json" "$tmp/artifacts.json")"

cat > "$tmp/report_missing_artifact.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "api-response", "round": "R1", "rawQuote": "HTTP 200", "artifactRefs": ["missing-artifact"]}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]}
  ],
  "independentReexecution": [
    {"itemId": "1", "status": "agree", "artifactRefs": ["reexec-R1-1"]}
  ]
}
JSON
assert_eq "missing artifact ref -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/report_missing_artifact.json" "$tmp/artifacts.json")"

cat > "$tmp/report_missing_raw_quote.json" <<JSON
{
  "schemaVersion": 1,
  "results": [
    {"itemId": "1", "result": "pass", "evidenceType": "observed-data", "round": "R1", "rawQuote": "", "artifactRefs": ["api-R1-1"]}
  ],
  "acMatrix": [
    {"acId": "AC1", "status": "pass", "coveringItemIds": ["1"]}
  ],
  "independentReexecution": [
    {"itemId": "1", "status": "agree", "artifactRefs": ["reexec-R1-1"]}
  ]
}
JSON
assert_eq "runtime pass without raw quote -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/report_missing_raw_quote.json" "$tmp/artifacts.json")"

assert_eq "missing manifest json -> exit 1" "1" "$(rc "$tmp/nope_manifest.json" "$tmp/report_good.json" "$tmp/artifacts.json")"
assert_eq "missing report json -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/nope_report.json" "$tmp/artifacts.json")"
assert_eq "missing artifacts index -> exit 1" "1" "$(rc "$tmp/manifest_good.json" "$tmp/report_good.json" "$tmp/nope_artifacts.json")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
