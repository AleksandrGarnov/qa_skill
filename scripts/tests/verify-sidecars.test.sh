#!/usr/bin/env bash
# Self-contained tests for verify-sidecars.sh (md <-> json item-ID consistency gate).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VS="$SCRIPT_DIR/verify-sidecars.sh"
pass=0; fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VS" "$1" "$2" "$3" "$4" >/dev/null 2>&1; echo "$?"; }
tmp="$(mktemp -d)"

cat > "$tmp/m.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 1 | J1 | x | 90 | spec |
| 2 | J1 | y | 110 | spec |
MD
cat > "$tmp/r.md" <<'MD'
# Test Report
## Checklist results
| # | Item | How run | Result | Evidence | Round | Actual |
|---|------|---------|--------|----------|-------|--------|
| 1 | a | x | pass | api | R1 | 90 |
| 2 | b | y | pass | api | R1 | 110 |
MD
cat > "$tmp/m.json" <<'JSON'
{"items":[{"id":"1"},{"id":"2"}]}
JSON
cat > "$tmp/r.json" <<'JSON'
{"results":[{"itemId":"1"},{"itemId":"2"}]}
JSON

# All four agree -> SIDECARS-OK (0)
assert_eq "md/json item IDs match -> exit 0" "0" "$(rc "$tmp/m.md" "$tmp/m.json" "$tmp/r.md" "$tmp/r.json")"

# manifest.json missing an item present in md -> FAIL
cat > "$tmp/m_missing.json" <<'JSON'
{"items":[{"id":"1"}]}
JSON
assert_eq "manifest item in md not json -> exit 1" "1" "$(rc "$tmp/m.md" "$tmp/m_missing.json" "$tmp/r.md" "$tmp/r.json")"

# manifest.json has an EXTRA item not in md -> FAIL
cat > "$tmp/m_extra.json" <<'JSON'
{"items":[{"id":"1"},{"id":"2"},{"id":"9"}]}
JSON
assert_eq "manifest item in json not md -> exit 1" "1" "$(rc "$tmp/m.md" "$tmp/m_extra.json" "$tmp/r.md" "$tmp/r.json")"

# report.json itemId disagrees with report.md -> FAIL
cat > "$tmp/r_mismatch.json" <<'JSON'
{"results":[{"itemId":"1"},{"itemId":"3"}]}
JSON
assert_eq "report result IDs disagree -> exit 1" "1" "$(rc "$tmp/m.md" "$tmp/m.json" "$tmp/r.md" "$tmp/r_mismatch.json")"

# unparseable json -> FAIL (not a crash)
printf '{ this is not json ' > "$tmp/bad.json"
assert_eq "unparseable manifest json -> exit 1" "1" "$(rc "$tmp/m.md" "$tmp/bad.json" "$tmp/r.md" "$tmp/r.json")"

# missing file -> exit 1
assert_eq "missing file -> exit 1" "1" "$(rc "$tmp/nope.md" "$tmp/m.json" "$tmp/r.md" "$tmp/r.json")"

# numeric-vs-string IDs still compare equal (json 1 == md 1)
cat > "$tmp/m_numeric.json" <<'JSON'
{"items":[{"id":1},{"id":2}]}
JSON
assert_eq "numeric json ids match string md ids -> exit 0" "0" "$(rc "$tmp/m.md" "$tmp/m_numeric.json" "$tmp/r.md" "$tmp/r.json")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
