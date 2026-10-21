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

[ "$n" = "4" ] && ok "exactly 3 behaviour surfaces + the cold-start surface (lockfile bump)" || bad "surface count" "expected 4, got $n: [$out]"
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

# --- Runtime/infra changes: migrations are behaviour; infra/dependency changes demand a cold-start smoke ---
cat > "$tmp/mig.diff" <<'DIFF'
diff --git a/database/migrations/2026_10_22_000000_add_status_to_orders.php b/database/migrations/2026_10_22_000000_add_status_to_orders.php
--- a/database/migrations/2026_10_22_000000_add_status_to_orders.php
+++ b/database/migrations/2026_10_22_000000_add_status_to_orders.php
@@ -10,3 +10,4 @@ public function up()
+        $table->string('status')->default('new');
DIFF
out3="$($CS --diff "$tmp/mig.diff")"
printf '%s\n' "$out3" | grep -q 'add_status_to_orders.php' && ok "migration file is a surface (not noise)" || bad "migration surface" "[$out3]"
has "$out3" '@runtime::cold-start' && ok "migration change -> @runtime::cold-start surface" || bad "cold-start on migration" "[$out3]"

for f in Dockerfile docker-compose.yml composer.json composer.lock package-lock.json config/queue.php \
         deploy/k8s/app.yaml helm/values.yaml .env.example docker/nginx/default.conf requirements.txt; do
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1,2 @@\n+x\n' "$f" "$f" "$f" "$f" > "$tmp/rt.diff"
  o="$($CS --diff "$tmp/rt.diff")"
  has "$o" '@runtime::cold-start' && ok "runtime trigger: $f" || bad "runtime trigger: $f" "[$o]"
done

# Deleting a runtime file still triggers (path comes from the diff --git header, not just +++)
printf 'diff --git a/Dockerfile b/Dockerfile\ndeleted file mode 100644\n--- a/Dockerfile\n+++ /dev/null\n@@ -1 +0,0 @@\n-FROM php\n' > "$tmp/del.diff"
has "$($CS --diff "$tmp/del.diff")" '@runtime::cold-start' && ok "deleted Dockerfile -> cold-start" || bad "deleted Dockerfile" ""

# Plain code / docs / CI config / tests do NOT trigger it (no inflation of the required set)
for f in app/Services/Wallet.php README.md .github/workflows/ci.yml tests/Feature/FooTest.php src/i18n/en.json; do
  printf 'diff --git a/%s b/%s\n--- a/%s\n+++ b/%s\n@@ -1 +1,2 @@\n+x\n' "$f" "$f" "$f" "$f" > "$tmp/nrt.diff"
  o="$($CS --diff "$tmp/nrt.diff")"
  has "$o" '@runtime::cold-start' && bad "no cold-start for $f" "[$o]" || ok "no cold-start for $f"
done

# The existing mixed diff has a lockfile change -> it now also carries the cold-start surface
has "$out" '@runtime::cold-start' && ok "lockfile bump in the mixed diff -> cold-start" || bad "mixed diff cold-start" "[$out]"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
