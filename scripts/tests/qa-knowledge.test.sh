#!/usr/bin/env bash
# Self-contained tests for qa-knowledge.sh (per-component failure-mode profiles).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QK="$SCRIPT_DIR/qa-knowledge.sh"
pass=0; fail=0
ok()  { echo "ok   - $1"; pass=$((pass+1)); }
bad() { echo "FAIL - $1"; echo "       $2"; fail=$((fail+1)); }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
f="$tmp/qa-knowledge.md"

# list on missing -> NONE
[ "$($QK list "$f")" = "NONE" ] && ok "list missing -> NONE" || bad "list missing" "$($QK list "$f")"

# add two rows
$QK add "$f" "Wallet" "concurrency / in-the-window" "state-transition all-transitions" 3 "PAY-ESC-01" >/dev/null
$QK add "$f" "Nova lens" "null render 500" "boundary (null!=0)" 2 "PAY-1-BUG-02" >/dev/null
rows="$($QK list "$f")"
[ "$(printf '%s\n' "$rows" | grep -c .)" = "2" ] && ok "two rows stored" || bad "row count" "$rows"
printf '%s\n' "$rows" | grep -q 'Wallet.*concurrency.*state-transition' && ok "row content intact" || bad "content" "$rows"

# match on component keyword
m="$($QK match "$f" wallet)"
printf '%s\n' "$m" | grep -q 'Wallet' && ok "match 'wallet' finds Wallet row" || bad "match wallet" "$m"
printf '%s\n' "$m" | grep -q 'Nova' && bad "match should not include Nova" "$m" || ok "match 'wallet' excludes Nova"

# match is component-only: a keyword that only appears in the risk/technique column must NOT match
mb="$($QK match "$f" boundary)"
[ "$mb" = "NONE" ] && ok "keyword only in technique col -> no component match (NONE)" || bad "col-scope" "$mb"

# multi-keyword
mm="$($QK match "$f" wallet nova)"
[ "$(printf '%s\n' "$mm" | grep -c .)" = "2" ] && ok "multi-keyword matches both components" || bad "multi" "$mm"

# no match -> NONE
[ "$($QK match "$f" doesnotexist)" = "NONE" ] && ok "no match -> NONE" || bad "nomatch" "$($QK match "$f" doesnotexist)"

# pipe sanitization: a value with | stays one row
$QK add "$f" "Auth|Session" "token desync" "decision-table" 1 "x" >/dev/null
[ "$(printf '%s\n' "$($QK list "$f")" | grep -c .)" = "3" ] && ok "pipe in value stays one row" || bad "pipe" "$($QK list "$f")"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
