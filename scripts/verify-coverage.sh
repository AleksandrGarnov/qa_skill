#!/usr/bin/env bash
# Coverage cross-check between the APPROVED checklist manifest and the test report.
# Two STRUCTURAL guarantees (set membership on item IDs — NOT a semantic check of whether
# a 'pass' is truthful; that stays the step-9 self-audit + an independent reviewer):
#   1. No skipped items — every item ID in the frozen manifest has a result row in the report.
#   2. Journey-rooted — every manifest item traces to a user journey defined in the manifest,
#      and at least one journey exists (a checklist built from code concerns has no journeys).
#   3. Oracle present (STRUCTURAL only) — the ## Items table carries an "Expected source" column and
#      every item fills it (non-empty, non-placeholder), with a best-effort TRIPWIRE that trips the
#      blatant "the code is its own oracle" phrasings. This is NOT a semantic guarantee of
#      independence — bash can't tell a real "hand calc: 100-10" from an invented "spec §4". TRUE
#      independence (is the source real, and actually independent of the impl?) is a SEMANTIC check,
#      done at the step-6.5 review, per this repo's rule: gates check field completeness, prose/review
#      checks semantics. A green here means "an oracle is declared and isn't blatantly the code",
#      not "the oracle is sound". See test-oracle.md.
#   4. Test-design technique present (STRUCTURAL only) — the ## Items table carries a "Technique" column
#      and every item names a technique from a CLOSED vocabulary (equivalence/boundary/decision-table/
#      state-transition/use-case/pairwise/error-guessing/classification-tree/exploratory/n-a). A bare
#      "manual"/"tested it"/"-" is rejected, so "I tested a few values/combos" can't pass for coverage.
#      Whether the chosen technique is the RIGHT one for the feature is SEMANTIC (step-6.5 review), same
#      split as the oracle check. See test-design-techniques.md.
#   5. Technique-as-quota (STRUCTURAL only) — when an ENUMERABLE technique (decision-table/state-
#      transition/pairwise/boundary) is used, the ## Technique coverage section must carry a claim WITH
#      a number for it (N rules / V+I transitions / N cases / N classes) — so a complex space can't
#      collapse to one check. The number's arithmetic correctness is SEMANTIC (step-6.5 review).
#      See test-design-techniques.md.
#
# Usage: verify-coverage.sh <manifest.md> <report.md>
# Output: COVERAGE-OK (exit 0) or a list of violations (exit 1).
set -uo pipefail

man="${1:?usage: verify-coverage.sh <manifest.md> <report.md>}"
rep="${2:?usage: verify-coverage.sh <manifest.md> <report.md>}"
[ -f "$man" ] || { echo "MANIFEST-MISSING: $man"; exit 1; }
[ -f "$rep" ] || { echo "REPORT-MISSING: $rep"; exit 1; }

# Localizable results-section heading (EN + RU default; override via env, e.g.
# QA_RE_RESULTS='Checklist results|Ergebnisse'). Byte-safe — no Cyrillic char classes.
RESULTS_RE="${QA_RE_RESULTS:-Checklist results|Результаты[^|]*чек}"

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
      for (i=1;i<=n;i++){ h=tolower(f[i]); if(index(h,"journey"))jc=i; if(index(h,"id")&&!idc)idc=i; if(index(h,"source")&&!sc)sc=i; if(index(h,"technique")&&!tc)tc=i }
      if (!idc) idc=1
      if (!jc)  jc=2
      next
    }
    id=f[idc]; jr=f[jc]
    gsub(/[[:space:]]/,"",id); gsub(/[[:space:]]/,"",jr)
    src=(sc? f[sc] : ""); gsub(/^[[:space:]]+|[[:space:]]+$/,"",src); gsub(/\t/," ",src)
    tech=(tc? f[tc] : ""); gsub(/^[[:space:]]+|[[:space:]]+$/,"",tech); gsub(/\t/," ",tech)
    if (id != "") print id "\t" jr "\t" src "\t" tech
  }
' "$man" > "$tmp/items"

# Does the ## Items table declare an "Expected source" (oracle) column at all?
items_header="$(awk '/^## Items/{f=1;next} f&&/^\|/{print;exit}' "$man")"
has_srccol=0
printf '%s' "$items_header" | grep -qiE 'expected source|[^a-z]source[^a-z]|source *\|' && has_srccol=1

# Does the ## Items table declare a "Technique" (test-design technique) column at all?
has_techcol=0
printf '%s' "$items_header" | grep -qiE 'technique' && has_techcol=1

cut -f1 "$tmp/items" | sort -u > "$tmp/approved"
napproved=$(grep -c . "$tmp/approved" 2>/dev/null || true)
[ "${napproved:-0}" -gt 0 ] || fail "manifest has no checklist items (## Items empty)"

