#!/usr/bin/env bash
# Self-contained tests for verify-deploy.sh — no external test framework.
# Uses file:// URLs pointing at temp files to stand in for the version endpoint.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERIFY="$SCRIPT_DIR/verify-deploy.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

# exit code of a verify-deploy run (output suppressed)
run_rc() { "$VERIFY" "$1" "$2" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"
COMMIT="deadbeef1234567"      # short = deadbee

# Case 1: deployed commit present in the response -> OK (exit 0)
printf '{"build":"deadbeef1234567","env":"stage"}' > "$tmp/ok.json"
assert_eq "commit present -> exit 0" "0" "$(run_rc "file://$tmp/ok.json" "$COMMIT")"

# Case 2: short hash present even when full hash differs downstream -> OK (matches on short)
printf 'version deadbee built today' > "$tmp/short.txt"
assert_eq "short hash match -> exit 0" "0" "$(run_rc "file://$tmp/short.txt" "$COMMIT")"

# Case 3: a different commit is deployed -> MISMATCH (exit 2)
printf '{"build":"cafebabe9999000"}' > "$tmp/bad.json"
assert_eq "wrong build -> exit 2" "2" "$(run_rc "file://$tmp/bad.json" "$COMMIT")"

# Case 4: endpoint unreachable -> exit 1
assert_eq "unreachable -> exit 1" "1" "$(run_rc "file://$tmp/does-not-exist.json" "$COMMIT")"

# Case 5: case-insensitive match (grep -i) -> OK
printf 'BUILD: DEADBEE' > "$tmp/upper.txt"
assert_eq "case-insensitive match -> exit 0" "0" "$(run_rc "file://$tmp/upper.txt" "$COMMIT")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
