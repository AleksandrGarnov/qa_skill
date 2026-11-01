#!/usr/bin/env bash
# Self-contained tests for test-smells.sh (lexical test-smell hints over changed test files).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TS="$SCRIPT_DIR/test-smells.sh"
pass=0; fail=0
ok()   { echo "ok   - $1"; pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; echo "       $2"; fail=$((fail+1)); }
hit()  { printf '%s\n' "$1" | grep -qF "$2"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/src" "$tmp/tests"

cat > "$tmp/src/cart.test.ts" <<'TS'
import { total } from './cart';

describe('cart', () => {
  it.only('sums items', () => {
    expect(total([1, 2])).toBe(3);
  });

  it('applies discount', () => {
    const t = total([10], 0.5);
    console.log(t);
  });

  test.skip('legacy rounding', () => {
    expect(1).toBe(1);
  });

  it('loads remote price', async () => {
    expect(fetchPrice()).resolves.toBe(5);
  });

  it('waits for debounce', async () => {
    await page.waitForTimeout(500);
    expect(await price()).toBe(5);
  });

  it('awaited resolves is fine', async () => {
    await expect(fetchPrice()).resolves.toBe(5);
  });

  it('stamps time', () => {
    const now = Date.now();
    expect(stamp(now)).toBeDefined();
  });
});
TS

cat > "$tmp/tests/test_wallet.py" <<'PY'
import time
import pytest


def test_deposit_credits_balance():
    w = Wallet()
    w.deposit(10)
    assert w.balance == 10


def test_withdraw_runs():
    w = Wallet()
    w.withdraw(5)


@pytest.mark.skip(reason="flaky")
def test_refund():
    assert True


def test_retry_sleeps():
    time.sleep(2)
    with pytest.raises(ValueError):
        Wallet().withdraw(-1)


def test_helper_assert():
    self.assertEqual(1, 1)
PY

cat > "$tmp/src/cart.ts" <<'TS'
// production code — a sleep or Date.now() here is not a test smell
export const now = () => Date.now();
setTimeout(() => {}, 10);
TS

cat > "$tmp/tests/clean.spec.ts" <<'TS'
it('is clean', () => {
  expect(add(1, 2)).toBe(3);
});
// it.only('commented out focus is not a smell', () => {});
TS

out="$($TS "$tmp/src/cart.test.ts" "$tmp/tests/test_wallet.py" "$tmp/src/cart.ts" "$tmp/tests/clean.spec.ts" "$tmp/missing.test.ts")"
rc=$?
T="$tmp/src/cart.test.ts"; P="$tmp/tests/test_wallet.py"

[ "$rc" = "0" ] && ok "exit 0 even with smells (signal, not a gate)" || bad "exit code" "got $rc"
hit "$out" "$T:4 | focused |"                && ok "it.only → focused"                      || bad "focused" "$out"
hit "$out" "$T:8 | no-assertion |"           && ok "JS callback without expect → no-assertion" || bad "js no-assertion" "$out"
hit "$out" "$T:13 | skipped |"               && ok "test.skip → skipped"                    || bad "js skipped" "$out"
hit "$out" "$T:18 | unawaited-assert |"      && ok "un-awaited .resolves → unawaited-assert" || bad "unawaited" "$out"
hit "$out" "$T:22 | sleepy |"                && ok "waitForTimeout → sleepy"                || bad "js sleepy" "$out"
hit "$out" "$T:31 | nondeterministic |"      && ok "Date.now → nondeterministic"            || bad "nondeterministic" "$out"
hit "$out" "$P:11 | no-assertion |"          && ok "Python test without assert → no-assertion" || bad "py no-assertion" "$out"
hit "$out" "$P:16 | skipped |"               && ok "@pytest.mark.skip → skipped"            || bad "py skipped" "$out"
hit "$out" "$P:22 | sleepy |"                && ok "time.sleep → sleepy"                    || bad "py sleepy" "$out"

hit "$out" "$T:26 | unawaited-assert" && bad "awaited .resolves flagged" "$out" || ok "await expect(...).resolves is not flagged"
hit "$out" "$T:4 | no-assertion"      && bad "asserting test flagged"   "$out" || ok "a test with expect() is not no-assertion"
hit "$out" "$P:5 | no-assertion"      && bad "py asserting test flagged" "$out" || ok "a Python test with assert is not no-assertion"
hit "$out" "$P:21 | no-assertion"     && bad "pytest.raises not counted" "$out" || ok "pytest.raises counts as an assertion"
hit "$out" "$P:27 | no-assertion"     && bad "self.assertEqual not counted" "$out" || ok "self.assertX counts as an assertion"
hit "$out" "$tmp/src/cart.ts:"        && bad "production file scanned" "$out" || ok "non-test files are ignored"
hit "$out" "clean.spec.ts:"           && bad "clean spec flagged"      "$out" || ok "clean spec and commented-out .only produce nothing"
hit "$out" "smells: 9 in 3 test file(s)" && ok "summary counts hits and test files (missing path skipped)" || bad "summary" "$(printf '%s\n' "$out" | tail -1)"

printf "it.only('focused, no assert', () => {\n  doThing();\n});\n" > "$tmp/tests/focus.test.js"
fo="$($TS "$tmp/tests/focus.test.js")"
hit "$fo" "focus.test.js:1 | no-assertion |" && ok "a focused test is still checked for assertions" || bad "focused no-assertion" "$fo"

$TS >/dev/null 2>&1; [ "$?" = "2" ] && ok "no arguments → usage error (exit 2)" || bad "usage" "expected exit 2"

echo
echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
