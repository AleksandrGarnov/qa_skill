#!/usr/bin/env bash
# Self-contained tests for blast-radius.sh (reverse-dependency enumeration of changed symbols).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BR="$SCRIPT_DIR/blast-radius.sh"
pass=0; fail=0
ok()  { echo "ok   - $1"; pass=$((pass+1)); }
bad() { echo "FAIL - $1"; echo "       $2"; fail=$((fail+1)); }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
root="$tmp/repo"
mkdir -p "$root/app" "$root/tests"
printf 'public function amountFloat() { return $this->amount; }\n' > "$root/app/Wallet.php"
printf 'echo $wallet->amountFloat();\n'                            > "$root/app/Cart.php"
printf 'total += order.amountFloat();\n'                           > "$root/app/Order.php"
printf 'assertEquals(10, $w->amountFloat());\n'                    > "$root/tests/WalletTest.php"

cat > "$tmp/surfaces.txt" <<'TXT'
app/Wallet.php::public function amountFloat()
app/Wallet.php::public function orphanedHelper()
app/Config.php
TXT

out="$($BR --surfaces "$tmp/surfaces.txt" --root "$root" 2>/dev/null)"

printf '%s\n' "$out" | grep -q 'app/Cart.php' && ok "finds caller Cart.php" || bad "Cart caller" "$out"
printf '%s\n' "$out" | grep -q 'app/Order.php' && ok "finds caller Order.php" || bad "Order caller" "$out"
printf '%s\n' "$out" | grep -Eq 'amountFloat.*WalletTest' && bad "test caller excluded" "$out" || ok "test file excluded from callers"
amline="$(printf '%s\n' "$out" | grep '^amountFloat')"; amcallers="${amline#*<-}"
printf '%s' "$amcallers" | grep -q 'Wallet' && bad "defining file excluded" "callers=[$amcallers]" || ok "defining file not listed as its own caller"
printf '%s\n' "$out" | grep -q 'orphanedHelper.*no external callers' && ok "symbol with no callers reported" || bad "orphan symbol" "$out"
# bare file surface (Config.php, no ::) is skipped — no symbol to trace
printf '%s\n' "$out" | grep -q 'Config.php' && bad "bare file skipped" "$out" || ok "bare file surface skipped (no symbol)"

# All-bare surfaces -> explicit 'no named symbols' note
printf 'app/A.php\napp/B.php\n' > "$tmp/bare.txt"
out2="$($BR --surfaces "$tmp/bare.txt" --root "$root" 2>/dev/null)"
printf '%s\n' "$out2" | grep -q 'no named symbols' && ok "all-bare surfaces -> explicit note" || bad "bare note" "$out2"

# Bad usage -> exit 2
"$BR" --surfaces "$tmp/nope.txt" >/dev/null 2>&1; [ "$?" = "2" ] && ok "missing surfaces file -> exit 2" || bad "usage" "expected 2"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
