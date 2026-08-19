#!/usr/bin/env bash
# Self-contained tests for qa-bundle.sh — canonical bundle paths and run-state validation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QB="$SCRIPT_DIR/qa-bundle.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

assert_match() {
  local desc="$1" pattern="$2" actual="$3"
  if printf '%s' "$actual" | grep -Eq "$pattern"; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       pattern:  [$pattern]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

tmp="$(mktemp -d)"

after() { rm -rf "$tmp"; }
trap after EXIT

bundle_out="$(bash "$QB" init "$tmp/docs" "Feature/PROJ-123 Login" "Run 01" 2>/dev/null)"
bundle_dir="$(printf '%s\n' "$bundle_out" | sed -n 's/^BUNDLE-DIR: //p')"
manifest_md="$(printf '%s\n' "$bundle_out" | sed -n 's/^MANIFEST-MD: //p')"
manifest_json="$(printf '%s\n' "$bundle_out" | sed -n 's/^MANIFEST-JSON: //p')"
report_md="$(printf '%s\n' "$bundle_out" | sed -n 's/^REPORT-MD: //p')"
report_json="$(printf '%s\n' "$bundle_out" | sed -n 's/^REPORT-JSON: //p')"
artifacts_json="$(printf '%s\n' "$bundle_out" | sed -n 's/^ARTIFACTS-JSON: //p')"
gates_dir="$(printf '%s\n' "$bundle_out" | sed -n 's/^GATES-DIR: //p')"
artifacts_dir="$(printf '%s\n' "$bundle_out" | sed -n 's/^ARTIFACTS-DIR: //p')"

assert_match "init prints sanitized bundle dir" '.*/docs/runs/feature-proj-123-login/run-01$' "$bundle_dir"
assert_eq "init creates bundle dir" "yes" "$(test -d "$bundle_dir" && echo yes || echo no)"
assert_eq "init creates gates dir" "yes" "$(test -d "$gates_dir" && echo yes || echo no)"
assert_eq "init creates artifacts dir" "yes" "$(test -d "$artifacts_dir" && echo yes || echo no)"
assert_eq "init creates artifacts index" "yes" "$(test -f "$artifacts_json" && echo yes || echo no)"
assert_eq "init pre-creates manifest.md path parent" "yes" "$(test -d "$(dirname "$manifest_md")" && echo yes || echo no)"
assert_match "manifest json path uses bundle dir" '^.*/manifest\.json$' "$manifest_json"
assert_match "report md path uses bundle dir" '^.*/report\.md$' "$report_md"
assert_match "report json path uses bundle dir" '^.*/report\.json$' "$report_json"

paths_out="$(bash "$QB" paths "$tmp/docs" "Feature/PROJ-123 Login" "Run 01" 2>/dev/null)"
assert_eq "paths reuses canonical bundle dir" "$bundle_dir" "$(printf '%s\n' "$paths_out" | sed -n 's/^BUNDLE-DIR: //p')"
assert_eq "paths does not require pre-existing files" "$manifest_md" "$(printf '%s\n' "$paths_out" | sed -n 's/^MANIFEST-MD: //p')"

cat > "$tmp/state_good.json" <<JSON
{
  "schemaVersion": 1,
  "runId": "run-01",
  "status": "approved",
  "branch": "feature/PROJ-123-login",
  "bundleDir": "$bundle_dir",
  "manifest": "$manifest_md",
  "manifestMd": "$manifest_md",
  "manifestJson": "$manifest_json",
  "report": "$report_md",
  "reportMd": "$report_md",
  "reportJson": "$report_json",
  "artifactsIndexJson": "$artifacts_json",
  "currentRound": "R1",
  "gates": {
    "context": "pending",
    "coverage": "pending",
    "report": "pending",
    "evidence": "pending"
  }
}
JSON

validate_good="$(bash "$QB" state validate "$tmp/state_good.json" 2>/dev/null)"
assert_eq "state validate passes for richer state" "STATE-OK: active run-state is complete" "$validate_good"

cat > "$tmp/state_bad.json" <<JSON
{
  "schemaVersion": 1,
  "runId": "run-01",
  "status": "approved",
  "branch": "feature/PROJ-123-login",
  "manifest": "$manifest_md",
  "report": "$report_md"
}
JSON

bash "$QB" state validate "$tmp/state_bad.json" >/dev/null 2>&1
assert_eq "state validate fails on missing required fields" "1" "$?"

bash "$QB" mystery >/dev/null 2>&1
assert_eq "unknown command exits 2" "2" "$?"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
