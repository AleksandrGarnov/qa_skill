#!/usr/bin/env bash
# Structural completeness check for a FILLED test report (per test-report-template.md).
# Fails CLOSED if the per-item execution record or a required gate line is incomplete —
# so a rushed or hand-waved report can't reach a verdict. It checks STRUCTURE
# (nothing left blank / placeholder), NOT truthfulness — that's the step-9 self-audit.
#
# Usage: verify-report.sh <report.md>
# Output: REPORT-OK (exit 0) or a list of violations (exit 1).
set -uo pipefail

f="${1:?usage: verify-report.sh <report.md>}"
[ -f "$f" ] || { echo "REPORT-MISSING: $f"; exit 1; }

viol=0
fail() { echo "FAIL: $*"; viol=$((viol+1)); }

# 1) Prior-test basis gate line is filled (a real FRESH / RE-TEST value, not a blank/placeholder).
pt="$(grep -niE 'prior-test basis' "$f" | head -1 | cut -d: -f1)"
if [ -z "$pt" ]; then
  fail "Prior-test basis line missing"
else
  ctx="$(sed -n "${pt},$((pt+5))p" "$f")"
  printf '%s' "$ctx" | grep -qiE 'FRESH|RE-TEST' || fail "Prior-test basis not filled (no FRESH / RE-TEST value)"
fi

# 2) Checklist results table: every data row must have a complete execution record —
#    no empty cell, no unfilled <placeholder>.
rows="$(awk '
  /^## Checklist results/ {insec=1; next}
  insec && /^## / {insec=0}
  insec && /^\|[[:space:]]*[0-9]/ {print}
' "$f")"

if [ -z "$rows" ]; then
  fail "Checklist results table has no data rows"
else
  rownum=0
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    rownum=$((rownum+1))
    body="${line#|}"; body="${body%|}"
    IFS='|' read -r -a cells <<< "$body"
    ci=0
    for c in "${cells[@]}"; do
      ci=$((ci+1))
      c="$(printf '%s' "$c" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      if [ -z "$c" ]; then fail "row $rownum: cell $ci is empty"; continue; fi
      case "$c" in
        '<'*'>') fail "row $rownum: cell $ci is an unfilled placeholder ($c)";;
      esac
    done
  done <<< "$rows"
fi

# 3) Every Found-bug block must carry EXACT repro steps (>=1 real numbered step, not a placeholder).
missing_repro="$(awk '
  /^## Found bugs/ {insec=1; next}
  insec && /^## / {flush(); insec=0}
  insec && /^### / {flush(); hdr=$0; sub(/^### +/,"",hdr); inblock=1; have=0; next}
  insec && inblock {
    if ($0 ~ /^[[:space:]]*[0-9][.)][[:space:]]/) {
      rest=$0; sub(/^[[:space:]]*[0-9][.)][[:space:]]+/,"",rest)
      gsub(/^[[:space:]]+/,"",rest); gsub(/[[:space:]]+$/,"",rest)
      if (rest != "" && rest !~ /^<.*>$/) have=1
    }
  }
  END {flush()}
  function flush() {if (inblock && hdr!="" && !have) print hdr; inblock=0; hdr=""; have=0}
' "$f")"
if [ -n "$missing_repro" ]; then
  while IFS= read -r b; do [ -n "$b" ] && fail "bug has no exact repro steps: $b"; done <<< "$missing_repro"
fi

# 4) A clean ✅ GO must not coexist with any 'not executed' approved item.
verdict_line="$(grep -iE '^\*\*Verdict:' "$f" | head -1)"
if printf '%s' "$verdict_line" | grep -q 'GO' \
   && ! printf '%s' "$verdict_line" | grep -qiE 'NO-GO|WITH DEFERRALS|exploratory'; then
  notrun="$(awk '
    /^## Checklist results/ {insec=1; next}
    insec && /^## / {insec=0}
    insec && /^\|[[:space:]]*[0-9]/ && tolower($0) ~ /not executed/ {c++}
    END {print c+0}
  ' "$f")"
  if [ "$notrun" -gt 0 ]; then
    fail "clean GO but $notrun checklist item(s) are 'not executed' — defer them with a reason (GO-with-deferrals) or run them; no clean GO over an incomplete run"
  fi
fi

if [ "$viol" -eq 0 ]; then
  echo "REPORT-OK: execution records and gate lines are complete"
  exit 0
fi
echo "---"
echo "$viol violation(s) — report incomplete, verdict is blocked until every execution record, gate line, and bug repro is filled"
exit 1