# The oracle column must exist — every check needs an expected value sourced independently of the code.
[ "$has_srccol" -eq 1 ] || fail "manifest ## Items has no 'Expected source' column — every check needs an oracle independent of the implementation (spec/hand-calc/invariant/reference/historical, or a metamorphic rule). See references/test-oracle.md"

# The technique column must exist — every check must name the test-design technique that produced it,
# so "tested a few values/combos" can't pass for coverage. This is STRUCTURAL (a recognized technique
# is declared); whether it's the RIGHT technique for the feature is semantic (step-6.5 review), like the
# oracle-independence check above. See references/test-design-techniques.md.
[ "$has_techcol" -eq 1 ] || fail "manifest ## Items has no 'Technique' column — every check must name the test-design technique that chose its values/combinations/sequences (equivalence/boundary/decision-table/state-transition/use-case/pairwise/error-guessing/classification-tree/exploratory, or 'n/a — <reason>'). See references/test-design-techniques.md"

# Best-effort TRIPWIRE for a source that is blatantly 'the code itself' — NOT a guarantee.
# Independence is semantic (bash can't tell a real "hand calc: 100-10" from an invented "spec §4"),
# so this only trips the obvious phrasings (EN + common RU); TRUE independence is verified at the
# step-6.5 review. Do not read a green here as "the oracle is independent" — read it as "not
# blatantly the code". Byte-safe: no Cyrillic char classes/ranges (they break in C-locale grep).
impl_oracle='whatever the code|the code returns?|code returns?|returned by (the )?(code|impl|implementation)|implementation under test|^impl(ementation)?$|same as (the )?(code|impl|current|existing|prod)|dev said|what the dev|because the code|current behaviou?r|existing behaviou?r|system output|running app|the app returns?|as returned|what it returns?|actual output|observed output|matches (the )?(current|existing|prod|app)|\(код\)|из кода|как в коде|что вернул код|что возвращает код|что отдаёт код|текущ[^|]*поведени|как сейчас|вывод системы|совпадает с (кодом|реализац)|как в проде|как в реализации'

# Recognized test-design technique vocabulary (CLOSED set — a value outside it, e.g. "manual" /
# "tested it" / "-", is a disguised no-technique, mirroring the closed terminal-bucket whitelist for
# results). Byte-safe: full words are unambiguous; abbreviations (ep/bva/dt/fsm/na/n/a) are boundary-
# guarded with explicit [^a-zA-Z] so they don't match inside ordinary words (rename, keep, banana).
tech_vocab='equivalence|partition|boundary|decision[ _-]?table|state[ _-]?transition|state[ _-]?machine|n-?switch|switch coverage|use[ _-]?case|scenario|pairwise|combinatorial|all-?pairs|t=[0-9]|error[ _-]?guess|classification[ _-]?tree|exploratory|not applicable|(^|[^a-zA-Z])(ep|bva|dt|fsm|na|n/a)([^a-zA-Z]|$)'

# every item must carry a journey ref that exists in ## Journeys, an independent oracle, AND a technique
while IFS=$'\t' read -r id jr src tech; do
  [ -n "$id" ] || continue
  if [ -z "$jr" ]; then
    fail "manifest item $id has no journey ref — every item must trace to a user journey (J#)"
  elif ! grep -qxF "$jr" "$tmp/journeys"; then
    fail "manifest item $id references journey $jr, which is not defined in ## Journeys"
  fi
  if [ "$has_srccol" -eq 1 ]; then
    case "$src" in
      ""|"<"*">") fail "manifest item $id has no Expected source — derive the expected value independently of the implementation (spec/hand-calc/invariant/reference/historical), or state a metamorphic rule (references/test-oracle.md)";;
      *) printf '%s' "$src" | grep -qiE "$impl_oracle" && fail "manifest item $id names the implementation as its own oracle ('$src') — a green check would only prove the code agrees with itself; derive expected from an independent source. (This tripwire catches only blatant phrasings; the step-6.5 review checks true independence.)";;
    esac
  fi
  if [ "$has_techcol" -eq 1 ]; then
    case "$tech" in
      ""|"<"*">") fail "manifest item $id has no Technique — name the test-design technique that produced its values/combinations/sequences (equivalence/boundary/decision-table/state-transition/use-case/pairwise/error-guessing/classification-tree/exploratory, or 'n/a — <reason>' for a trivial single-value check). See references/test-design-techniques.md";;
      *) printf '%s' "$tech" | grep -qiE "$tech_vocab" || fail "manifest item $id names an unrecognized Technique ('$tech') — use one of equivalence/boundary/decision-table/state-transition/use-case/pairwise/error-guessing/classification-tree/exploratory, or 'n/a — <reason>' (a bare 'manual'/'tested it'/'-' is not a technique). See references/test-design-techniques.md";;
    esac
  fi
