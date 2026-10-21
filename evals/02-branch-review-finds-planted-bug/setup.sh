# Build main + feature history behind a local bare "origin", as branch-diff.sh diffs against origin/<base>.
set -e
G="git -c user.email=eval@example.com -c user.name=eval"
remote="$(mktemp -d)/origin.git"
git init -q --bare "$remote"
git init -q -b main
$G add -A
$G commit -qm "LM-2: base"
git remote add origin "$remote"
git push -q origin main
git checkout -q -b feature/LM-2-discount
cat > discount.py <<'PY'
def apply_discount(price_cents: int, percent: int) -> int:
    """Return the price after a percentage discount, in cents."""
    return price_cents - price_cents * percent // 100
PY
$G commit -qam "LM-2: apply percentage discount"
git push -q -u origin feature/LM-2-discount
git remote set-head origin main
