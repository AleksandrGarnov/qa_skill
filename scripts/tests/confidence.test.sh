#!/usr/bin/env bash
# Self-contained tests for confidence.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CF="$SCRIPT_DIR/confidence.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
assert_contains() {
  local desc="$1" needle="$2" hay="$3"
  case "$hay" in *"$needle"*) echo "ok   - $desc"; pass=$((pass+1));;
    *) echo "FAIL - $desc"; echo "       expected to contain: [$needle]"; echo "       in: [$hay]"; fail=$((fail+1));; esac
}

tmp="$(mktemp -d)"

# --- streak counting ---
f="$tmp/c1.md"
"$CF" record "$f" "wallet" go RUN1 2026-01-01 >/dev/null
assert_eq "one GO -> streak 1" "1" "$("$CF" streak "$f" "wallet")"

"$CF" record "$f" "wallet" go RUN2 2026-01-02 >/dev/null
"$CF" record "$f" "wallet" go RUN3 2026-01-03 >/dev/null
assert_eq "three GO -> streak 3" "3" "$("$CF" streak "$f" "wallet")"

# an escape resets the streak to 0
"$CF" record "$f" "wallet" escape RUN4 2026-01-04 >/dev/null
assert_eq "GO,GO,GO,ESCAPE -> streak 0" "0" "$("$CF" streak "$f" "wallet")"

# GOs after the escape count fresh
"$CF" record "$f" "wallet" go RUN5 2026-01-05 >/dev/null
"$CF" record "$f" "wallet" go RUN6 2026-01-06 >/dev/null
assert_eq "two GO after escape -> streak 2" "2" "$("$CF" streak "$f" "wallet")"

# --- per-component isolation ---
f2="$tmp/c2.md"
"$CF" record "$f2" "bonus" go A1 >/dev/null
"$CF" record "$f2" "payments" go B1 >/dev/null
"$CF" record "$f2" "bonus" go A2 >/dev/null
"$CF" record "$f2" "bonus" go A3 >/dev/null
assert_eq "component 'bonus' isolated -> streak 3" "3" "$("$CF" streak "$f2" "bonus")"
assert_eq "component 'payments' isolated -> streak 1" "1" "$("$CF" streak "$f2" "payments")"

# case-insensitive component match
assert_eq "component match is case-insensitive" "3" "$("$CF" streak "$f2" "BONUS")"

# unknown component -> streak 0
assert_eq "unknown component -> streak 0" "0" "$("$CF" streak "$f2" "nope")"

# --- suggest (threshold) ---
f3="$tmp/c3.md"
for i in 1 2 3 4; do "$CF" record "$f3" "frontend" go "R$i" >/dev/null; done
assert_contains "below threshold -> KEEP-PRESENCE" "KEEP-PRESENCE" "$("$CF" suggest "$f3" "frontend" 5)"
"$CF" record "$f3" "frontend" go R5 >/dev/null
assert_contains "at threshold -> READY-FOR-PRESENCE-REDUCTION" "READY-FOR-PRESENCE-REDUCTION" "$("$CF" suggest "$f3" "frontend" 5)"

# default threshold via env
assert_contains "default threshold honoured (env=3)" "READY" "$(CONFIDENCE_THRESHOLD=3 "$CF" suggest "$f3" "frontend")"

# --- list / NONE ---
assert_eq "empty ledger -> NONE" "NONE" "$("$CF" list "$tmp/missing.md")"
out="$("$CF" list "$f3")"; assert_contains "list prints data rows" "| frontend | GO |" "$out"

# --- validation ---
rc() { "$@" >/dev/null 2>&1; echo "$?"; }
assert_eq "invalid outcome -> exit 2" "2" "$(rc "$CF" record "$tmp/c4.md" "x" maybe)"
assert_eq "missing component on record -> exit 2" "2" "$(rc "$CF" record "$tmp/c4.md" "")"
assert_eq "non-numeric threshold -> exit 2" "2" "$(rc "$CF" suggest "$f3" "frontend" five)"

# pipes in component don't break the table row
"$CF" record "$tmp/c5.md" "a|b" go >/dev/null
assert_contains "pipes sanitized in component" "| a/b | GO |" "$("$CF" list "$tmp/c5.md")"

echo "---"
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