done < "$tmp/items"

# --- M2: technique-as-quota — an ENUMERABLE technique must carry a NUMERIC coverage claim ---
# decision-table/state-transition/pairwise/boundary have a countable target (rules/transitions/cases/
# classes); tagging one and staying silent on "how many" lets a complex space collapse to one check.
# STRUCTURAL only: the gate requires a claim WITH a number to exist per used enumerable technique — it
# does NOT check the number is arithmetically right (that's the step-6.5 review, same split as oracle).
fam_of() {
  local s; s="$(printf '%s' "$1" | tr 'A-Z' 'a-z')"
  if printf '%s' "$s" | grep -qE 'decision[ _-]?table|(^|[^a-z])dt([^a-z]|$)'; then echo decision-table; return; fi
  if printf '%s' "$s" | grep -qE 'state[ _-]?transition|state[ _-]?machine|n-?switch|switch coverage|(^|[^a-z])fsm([^a-z]|$)'; then echo state-transition; return; fi
  if printf '%s' "$s" | grep -qE 'pairwise|combinatorial|all-?pairs|t=[0-9]|n-?wise'; then echo pairwise; return; fi
  if printf '%s' "$s" | grep -qE 'boundary|(^|[^a-z])bva([^a-z]|$)'; then echo boundary; return; fi
  echo ""
}
if [ "$has_techcol" -eq 1 ]; then
  cut -f4 "$tmp/items" | while IFS= read -r tk; do fam_of "$tk"; done | grep -v '^$' | sort -u > "$tmp/famused"
  if [ -s "$tmp/famused" ]; then
    TC_RE="${QA_RE_TECHCOV:-Technique coverage|Покрытие[^|]*техник}"
    has_tcsection=0
    awk -v R="$TC_RE" '$0 ~ ("^## +(" R ")"){f=1} END{exit !f}' "$man" && has_tcsection=1
    awk -v R="$TC_RE" '
      $0 ~ ("^## +(" R ")"){ins=1;seen=0;next} ins&&/^## /{ins=0}
      ins&&/^\|/{ body=$0; sub(/^\|/,"",body); sub(/\|[[:space:]]*$/,"",body); split(body,f,"|")
        c1=f[1]; gsub(/[[:space:]]/,"",c1); if(c1 ~ /^:?-+:?$/)next
        if(!seen){seen=1;next}
        t=f[1]; c=f[2]; gsub(/^[[:space:]]+|[[:space:]]+$/,"",t); gsub(/\t/," ",t); gsub(/\t/," ",c)
        if(t!="") print t "\t" c }
    ' "$man" > "$tmp/tcrows"
    : > "$tmp/famclaim"
    while IFS=$'\t' read -r tcname claim; do
      f="$(fam_of "$tcname")"; [ -n "$f" ] || continue
      printf '%s' "$claim" | grep -qE '[0-9]' && echo "$f" >> "$tmp/famclaim"
    done < "$tmp/tcrows"
    sort -u "$tmp/famclaim" -o "$tmp/famclaim" 2>/dev/null || true
    if [ "$has_tcsection" -ne 1 ]; then
      fail "manifest uses enumerable technique(s) [$(paste -sd, "$tmp/famused")] but has no '## Technique coverage' section — state a numeric coverage claim per technique (decision-table: N feasible rules; state-transition: V valid+I invalid; pairwise: N cases; boundary: N classes). See references/test-design-techniques.md"
    else
      while IFS= read -r f; do
        [ -n "$f" ] || continue
        grep -qxF "$f" "$tmp/famclaim" || fail "technique '$f' is used but its ## Technique coverage claim states no number — quantify the target it covers (rules/transitions/cases/classes), so a complex space can't collapse to a single check"
      done < "$tmp/famused"
    fi
  fi
fi

# --- report results: ID -> terminal status (## Checklist results; columns by header) ---
awk -v R="$RESULTS_RE" '
  $0 ~ ("^## +(" R ")") {insec=1; seen=0; idc=0; rc=0; next}
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
  echo "COVERAGE-OK: all ${napproved:-0} approved item(s) accounted for; every item journey-rooted across ${njourneys:-0} journey(s); each declares an Expected source and a test-design Technique, and every enumerable technique carries a numeric coverage claim (soundness of all three verified semantically at step 6.5, not here)"
  exit 0
fi
echo "---"
echo "$viol coverage violation(s) — the report does not account for the approved, journey-rooted checklist"
exit 1
