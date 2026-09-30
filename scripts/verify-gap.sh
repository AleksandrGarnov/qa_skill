#!/usr/bin/env bash
# Test-Gap coverage gate — every CHANGED behaviour-surface must map to >=1 checklist item, or an
# explicit reasoned N/A. Fails CLOSED on an unmapped/uncovered surface, so a large diff cannot be
# "covered" by a handful of items ("5 checks for 2000 lines" is exactly the gap this closes).
#
# STRUCTURAL only (like the oracle/technique gates): it checks that the manifest's
# ## Changed-surface coverage table ACCOUNTS FOR every surface in the frozen list —
#   - each surface has a row, and
#   - that row names >=1 item that exists in ## Items, OR is marked N/A with a reason.
# Whether the named items TRULY exercise the surface is semantic — verified at the step-6.5 review,
# per this repo's split (gates check field completeness; prose/review checks meaning).
# Grounded in Test-Gap Analysis (Amann/Jürgens) and patch/diff coverage (diff-cover, Codecov patch).
#
# Usage: verify-gap.sh <manifest.md> <surfaces-file>
#   <surfaces-file> = output of changed-surfaces.sh, frozen at approval (one surface per line;
#                     blank lines and #-comments ignored).
# Output: GAP-OK (exit 0) or a list of violations (exit 1).
set -uo pipefail

man="${1:?usage: verify-gap.sh <manifest.md> <surfaces-file>}"
surf="${2:?usage: verify-gap.sh <manifest.md> <surfaces-file>}"
[ -f "$man" ] || { echo "MANIFEST-MISSING: $man"; exit 1; }
[ -f "$surf" ] || { echo "SURFACES-MISSING: $surf"; exit 1; }

# Localizable section heading (EN + RU default; override via env). Byte-safe: no Cyrillic char classes.
SECT_RE="${QA_RE_SURFACES:-Changed-surface coverage|Изменённые[^|]*поверхност|Test-Gap}"

viol=0; fail() { echo "FAIL: $*"; viol=$((viol+1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- required surfaces (skip blanks + #-comments), trimmed & de-duplicated ---
sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' "$surf" | grep -vE '^(#|$)' | sort -u > "$tmp/req"
nreq=$(grep -c . "$tmp/req" 2>/dev/null || true)
[ "${nreq:-0}" -gt 0 ] || { echo "GAP-OK: no behaviour-carrying surfaces changed (nothing to map)"; exit 0; }

# --- ## Items IDs (to reject dangling coverage refs) ---
awk '
  /^## Items/{ins=1;seen=0;next} ins&&/^## /{ins=0}
  ins&&/^\|/{ body=$0; sub(/^\|/,"",body); split(body,f,"|"); id=f[1]; gsub(/[[:space:]]/,"",id)
    if(id ~ /^:?-+:?$/)next; if(!seen){seen=1;next}; if(id!="")print id }
' "$man" | sort -u > "$tmp/items"

# --- the coverage section must exist at all (non-skippable, like the oracle column) ---
if ! awk -v R="$SECT_RE" '$0 ~ ("^## +(" R ")"){f=1} END{exit !f}' "$man"; then
  fail "manifest has no '## Changed-surface coverage' section — map every changed surface (changed-surfaces.sh) to >=1 item or a reasoned N/A (Test-Gap gate)"
  echo "---"; echo "$viol test-gap violation(s)"; exit 1
fi

# --- parse the coverage table: surface \t covered \t notes (columns located by header) ---
awk -v R="$SECT_RE" '
  $0 ~ ("^## +(" R ")"){ins=1;seen=0;sc=0;cc=0;nc=0;next}
  ins&&/^## /{ins=0}
  ins&&/^\|/{
    body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body); n=split(body,f,"|")
    c1=f[1]; gsub(/[[:space:]]/,"",c1); if(c1 ~ /^:?-+:?$/)next
    if(!seen){seen=1
      for(i=1;i<=n;i++){h=tolower(f[i]); if(index(h,"surface"))sc=i; if(index(h,"cover")||index(h,"item"))cc=i; if(index(h,"note"))nc=i}
      if(!sc)sc=1; if(!cc)cc=2; next}
    s=f[sc]; cov=(cc?f[cc]:""); note=(nc?f[nc]:"")
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",s);    gsub(/\t/," ",s)
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",cov);  gsub(/\t/," ",cov)
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",note); gsub(/\t/," ",note)
    if(s!="") print s "\t" cov "\t" note
  }
' "$man" > "$tmp/map"

na_re='n/?a|not applicable|refactor|rename|no behaviou?r|dead code|config[ -]?only|generated|whitespace|formatting'

while IFS= read -r s; do
  [ -n "$s" ] || continue
  row="$(awk -F'\t' -v k="$s" '$1==k{print;exit}' "$tmp/map")"
  if [ -z "$row" ]; then
    fail "changed surface '$s' has no row in ## Changed-surface coverage — unmapped (a Test-Gap: changed behaviour with no checklist item)"
    continue
  fi
  cov="$(printf '%s' "$row" | cut -f2)"; note="$(printf '%s' "$row" | cut -f3)"
  # Strip N/A words from the covered cell; anything left is treated as real item token(s).
  covreal="$(printf '%s' "$cov" | sed -E 's/(n\/?a|not applicable)//ig')"
  covtoks="$(printf '%s' "$covreal" | tr ',;/|' '\n' | tr ' ' '\n' | grep -vE '^[[:space:]]*$' || true)"
  if [ -n "$covtoks" ]; then
    # coverage path — every named token must be a real item ID
    while IFS= read -r t; do
      t="$(printf '%s' "$t" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
      [ -n "$t" ] || continue
      grep -qxF "$t" "$tmp/items" || fail "changed surface '$s' names item '$t' which is not in ## Items (dangling coverage ref)"
    done <<< "$covtoks"
  else
    # N/A path — require a reason (a real N/A explanation, not a bare 'N/A')
    if printf '%s %s' "$cov" "$note" | grep -qiE "$na_re"; then
      reason="$(printf '%s %s' "$cov" "$note" | sed -E 's/(n\/?a|not applicable)//ig; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
      [ -n "$reason" ] || fail "changed surface '$s' marked N/A without a reason — state why it needs no test (pure refactor/rename/config/dead code/generated)"
    else
      fail "changed surface '$s' has no covering item and no N/A reason — cover it with >=1 item or mark 'N/A — <reason>'"
    fi
  fi
done < "$tmp/req"

if [ "$viol" -eq 0 ]; then
  echo "GAP-OK: all ${nreq} changed surface(s) mapped to a covering item or a reasoned N/A (true exercise verified at step 6.5, not here)"
  exit 0
fi
echo "---"
echo "$viol test-gap violation(s) — a changed behaviour-surface is untested; the checklist does not scale to the diff"
exit 1
