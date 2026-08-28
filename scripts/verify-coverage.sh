#!/usr/bin/env bash
# Coverage cross-check between the APPROVED checklist manifest and the test report.
# Two STRUCTURAL guarantees (set membership on item IDs — NOT a semantic check of whether
# a 'pass' is truthful; that stays the step-9 self-audit + an independent reviewer):
#   1. No skipped items — every item ID in the frozen manifest has a result row in the report.
#   2. Journey-rooted — every manifest item traces to a user journey defined in the manifest,
#      and at least one journey exists (a checklist built from code concerns has no journeys).
#   3. Oracle-independent — the ## Items table carries an "Expected source" column and every item
#      names an expected value sourced from something OTHER than the implementation under test
#      (a spec/hand-calc/invariant/reference/historical value, or a metamorphic rule). Blocks the
#      "the code is its own oracle" trap that a green observation otherwise hides. See test-oracle.md.
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
      for (i=1;i<=n;i++){ h=tolower(f[i]); if(index(h,"journey"))jc=i; if(index(h,"id")&&!idc)idc=i; if(index(h,"source")&&!sc)sc=i }
      if (!idc) idc=1
      if (!jc)  jc=2
      next
    }
    id=f[idc]; jr=f[jc]
    gsub(/[[:space:]]/,"",id); gsub(/[[:space:]]/,"",jr)
    src=(sc? f[sc] : ""); gsub(/^[[:space:]]+|[[:space:]]+$/,"",src); gsub(/\t/," ",src)
    if (id != "") print id "\t" jr "\t" src
  }
' "$man" > "$tmp/items"

# Does the ## Items table declare an "Expected source" (oracle) column at all?
items_header="$(awk '/^## Items/{f=1;next} f&&/^\|/{print;exit}' "$man")"
has_srccol=0
printf '%s' "$items_header" | grep -qiE 'expected source|[^a-z]source[^a-z]|source *\|' && has_srccol=1

cut -f1 "$tmp/items" | sort -u > "$tmp/approved"
napproved=$(grep -c . "$tmp/approved" 2>/dev/null || true)
[ "${napproved:-0}" -gt 0 ] || fail "manifest has no checklist items (## Items empty)"

# The oracle column must exist — every check needs an expected value sourced independently of the code.
[ "$has_srccol" -eq 1 ] || fail "manifest ## Items has no 'Expected source' column — every check needs an oracle independent of the implementation (spec/hand-calc/invariant/reference/historical, or a metamorphic rule). See references/test-oracle.md"

# an expected source that is really 'the code itself' — the code can't be its own oracle
impl_oracle='whatever the code|the code returns?|code returns?|returned by (the )?(code|impl|implementation)|implementation under test|^impl(ementation)?$|same as (the )?(code|impl)|dev said|what the dev|because the code'

# every item must carry a journey ref that exists in ## Journeys, AND an independent oracle
while IFS=$'\t' read -r id jr src; do
  [ -n "$id" ] || continue
  if [ -z "$jr" ]; then
    fail "manifest item $id has no journey ref — every item must trace to a user journey (J#)"
  elif ! grep -qxF "$jr" "$tmp/journeys"; then
    fail "manifest item $id references journey $jr, which is not defined in ## Journeys"
  fi
  if [ "$has_srccol" -eq 1 ]; then
    case "$src" in
      ""|"<"*">") fail "manifest item $id has no Expected source — derive the expected value independently of the implementation (spec/hand-calc/invariant/reference/historical), or state a metamorphic rule (references/test-oracle.md)";;
      *) printf '%s' "$src" | grep -qiE "$impl_oracle" && fail "manifest item $id uses the implementation as its own oracle ('$src') — a green check would only prove the code agrees with itself; derive expected from an independent source";;
    esac
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

# present-but-not-a-terminal-bucket -> also a skip (guideline 3: no item skipped under any pretext).
# WHITELIST the legitimate terminal buckets (pass/fail/blocked/flaky/N/A) — anything else is a
# disguised skip. A blacklist of just 'not executed' let 'skipped'/'deferred'/'wontfix'/'later'
# sail through as "done"; the guarantee is only real if the allowed set is closed, not the denied set.
while IFS= read -r aid; do
  [ -n "$aid" ] || continue
  grep -qxF "$aid" "$tmp/accounted" || continue     # absent rows already failed above
  st="$(awk -F'\t' -v k="$aid" '$1==k{print $2; exit}' "$tmp/results")"
  case "$st" in
    pass*|fail*|blocked*|flaky*|n/a*|na|n-a*) : ;;   # valid terminal bucket
    ""|*"not executed"*|"notexecuted")
      fail "approved item $aid is 'not executed'/empty — a skipped item (run it, or 'blocked' with a documented attempt)";;
    *)
      fail "approved item $aid has status '$st' — not a recognized terminal bucket (pass/fail/blocked/flaky/N/A); a disguised skip (skipped/deferred/wontfix/…) does not satisfy coverage";;
  esac
done < "$tmp/approved"

# drift = accounted \ approved  -> added during the run; informational, not a failure
drift="$(comm -13 "$tmp/approved" "$tmp/accounted")"
if [ -n "$drift" ]; then
  echo "NOTE: report has result rows not in the approved manifest (added during the run): $(echo $drift | tr '\n' ' ')"
fi

if [ "$viol" -eq 0 ]; then
  echo "COVERAGE-OK: all ${napproved:-0} approved item(s) accounted for; every item journey-rooted across ${njourneys:-0} journey(s); each carries an oracle independent of the implementation"
  exit 0
fi
echo "---"
echo "$viol coverage violation(s) — the report does not account for the approved, journey-rooted checklist"
exit 1
