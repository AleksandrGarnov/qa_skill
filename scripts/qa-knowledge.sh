#!/usr/bin/env bash
# QA knowledge base — per-component failure-mode profiles distilled from prior docs by `qa-learn`.
# The richer sibling of learned-checks.sh: where learned-checks holds concrete checks, this holds the
# STANDING RISK PROFILE of a component — the failure category that keeps recurring there and the
# technique/check a future run must therefore apply. Read at step 1 (recall) + step 5 (technique bias),
# and enforced by verify-learned.sh (a known recurring risk for a changed component must be addressed).
# Plain markdown + grep/awk — no model; the intelligence is `qa-learn`'s curation, not retrieval.
#
# Usage:
#   qa-knowledge.sh add   <file> "<component>" "<recurring-risk>" "<required technique/check>" [freq] [source] [date]
#   qa-knowledge.sh list  <file>
#   qa-knowledge.sh match <file> <keyword> [keyword...]   # rows whose component matches any keyword (or NONE)
set -uo pipefail

cmd="${1:-}"; file="${2:-}"
[ -n "$cmd" ] && [ -n "$file" ] || { echo "usage: qa-knowledge.sh add|list|match <file> ..." >&2; exit 2; }

header() {
  cat <<'MD'
# QA knowledge base
> Per-component failure-mode profiles distilled from prior QA docs by `qa-learn`. Each row: a component's
> recurring risk (the "why not caught" category / repeated bug class) and the technique or check a future
> run touching that component must apply. Step 1 recalls it; step 5 biases technique selection; and
> `verify-learned.sh` fails closed if a changed component's known recurring risk isn't addressed.
> Append-only; `qa-learn` dedupes and re-ranks. One row per component × recurring-risk.

| # | Component / area | Recurring risk (category) | Required technique / check | Freq | Learned from |
|---|------------------|---------------------------|----------------------------|------|--------------|
MD
}

datarows() {
  if [ -f "$file" ]; then grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file" 2>/dev/null || true; else echo 0; fi
}

case "$cmd" in
  add)
    comp="${3:-}"; risk="${4:-}"; req="${5:-}"; freq="${6:-1}"; src="${7:-}"; date="${8:-$(date +%F)}"
    [ -n "$comp" ] && [ -n "$risk" ] && [ -n "$req" ] || { echo 'usage: qa-knowledge.sh add <file> "<component>" "<recurring-risk>" "<required technique/check>" [freq] [source] [date]' >&2; exit 2; }
    for v in comp risk req freq src; do printf -v "$v" '%s' "$(printf '%s' "${!v}" | tr '|' '/' | tr '\n' ' ')"; done
    [ -n "$src" ] || src="-"
    [ -f "$file" ] || header > "$file"
    n=$(( $(datarows) + 1 ))
    printf '| %s | %s | %s | %s | %s | %s |\n' "$n" "$comp" "$risk" "$req" "$freq" "$src" >> "$file"
    echo "KNOWLEDGE-ADDED: #$n ($comp: $risk -> $req)"
    ;;
  list)
    if [ ! -f "$file" ] || [ "$(datarows)" -eq 0 ]; then echo "NONE"; exit 0; fi
    grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file"
    ;;
  match)
    shift 2
    [ "$#" -ge 1 ] || { echo "usage: qa-knowledge.sh match <file> <keyword> [keyword...]" >&2; exit 2; }
    if [ ! -f "$file" ] || [ "$(datarows)" -eq 0 ]; then echo "NONE"; exit 0; fi
    # match on the Component column (col 2) only — so a keyword doesn't match a risk/technique by accident
    pat="$(printf '%s|' "$@")"; pat="${pat%|}"
    out="$(awk -F'|' -v pat="$pat" '
      /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
        c=$3; gsub(/^[[:space:]]+|[[:space:]]+$/,"",c)
        if (tolower(c) ~ tolower(pat)) print
      }' "$file")"
    [ -n "$out" ] && printf '%s\n' "$out" || echo "NONE"
    ;;
  *)
    echo "unknown command: $cmd (use add|list|match)" >&2; exit 2;;
esac
