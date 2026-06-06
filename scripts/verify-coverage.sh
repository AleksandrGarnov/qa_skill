#!/usr/bin/env bash
# Coverage cross-check between the APPROVED checklist manifest and the test report.
# Two STRUCTURAL guarantees (set membership on item IDs — NOT a semantic check of whether
# a 'pass' is truthful; that stays the step-9 self-audit + an independent reviewer):
#   1. No skipped items — every item ID in the frozen manifest has a result row in the report.
#   2. Journey-rooted — every manifest item traces to a user journey defined in the manifest,
#      and at least one journey exists (a checklist built from code concerns has no journeys).
#
# Usage: verify-coverage.sh <manifest.md> <report.md>
# Output: COVERAGE-OK (exit 0) or a list of violations (exit 1).
set -uo pipefail

man="${1:?usage: verify-coverage.sh <manifest.md> <report.md>}"
rep="${2:?usage: verify-coverage.sh <manifest.md> <report.md>}"
[ -f "$man" ] || { echo "MANIFEST-MISSING: $man"; exit 1; }
[ -f "$rep" ] || { echo "REPORT-MISSING: $rep"; exit 1; }

viol=0
fail() { echo "FAIL: $*"; viol=$((viol+1)); }

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Extract column 1 (id) of the data rows of a named ## section's table.
# Skips the separator row and the first (header) row; trims whitespace.
col1_of_section() {
  awk -v sec="$1" '
    $0 ~ "^## " sec {insec=1; seen=0; next}
    insec && /^## / {insec=0}
    insec && /^\|/ {
      body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body)
      split(body, f, "|"); id=f[1]; gsub(/[[:space:]]/,"",id)
      if (id ~ /^:?-+:?$/) next        # separator row
      if (!seen) { seen=1; next }       # header row
      if (id != "") print id
    }
  ' "$2"
}

# --- journeys defined in the manifest (## Journeys, col1 = J id) ---
col1_of_section "Journeys" "$man" | sort -u > "$tmp/journeys"
njourneys=$(grep -c . "$tmp/journeys" 2>/dev/null || true)
[ "${njourneys:-0}" -gt 0 ] || fail "manifest defines no user journeys (## Journeys empty) — the checklist must be journey-rooted, not built from code concerns"

# --- manifest items (## Items: ID + Journey columns located by HEADER, robust to extra columns) ---
awk '
  /^## Items/ {insec=1; seen=0; idc=0; jc=0; next}
  insec && /^## / {insec=0}
  insec && /^\|/ {
    body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body)
    n=split(body, f, "|")
    c1=f[1]; gsub(/[[:space:]]/,"",c1)
    if (c1 ~ /^:?-+:?$/) next                       # separator row
    if (!seen) {                                    # header row -> locate columns
      seen=1
      for (i=1;i<=n;i++){ h=tolower(f[i]); if(index(h,"journey"))jc=i; if(index(h,"id")&&!idc)idc=i }
      if (!idc) idc=1
      if (!jc)  jc=2
      next
    }
    id=f[idc]; jr=f[jc]
    gsub(/[[:space:]]/,"",id); gsub(/[[:space:]]/,"",jr)
    if (id != "") print id "\t" jr
  }
' "$man" > "$tmp/items"

cut -f1 "$tmp/items" | sort -u > "$tmp/approved"
napproved=$(grep -c . "$tmp/approved" 2>/dev/null || true)
[ "${napproved:-0}" -gt 0 ] || fail "manifest has no checklist items (## Items empty)"

# every item must carry a journey ref that exists in ## Journeys
while IFS=$'\t' read -r id jr; do
  [ -n "$id" ] || continue
  if [ -z "$jr" ]; then
    fail "manifest item $id has no journey ref — every item must trace to a user journey (J#)"
  elif ! grep -qxF "$jr" "$tmp/journeys"; then
    fail "manifest item $id references journey $jr, which is not defined in ## Journeys"
  fi
done < "$tmp/items"

# --- report results: ID -> terminal status (## Checklist results; columns by header) ---
awk '
  /^## Checklist results/ {insec=1; seen=0; idc=0; rc=0; next}
  insec && /^## / {insec=0}
  insec && /^\|/ {
    body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body)
    n=split(body, f, "|")
    c1=f[1]; gsub(/[[:space:]]/,"",c1)
    if (c1 ~ /^:?-+:?$/) next
    if (!seen) {
      seen=1
      for (i=1;i<=n;i++){ h=tolower(f[i]); if(index(h,"result"))rc=i; if((index(h,"id")||index(h,"#"))&&!idc)idc=i }
      if (!idc) idc=1
      next
    }
    id=f[idc]; gsub(/[[:space:]]/,"",id)
    res=tolower(f[rc]); gsub(/^[[:space:]]+|[[:space:]]+$/,"",res)
    if (id!="") print id "\t" res
  }
' "$rep" > "$tmp/results"
cut -f1 "$tmp/results" | sort -u > "$tmp/accounted"

# missing = approved \ accounted  -> a skipped item (absent row)
missing="$(comm -23 "$tmp/approved" "$tmp/accounted")"
if [ -n "$missing" ]; then
  while IFS= read -r m; do
    [ -n "$m" ] && fail "approved item $m has no result row in the report — a skipped checklist item"
  done <<< "$missing"
fi

# present-but-not-executed -> also a skip (guideline 3: no item skipped under any pretext).
# A real bucket (pass/fail/blocked/N-A) is fine; 'not executed' / empty is not.
while IFS= read -r aid; do
  [ -n "$aid" ] || continue
  st="$(awk -F'\t' -v k="$aid" '$1==k{print $2; exit}' "$tmp/results")"
  case "$st" in
    ""|*"not executed"*|"notexecuted") grep -qxF "$aid" "$tmp/accounted" && fail "approved item $aid is 'not executed'/empty — a skipped item (run it, or 'blocked' with a documented attempt)";;
  esac
done < "$tmp/approved"

# drift = accounted \ approved  -> added during the run; informational, not a failure
drift="$(comm -13 "$tmp/approved" "$tmp/accounted")"
if [ -n "$drift" ]; then
  echo "NOTE: report has result rows not in the approved manifest (added during the run): $(echo $drift | tr '\n' ' ')"
fi

if [ "$viol" -eq 0 ]; then
  echo "COVERAGE-OK: all ${napproved:-0} approved item(s) accounted for; every item journey-rooted across ${njourneys:-0} journey(s)"
  exit 0
fi
echo "---"
echo "$viol coverage violation(s) — the report does not account for the approved, journey-rooted checklist"
exit 1
