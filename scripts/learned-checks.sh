#!/usr/bin/env bash
# Learned-checks store — the feedback loop that makes QA smarter over time WITHOUT training a model.
# A growing, project-level table of checks distilled from real outcomes (escaped defects, recurring
# killer items). Step 12 appends to it; step 5 reads the rows matching the change so a check that
# caught a bug before re-enters every relevant future checklist. Plain markdown + grep — no embeddings.
#
# Usage:
#   learned-checks.sh add   <file> "<component>" "<check>" "<why>" [date]   # append a learned check
#   learned-checks.sh list  <file>                                         # print all rows (or NONE)
#   learned-checks.sh match <file> <keyword> [keyword...]                  # rows whose component/check
#                                                                          #   matches any keyword (or NONE)
#   learned-checks.sh scan  <docs-dir>                                     # BACKFILL: mine existing
#                                                                          #   reports for bug candidates
set -uo pipefail

cmd="${1:-}"; file="${2:-}"
[ -n "$cmd" ] && [ -n "$file" ] || { echo "usage: learned-checks.sh add|list|match <file> ..." >&2; exit 2; }

header() {
  cat <<'MD'
# Learned checks
> Checks distilled from real outcomes — escaped defects (after a GO) and recurring killer items.
> Step 5 pulls the rows matching the changed components into the checklist, so a check that caught a
> bug before cannot quietly drop out of future runs. Append-only; one row per learned check.

| # | Component / area | Check (what to verify) | Why (the escape/recurrence that taught it) | Added |
|---|------------------|------------------------|--------------------------------------------|-------|
MD
}

# count existing data rows (lines starting with `| <number>`); always one clean integer on stdout
datarows() {
  if [ -f "$file" ]; then
    grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file" 2>/dev/null || true
  else
    echo 0
  fi
}

case "$cmd" in
  add)
    comp="${3:-}"; check="${4:-}"; why="${5:-}"; date="${6:-$(date +%F)}"
    [ -n "$comp" ] && [ -n "$check" ] && [ -n "$why" ] || { echo 'usage: learned-checks.sh add <file> "<component>" "<check>" "<why>" [date]' >&2; exit 2; }
    # sanitize pipes so the row stays a valid single table row
    for v in comp check why; do printf -v "$v" '%s' "$(printf '%s' "${!v}" | tr '|' '/' | tr '\n' ' ')"; done
    [ -f "$file" ] || header > "$file"
    n=$(( $(datarows) + 1 ))
    printf '| %s | %s | %s | %s | %s |\n' "$n" "$comp" "$check" "$why" "$date" >> "$file"
    echo "LEARNED-CHECK-ADDED: #$n ($comp)"
    ;;
  list)
    if [ ! -f "$file" ] || [ "$(datarows)" -eq 0 ]; then echo "NONE"; exit 0; fi
    grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file"
    ;;
  match)
    shift 2
    [ "$#" -ge 1 ] || { echo "usage: learned-checks.sh match <file> <keyword> [keyword...]" >&2; exit 2; }
    if [ ! -f "$file" ] || [ "$(datarows)" -eq 0 ]; then echo "NONE"; exit 0; fi
    pat="$(printf '%s|' "$@")"; pat="${pat%|}"     # keyword1|keyword2|...
    out="$(grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file" | grep -iE "$pat" || true)"
    [ -n "$out" ] && printf '%s\n' "$out" || echo "NONE"
    ;;
  scan)
    # Backfill helper: mine the EXISTING reports in a docs dir for bug candidates, so the store can be
    # seeded from history (not only from new runs). Mechanical extraction; an agent/human then curates
    # which candidates become learned checks (recurring / high-value) and runs `add` for each.
    # Here the 2nd arg ($file) is a DOCS DIRECTORY.  Output: <report-file>\t<bug heading>  (or NONE).
    dir="$file"
    [ -d "$dir" ] || { echo "DOCS-DIR-MISSING: $dir"; exit 1; }
    out="$(grep -rlE '^## Found bugs|^# Test Report' "$dir" 2>/dev/null | while IFS= read -r rep; do
      awk -v f="$rep" '
        /^## Found bugs/ {insec=1; next}
        insec && /^## / {insec=0}
        insec && /^### / { h=$0; sub(/^###[[:space:]]*/,"",h); if (h !~ /^<.*>$/) print f "\t" h }
      ' "$rep"
    done)"
    [ -n "$out" ] && printf '%s\n' "$out" || echo "NONE"
    ;;
  *)
    echo "unknown command: $cmd (use add|list|match)" >&2; exit 2;;
esac
