#!/usr/bin/env bash
# qa-harvest — mine the whole corpus of prior QA documents into structured signal for learning.
# Deterministic extraction only (grep/awk, no model): the `qa-learn` skill then CURATES this signal
# into the knowledge store. Reads a docs directory of prior reports + an escaped-defects log.
#
# Sources & what each teaches:
#   - report "## Found bugs"  ->  recurring bugs per component (the `[Feature]` tag) + severity
#   - escaped-defects log      ->  per-component "why not caught" categories (the structural gaps)
#   - report "## Verdict"      ->  per-component GO/NO-GO trend (seeds confidence)
#
# Usage:
#   qa-harvest.sh bugs     <docs-dir>            # source \t component \t severity \t title
#   qa-harvest.sh escapes  <docs-dir>            # source \t component \t severity \t why-not-caught
#   qa-harvest.sh verdicts <docs-dir>            # source \t verdict(GO|NO-GO|GO-WITH-DEFERRALS|EXPLORATORY)
#   qa-harvest.sh summary  <docs-dir>            # per-component digest, ranked by frequency (for curation)
set -uo pipefail

cmd="${1:-}"; dir="${2:-}"
[ -n "$cmd" ] && [ -n "$dir" ] || { echo "usage: qa-harvest.sh bugs|escapes|verdicts|summary <docs-dir>" >&2; exit 2; }
[ -d "$dir" ] || { echo "DOCS-DIR-MISSING: $dir"; exit 1; }

# --- found bugs across all reports: source \t component \t severity \t title ---
harvest_bugs() {
  grep -rlE '^## Found bugs' "$dir" 2>/dev/null | while IFS= read -r rep; do
    awk -v f="$rep" '
      function flush() {
        if (inblock && title!="" && title !~ /^<.*>$/)
          print f "\t" (comp!=""?comp:"unknown") "\t" sev "\t" title
        inblock=0; comp=""; sev="minor"; title=""
      }
      /^## Found bugs/ {insec=1; next}
      insec && /^## / {flush(); insec=0}
      insec && /^### / {
        flush()
        h=$0; sub(/^###[[:space:]]*/,"",h); gsub(/\r/,"",h)
        comp=""; if (match(h, /\[[^]]*\]/)) comp=substr(h, RSTART+1, RLENGTH-2)
        title=h; sev="minor"; inblock=1; next
      }
      insec && inblock && tolower($0) ~ /severity/ {
        l=tolower($0)
        if (l ~ /blocker/) sev="blocker"; else if (l ~ /major/) sev="major"; else if (l ~ /minor/) sev="minor"
      }
      END {flush()}
    ' "$rep"
  done
}

# --- escaped defects: source \t component \t severity \t why-not-caught ---
harvest_escapes() {
  grep -rlE '^escape:|why not caught:' "$dir" 2>/dev/null | while IFS= read -r f; do
    awk -v f="$f" '
      function flush() {
        if (started) print f "\t" (comp!=""?comp:"unknown") "\t" (sev!=""?sev:"unknown") "\t" (why!=""?why:"uncategorized")
        started=0; comp=""; sev=""; why=""
      }
      /^[[:space:]]*escape:/ {flush(); started=1; next}
      /^[[:space:]]*component\/area:/ { c=$0; sub(/^[^:]*:[[:space:]]*/,"",c); gsub(/^[[:space:]]+|[[:space:]]+$/,"",c); gsub(/\r/,"",c); comp=c; started=1 }
      /^[[:space:]]*severity:/ { s=$0; sub(/^[^:]*:[[:space:]]*/,"",s); sub(/[[:space:]].*/,"",s); gsub(/\r/,"",s); sev=s }
      /^[[:space:]]*why not caught:/ { w=$0; sub(/^[^:]*:[[:space:]]*/,"",w); gsub(/^[[:space:]]+|[[:space:]]+$/,"",w); gsub(/\r/,"",w); why=w }
      END {flush()}
    ' "$f"
  done
}

# --- verdicts: source \t verdict ---
harvest_verdicts() {
  grep -rlE '^\*\*Verdict:' "$dir" 2>/dev/null | while IFS= read -r rep; do
    v="$(grep -m1 -E '^\*\*Verdict:' "$rep")"
    vn="UNKNOWN"
    case "$(printf '%s' "$v" | tr 'a-z' 'A-Z')" in
      *NO-GO*|*"⛔"*) vn="NO-GO";;
      *DEFERRAL*) vn="GO-WITH-DEFERRALS";;
      *EXPLORATORY*) vn="EXPLORATORY";;
      *GO*|*"✅"*) vn="GO";;
    esac
    printf '%s\t%s\n' "$rep" "$vn"
  done
}

case "$cmd" in
  bugs)     harvest_bugs ;;
  escapes)  harvest_escapes ;;
  verdicts) harvest_verdicts ;;
  summary)
    tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
    harvest_bugs    > "$tmp/bugs"    2>/dev/null || true
    harvest_escapes > "$tmp/escapes" 2>/dev/null || true
    echo "# qa-harvest summary — per-component signal from prior docs (curate into the knowledge store)"
    echo "# component | bugs | escapes | max-severity | recurring why-not-caught categories"
    # union of components seen in bugs + escapes
    { cut -f2 "$tmp/bugs"; cut -f2 "$tmp/escapes"; } 2>/dev/null | sort -u | grep -v '^$' | while IFS= read -r comp; do
      [ -n "$comp" ] || continue
      nb=$(awk -F'\t' -v c="$comp" '$2==c' "$tmp/bugs" | grep -c . || true)
      ne=$(awk -F'\t' -v c="$comp" '$2==c' "$tmp/escapes" | grep -c . || true)
      # max severity across this component's bugs+escapes
      sev=$(awk -F'\t' -v c="$comp" '$2==c{print $3}' "$tmp/bugs" "$tmp/escapes" | tr 'A-Z' 'a-z' \
        | awk '/blocker/{b=1} /major/{m=1} /minor/{n=1} END{print (b?"blocker":(m?"major":(n?"minor":"-")))}')
      cats=$(awk -F'\t' -v c="$comp" '$2==c{print $4}' "$tmp/escapes" | sort | uniq -c | sort -rn \
        | awk '{$1=$1; cnt=$1; $1=""; sub(/^ /,""); printf "%s(x%s) ", $0, cnt}')
      printf '%s | %s | %s | %s | %s\n' "$comp" "$nb" "$ne" "$sev" "${cats:-—}"
    done | sort -t'|' -k2 -rn
    ;;
  *)
    echo "unknown command: $cmd (use bugs|escapes|verdicts|summary)" >&2; exit 2;;
esac
