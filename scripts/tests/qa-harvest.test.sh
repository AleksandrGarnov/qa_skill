#!/usr/bin/env bash
# Self-contained tests for qa-harvest.sh (corpus mining from prior QA docs).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QH="$SCRIPT_DIR/qa-harvest.sh"
pass=0; fail=0
ok()  { echo "ok   - $1"; pass=$((pass+1)); }
bad() { echo "FAIL - $1"; echo "       $2"; fail=$((fail+1)); }
has() { printf '%s\n' "$1" | grep -qE "$2"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
docs="$tmp/docs"; mkdir -p "$docs"

cat > "$docs/report-PAY-1.md" <<'MD'
# Test Report — PAY-1
**Verdict:** ✅ GO
## Found bugs
### PAY-1-BUG-01 — [Wallet] balance double-counts on retry
- **Severity:** blocker
- **Priority:** high
### PAY-1-BUG-02 — [Nova] currency column 500s on orphan
- **Severity:** major
## Recommendation
ship after fix
MD

cat > "$docs/report-PAY-2.md" <<'MD'
# Test Report — PAY-2
**Verdict:** ⛔ NO-GO
## Found bugs
### PAY-2-BUG-01 — [Wallet] negative amount accepted
- **Severity:** major
MD

cat > "$docs/escaped-defects.md" <<'MD'
# Escaped-defects
escape: PAY-ESC-01
component/area: Wallet
severity: blocker     discovered-by: monitoring
why not caught: missing edge case

escape: PAY-ESC-02
component/area: Wallet
severity: major     discovered-by: user
why not caught: thin regression
MD

# --- bugs ---
bugs="$($QH bugs "$docs")"
has "$bugs" 'Wallet.*blocker.*double-counts'  && ok "bug: Wallet component + blocker severity extracted" || bad "bugs Wallet" "$bugs"
has "$bugs" 'Nova.*major.*currency'           && ok "bug: second component (Nova) extracted"            || bad "bugs Nova" "$bugs"
n=$(printf '%s\n' "$bugs" | grep -c .)
[ "$n" = "3" ] && ok "bugs: 3 found-bug rows across 2 reports" || bad "bug count" "expected 3 got $n: $bugs"

# --- escapes ---
esc="$($QH escapes "$docs")"
has "$esc" 'Wallet.*blocker.*missing edge case' && ok "escape: component+severity+category extracted" || bad "escape1" "$esc"
has "$esc" 'Wallet.*major.*thin regression'     && ok "escape: second record extracted"               || bad "escape2" "$esc"

# --- verdicts ---
ver="$($QH verdicts "$docs")"
has "$ver" 'report-PAY-1.*GO'    && ok "verdict GO extracted"    || bad "verdict go" "$ver"
has "$ver" 'report-PAY-2.*NO-GO' && ok "verdict NO-GO extracted" || bad "verdict nogo" "$ver"

# --- summary: Wallet should rank top (most signal) with recurring categories ---
sum="$($QH summary "$docs")"
has "$sum" 'Wallet'                        && ok "summary lists Wallet"                      || bad "summary wallet" "$sum"
has "$sum" 'Wallet.*blocker'               && ok "summary rolls up max severity = blocker"  || bad "summary sev" "$sum"
has "$sum" 'missing edge case|thin regression' && ok "summary surfaces recurring categories" || bad "summary cats" "$sum"
# Wallet (2 bugs) should appear before Nova (0 bugs) in the frequency-sorted body
wl=$(printf '%s\n' "$sum" | grep -n 'Wallet' | head -1 | cut -d: -f1)
nv=$(printf '%s\n' "$sum" | grep -n 'Nova'   | head -1 | cut -d: -f1)
[ -n "$wl" ] && [ -n "$nv" ] && [ "$wl" -lt "$nv" ] && ok "summary ranks Wallet above Nova by frequency" || bad "summary rank" "wallet@$wl nova@$nv"

# --- empty / missing ---
mkdir -p "$tmp/empty"
e="$($QH bugs "$tmp/empty")"; [ -z "$e" ] && ok "empty docs dir -> no bugs" || bad "empty" "$e"
"$QH" bugs "$tmp/nope" >/dev/null 2>&1; [ "$?" = "1" ] && ok "missing docs dir -> exit 1" || bad "missing dir" "expected 1"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
