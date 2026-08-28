#!/usr/bin/env bash
# Sidecar consistency gate — cross-checks the markdown artifacts against their JSON sidecars.
#
# The md-only gates (verify-context / verify-report / verify-coverage) and the json-only gate
# (verify-evidence) each read a DIFFERENT file. Nothing else guarantees the two agree, so a run could
# keep manifest.md / manifest.json (or report.md / report.json) out of sync — an item present in one
# with a different ID, or missing from the other — and every gate would still pass, each on its own
# half of the picture. This gate closes that seam: the item IDs must match across md and json.
#
# Structural, not semantic: it checks that the two accountings list the SAME item / result IDs, not
# that the contents are correct (that stays with the other gates + the step-6.5 review).
#
# Usage: verify-sidecars.sh <manifest.md> <manifest.json> <report.md> <report.json>
# Output: SIDECARS-OK (exit 0) or a list of mismatches (exit 1).
set -uo pipefail
export LC_ALL=C   # make sort(1) and python sorted() agree (byte order)

mmd="${1:?usage: verify-sidecars.sh <manifest.md> <manifest.json> <report.md> <report.json>}"
mjson="${2:?usage: verify-sidecars.sh <manifest.md> <manifest.json> <report.md> <report.json>}"
rmd="${3:?usage: verify-sidecars.sh <manifest.md> <manifest.json> <report.md> <report.json>}"
rjson="${4:?usage: verify-sidecars.sh <manifest.md> <manifest.json> <report.md> <report.json>}"
for f in "$mmd" "$mjson" "$rmd" "$rjson"; do
  [ -f "$f" ] || { echo "MISSING: $f"; exit 1; }
done

viol=0
fail() { echo "FAIL: $*"; viol=$((viol+1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# --- item IDs from a markdown table section, column located by header ('id', or 'id'/'#') ---
md_ids() {  # <file> <section-heading> <id-keywords-regex-in-awk>
  awk -v sec="$2" '
    $0 ~ "^## " sec {ins=1; seen=0; idc=0; next}
    ins && /^## / {ins=0}
    ins && /^\|/ {
      b=$0; sub(/^\|/,"",b); sub(/\|[[:space:]]*$/,"",b); n=split(b,f,"|")
      c1=f[1]; gsub(/[[:space:]]/,"",c1); if (c1 ~ /^:?-+:?$/) next
      if (!seen) { seen=1; for(i=1;i<=n;i++){h=tolower(f[i]); if((index(h,"id")||index(h,"#"))&&!idc)idc=i} if(!idc)idc=1; next }
      id=f[idc]; gsub(/[[:space:]]/,"",id); if (id!="") print id
    }' "$1" | sort -u
}

# --- IDs from a JSON array of objects, by key ---
json_ids() {  # <file> <top-array-key> <id-key>
  python3 - "$1" "$2" "$3" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding='utf-8'))
except Exception as e:
    print("__JSON_ERROR__", e, file=sys.stderr); sys.exit(3)
arr = d.get(sys.argv[2], []) or []
ids = {str(o.get(sys.argv[3], '')).strip() for o in arr if str(o.get(sys.argv[3], '')).strip()}
print('\n'.join(sorted(ids)))
PY
}

check_pair() {  # <label> <md-file> <md-section> <json-file> <json-array> <json-idkey>
  local label="$1" mdf="$2" sec="$3" jf="$4" arr="$5" idk="$6"
  md_ids "$mdf" "$sec" > "$tmp/md"
  if ! json_ids "$jf" "$arr" "$idk" > "$tmp/json" 2>"$tmp/err"; then
    fail "$label: could not parse $jf ($(head -1 "$tmp/err"))"; return
  fi
  local only_md only_json
  only_md="$(comm -23 "$tmp/md" "$tmp/json")"
  only_json="$(comm -13 "$tmp/md" "$tmp/json")"
  [ -z "$only_md" ]   || fail "$label: ID(s) in .md but not .json: $(echo $only_md | tr '\n' ' ')"
  [ -z "$only_json" ] || fail "$label: ID(s) in .json but not .md: $(echo $only_json | tr '\n' ' ')"
}

check_pair "manifest items" "$mmd" "Items"             "$mjson" "items"   "id"
check_pair "report results" "$rmd" "Checklist results" "$rjson" "results" "itemId"

if [ "$viol" -eq 0 ]; then
  echo "SIDECARS-OK: manifest & report item IDs match across md and json"
  exit 0
fi
echo "---"
echo "$viol sidecar mismatch(es) — the md and json accountings disagree; the md-only and json-only gates would each pass on a different picture"
exit 1
