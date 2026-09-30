#!/usr/bin/env bash
# Self-contained tests for verify-gap.sh (Test-Gap coverage: changed surface -> covering item / N/A).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VG="$SCRIPT_DIR/verify-gap.sh"
pass=0; fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected [$expected] actual [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VG" "$1" "$2" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Frozen surfaces list (from changed-surfaces.sh)
cat > "$tmp/surfaces.txt" <<'TXT'
# changed behaviour surfaces
app/Services/Wallet.php::amountFloat
app/Nova/DepositResource.php
database/migrations/2018_x_wallets.php
TXT

# GOOD manifest: every surface mapped to a real item or a reasoned N/A
cat > "$tmp/good.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
| I2 | J1 | decision-table | run | ok | spec |
## Changed-surface coverage
| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| app/Services/Wallet.php::amountFloat | I1, I2 | |
| app/Nova/DepositResource.php | I2 | lens render path |
| database/migrations/2018_x_wallets.php | N/A | schema-only, no behaviour path |
MD
assert_eq "all surfaces mapped -> exit 0" "0" "$(rc "$tmp/good.md" "$tmp/surfaces.txt")"

# Surface missing from the table entirely -> FAIL
cat > "$tmp/missing.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
## Changed-surface coverage
| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| app/Services/Wallet.php::amountFloat | I1 | |
| database/migrations/2018_x_wallets.php | N/A | schema-only |
MD
assert_eq "unmapped surface (Nova missing) -> exit 1" "1" "$(rc "$tmp/missing.md" "$tmp/surfaces.txt")"

# Surface present but empty coverage + no N/A -> FAIL
cat > "$tmp/empty.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
## Changed-surface coverage
| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| app/Services/Wallet.php::amountFloat | I1 | |
| app/Nova/DepositResource.php |  |  |
| database/migrations/2018_x_wallets.php | N/A | schema-only |
MD
assert_eq "empty coverage cell -> exit 1" "1" "$(rc "$tmp/empty.md" "$tmp/surfaces.txt")"

# Bare N/A with no reason -> FAIL
cat > "$tmp/bareNA.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
## Changed-surface coverage
| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| app/Services/Wallet.php::amountFloat | I1 | |
| app/Nova/DepositResource.php | I1 | |
| database/migrations/2018_x_wallets.php | N/A |  |
MD
assert_eq "bare N/A without reason -> exit 1" "1" "$(rc "$tmp/bareNA.md" "$tmp/surfaces.txt")"

# Dangling coverage ref (item not in ## Items) -> FAIL
cat > "$tmp/dangling.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
## Changed-surface coverage
| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| app/Services/Wallet.php::amountFloat | I1 | |
| app/Nova/DepositResource.php | I9 | |
| database/migrations/2018_x_wallets.php | N/A | schema-only |
MD
assert_eq "dangling item ref I9 -> exit 1" "1" "$(rc "$tmp/dangling.md" "$tmp/surfaces.txt")"

# No ## Changed-surface coverage section at all -> FAIL
cat > "$tmp/nosect.md" <<'MD'
# Checklist manifest
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| I1 | J1 | boundary | run | ok | spec |
MD
assert_eq "no coverage section -> exit 1" "1" "$(rc "$tmp/nosect.md" "$tmp/surfaces.txt")"

# Empty surfaces list (no behaviour changed) -> exit 0 even without a section
cat > "$tmp/empty.txt" <<'TXT'
# nothing behaviour-carrying changed
TXT
assert_eq "empty surfaces list -> exit 0" "0" "$(rc "$tmp/nosect.md" "$tmp/empty.txt")"

# Missing files -> exit 1
assert_eq "missing manifest -> exit 1" "1" "$(rc "$tmp/nope.md" "$tmp/surfaces.txt")"
assert_eq "missing surfaces -> exit 1" "1" "$(rc "$tmp/good.md" "$tmp/nope.txt")"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
