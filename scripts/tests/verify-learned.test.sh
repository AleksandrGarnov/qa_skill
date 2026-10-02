#!/usr/bin/env bash
# Self-contained tests for verify-learned.sh (known recurring risk must be addressed).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VL="$SCRIPT_DIR/verify-learned.sh"
pass=0; fail=0
assert_eq() { local d="$1" e="$2" a="$3"; if [ "$e" = "$a" ]; then echo "ok   - $d"; pass=$((pass+1)); else echo "FAIL - $d"; echo "   exp [$e] got [$a]"; fail=$((fail+1)); fi; }
rc() { "$VL" "$1" "$2" "$3" >/dev/null 2>&1; echo "$?"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/kb.md" <<'MD'
# QA knowledge base
| # | Component / area | Recurring risk (category) | Required technique / check | Freq | Learned from |
|---|------------------|---------------------------|----------------------------|------|--------------|
| 1 | Wallet | concurrency / in-the-window | state-transition all-transitions | 3 | PAY-ESC-01 |
MD

# surfaces that TOUCH Wallet
cat > "$tmp/surf_hit.txt" <<'TXT'
app/Services/Wallet.php::charge
app/Nova/DepositResource.php
TXT
# surfaces that do NOT touch Wallet
cat > "$tmp/surf_miss.txt" <<'TXT'
app/Http/Controllers/ReportController.php::index
TXT

# manifest WITH a Learned risks row addressing Wallet
cat > "$tmp/man_ok.md" <<'MD'
# Checklist
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| 1 | J1 | state-transition | concurrent charge | no double-count | spec |
## Learned risks
| # | Component | Recurring risk | Addressed by (items / technique) or N/A — reason |
|---|-----------|----------------|--------------------------------------------------|
| 1 | Wallet | concurrency / in-the-window | I1 — state-transition all-transitions |
MD

# manifest MISSING the Learned risks section
cat > "$tmp/man_nosect.md" <<'MD'
# Checklist
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| 1 | J1 | state-transition | concurrent charge | ok | spec |
MD

# manifest with the section but Wallet row empty (not addressed, no N/A)
cat > "$tmp/man_empty.md" <<'MD'
# Checklist
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| 1 | J1 | boundary | x | ok | spec |
## Learned risks
| # | Component | Recurring risk | Addressed by (items / technique) or N/A — reason |
|---|-----------|----------------|--------------------------------------------------|
| 1 | Wallet | concurrency / in-the-window |  |
MD

# manifest that dismisses the risk with a reasoned N/A
cat > "$tmp/man_na.md" <<'MD'
# Checklist
## Items
| ID | Journey | Technique | What to run | Expected | Expected source |
|----|---------|-----------|-------------|----------|-----------------|
| 1 | J1 | boundary | x | ok | spec |
## Learned risks
| # | Component | Recurring risk | Addressed by (items / technique) or N/A — reason |
|---|-----------|----------------|--------------------------------------------------|
| 1 | Wallet | concurrency / in-the-window | N/A — this change is read-only, no concurrent write path |
MD

assert_eq "risk in play + addressed -> exit 0" "0" "$(rc "$tmp/man_ok.md" "$tmp/kb.md" "$tmp/surf_hit.txt")"
assert_eq "risk NOT in play (component untouched) -> exit 0" "0" "$(rc "$tmp/man_nosect.md" "$tmp/kb.md" "$tmp/surf_miss.txt")"
assert_eq "risk in play + no Learned-risks section -> exit 1" "1" "$(rc "$tmp/man_nosect.md" "$tmp/kb.md" "$tmp/surf_hit.txt")"
assert_eq "risk in play + empty addressing cell -> exit 1" "1" "$(rc "$tmp/man_empty.md" "$tmp/kb.md" "$tmp/surf_hit.txt")"
assert_eq "risk in play + reasoned N/A -> exit 0" "0" "$(rc "$tmp/man_na.md" "$tmp/kb.md" "$tmp/surf_hit.txt")"
assert_eq "no KB file yet -> exit 0" "0" "$(rc "$tmp/man_nosect.md" "$tmp/nope_kb.md" "$tmp/surf_hit.txt")"
assert_eq "missing manifest -> exit 1" "1" "$(rc "$tmp/nope.md" "$tmp/kb.md" "$tmp/surf_hit.txt")"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
