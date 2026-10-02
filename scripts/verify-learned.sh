#!/usr/bin/env bash
# Learned-risk gate — a component's KNOWN recurring risk (from qa-knowledge.md, distilled from prior
# docs) must be addressed when this change touches that component. Closes the loop: the system can't
# re-ship a class of bug it already learned about. Fails closed if an in-play recurring risk has no
# addressing row in the manifest's `## Learned risks` section.
#
# STRUCTURAL only (like the Test-Gap / technique gates): it checks each in-play component has an
# addressed-or-reasoned-N/A row; whether the chosen technique TRULY mitigates the risk is semantic,
# verified at the step-6.5 review. "In play" = the KB component keyword appears in the frozen changed
# surfaces for this run.
#
# Usage: verify-learned.sh <manifest.md> <knowledge-file> <surfaces-file>
# Output: LEARNED-OK (exit 0) or violations (exit 1).
set -uo pipefail

man="${1:?usage: verify-learned.sh <manifest.md> <knowledge-file> <surfaces-file>}"
kb="${2:?usage: verify-learned.sh <manifest.md> <knowledge-file> <surfaces-file>}"
surf="${3:?usage: verify-learned.sh <manifest.md> <knowledge-file> <surfaces-file>}"
[ -f "$man" ]  || { echo "MANIFEST-MISSING: $man"; exit 1; }
[ -f "$surf" ] || { echo "SURFACES-MISSING: $surf"; exit 1; }
# No KB yet (first-ever run / none distilled) -> nothing to enforce.
[ -f "$kb" ] || { echo "LEARNED-OK: no knowledge base yet (nothing learned to enforce)"; exit 0; }

SECT_RE="${QA_RE_LEARNED:-Learned risks|Learned-risk|Known risks}"
viol=0; fail() { echo "FAIL: $*"; viol=$((viol+1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# changed surfaces as a single lowercased blob to test component keywords against
surfblob="$(tr 'A-Z' 'a-z' < "$surf")"

# KB rows: component \t risk  (data rows only)
awk -F'|' '/^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
  c=$3; r=$4; gsub(/^[[:space:]]+|[[:space:]]+$/,"",c); gsub(/^[[:space:]]+|[[:space:]]+$/,"",r)
  if (c!="") print c "\t" r
}' "$kb" > "$tmp/kb"
[ -s "$tmp/kb" ] || { echo "LEARNED-OK: knowledge base has no rows"; exit 0; }

# in-play components = KB components whose keyword appears in the changed surfaces
: > "$tmp/inplay"
while IFS=$'\t' read -r comp risk; do
  [ -n "$comp" ] || continue
  key="$(printf '%s' "$comp" | tr 'A-Z' 'a-z')"
  if printf '%s' "$surfblob" | grep -qF "$key"; then printf '%s\t%s\n' "$comp" "$risk" >> "$tmp/inplay"; fi
done < "$tmp/kb"

if [ ! -s "$tmp/inplay" ]; then
  echo "LEARNED-OK: no changed surface matches a known-risk component"
  exit 0
fi

# the manifest must carry a ## Learned risks section addressing each in-play component
has_sect=0
awk -v R="$SECT_RE" '$0 ~ ("^## +(" R ")"){f=1} END{exit !f}' "$man" && has_sect=1
if [ "$has_sect" -ne 1 ]; then
  comps="$(cut -f1 "$tmp/inplay" | sort -u | paste -sd, -)"
  fail "manifest has no '## Learned risks' section, but the change touches component(s) with known recurring risks [$comps] — recall qa-knowledge and address each (an item/technique) or state 'N/A — <reason>'. See qa-knowledge.md"
  echo "---"; echo "$viol learned-risk violation(s)"; exit 1
fi

# parse ## Learned risks rows: component(col after #) + addressed cell
awk -v R="$SECT_RE" '
  $0 ~ ("^## +(" R ")"){ins=1;seen=0;next} ins&&/^## /{ins=0}
  ins&&/^\|/{
    body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body); n=split(body,f,"|")
    c1=f[1]; gsub(/[[:space:]]/,"",c1); if(c1 ~ /^:?-+:?$/)next
    if(!seen){seen=1;next}
    # columns: # | Component | Recurring risk | Addressed by / N-A
    comp=f[2]; addr=f[n]
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",comp); gsub(/\t/," ",comp)
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",addr); gsub(/\t/," ",addr)
    if(comp!="") print comp "\t" addr
  }
' "$man" > "$tmp/addressed"

na_re='n/?a|not applicable|does ?n.t (touch|apply)|out of scope|no longer'
# each in-play component must have an addressing row that is non-empty (items/technique) or reasoned N/A
cut -f1 "$tmp/inplay" | sort -u | while IFS= read -r comp; do
  [ -n "$comp" ] || continue
  key="$(printf '%s' "$comp" | tr 'A-Z' 'a-z')"
  row="$(awk -F'\t' -v k="$key" 'tolower($1) ~ k {print; exit}' "$tmp/addressed")"
  if [ -z "$row" ]; then
    echo "MISS	$comp"; continue
  fi
  addr="$(printf '%s' "$row" | cut -f2)"
  real="$(printf '%s' "$addr" | sed -E 's/(n\/?a|not applicable)//ig; s/[[:space:]]+/ /g; s/^ //; s/ $//')"
  if [ -z "$real" ]; then echo "EMPTY	$comp"; fi
done > "$tmp/bad"

while IFS=$'\t' read -r kind comp; do
  case "$kind" in
    MISS)  fail "changed component '$comp' has a known recurring risk but no row in ## Learned risks — address it (item/technique) or 'N/A — <reason>'";;
    EMPTY) fail "changed component '$comp' has a ## Learned risks row with no addressing item/technique and no N/A reason";;
  esac
done < "$tmp/bad"

if [ "$viol" -eq 0 ]; then
  echo "LEARNED-OK: every changed component with a known recurring risk is addressed (mitigation adequacy verified at step 6.5)"
  exit 0
fi
echo "---"
echo "$viol learned-risk violation(s) — a class of bug the corpus already taught us is unaddressed"
exit 1
