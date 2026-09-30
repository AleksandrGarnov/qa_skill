#!/usr/bin/env bash
# Self-contained tests for changed-surfaces.sh (surface enumeration from a unified diff).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CS="$SCRIPT_DIR/changed-surfaces.sh"
pass=0; fail=0
ok()   { echo "ok   - $1"; pass=$((pass+1)); }
bad()  { echo "FAIL - $1"; echo "       $2"; fail=$((fail+1)); }
has()  { printf '%s\n' "$1" | grep -qxF "$2"; }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/d.diff" <<'DIFF'
diff --git a/app/Services/Wallet.php b/app/Services/Wallet.php
--- a/app/Services/Wallet.php
+++ b/app/Services/Wallet.php
@@ -10,3 +10,5 @@ public function amountFloat()
-    return $this->amount;
+    return $this->wallet?->amount;
@@ -30,2 +32,3 @@
+    $flag = true;
diff --git a/app/Nova/DepositResource.php b/app/Nova/DepositResource.php
--- a/app/Nova/DepositResource.php
+++ b/app/Nova/DepositResource.php
@@ -5,3 +5,4 @@ public function fields(Request $request)
+    BelongsTo::make('Currency','wallet');
diff --git a/docs/readme.md b/docs/readme.md
--- a/docs/readme.md
+++ b/docs/readme.md
@@ -1 +1,2 @@ Heading
+more docs
diff --git a/tests/WalletTest.php b/tests/WalletTest.php
--- a/tests/WalletTest.php
+++ b/tests/WalletTest.php
@@ -1 +1,2 @@ testAmount
+$this->assertNull($x);
diff --git a/package-lock.json b/package-lock.json
--- a/package-lock.json
+++ b/package-lock.json
@@ -1 +1,2 @@
+"dep": "1.0.1"
DIFF

out="$($CS --diff "$tmp/d.diff")"
n="$(printf '%s\n' "$out" | grep -c .)"

[ "$n" = "3" ] && ok "exactly 3 behaviour surfaces (noise filtered)" || bad "surface count" "expected 3, got $n: [$out]"
has "$out" 'app/Services/Wallet.php::public function amountFloat()' && ok "symbol surface (named hunk context)" || bad "symbol surface" "$out"
has "$out" 'app/Services/Wallet.php' && ok "bare file surface (context-less hunk)" || bad "bare surface" "$out"
has "$out" 'app/Nova/DepositResource.php::public function fields(Request $request)' && ok "second file symbol surface" || bad "nova surface" "$out"
printf '%s\n' "$out" | grep -q 'readme.md' && bad "docs excluded" "$out" || ok "docs (.md) filtered out"
printf '%s\n' "$out" | grep -q 'WalletTest.php' && bad "tests excluded" "$out" || ok "test file filtered out"
printf '%s\n' "$out" | grep -q 'package-lock.json' && bad "lockfile excluded" "$out" || ok "lockfile filtered out"

# A diff that changes ONLY noise -> empty surface list (nothing behaviour to test)
cat > "$tmp/noise.diff" <<'DIFF'
diff --git a/README.md b/README.md
--- a/README.md
+++ b/README.md
@@ -1 +1,2 @@
+doc
DIFF
out2="$($CS --diff "$tmp/noise.diff")"
[ -z "$out2" ] && ok "noise-only diff -> no surfaces" || bad "noise-only" "[$out2]"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
