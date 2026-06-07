#!/usr/bin/env bash
# Confidence ledger — the trust metric that decides when a task class is safe to run with less
# human presence (the KPI from lesson 7: one-shot success, a growing streak of clean runs).
#
# It records, per component, the outcome of each QA cycle — a clean GO, or an ESCAPE (a defect that
# slipped past a GO and later surfaced, recorded by step 12). The "streak" is the number of clean GOs
# in a row since the last escape for that component. A high streak is the signal that the agent layer
# handles that task class reliably enough to lower presence (auto-approve / ZTE) — while the merge-gate
# hook still physically enforces the gates, so confidence lowers ceremony, never the safety floor.
#
# Plain markdown + awk, same shape as learned-checks.sh — no model, no embeddings.
#
# Usage:
#   confidence.sh record  <file> "<component>" go|escape [run-id] [date]   # append an outcome
#   confidence.sh streak  <file> "<component>"                             # clean GOs in a row (integer)
#   confidence.sh suggest <file> "<component>" [threshold]                 # READY/KEEP presence advice
#   confidence.sh list    <file>                                          # print all rows (or NONE)
set -uo pipefail

DEFAULT_THRESHOLD="${CONFIDENCE_THRESHOLD:-5}"

cmd="${1:-}"; file="${2:-}"
[ -n "$cmd" ] && [ -n "$file" ] || { echo "usage: confidence.sh record|streak|suggest|list <file> ..." >&2; exit 2; }

header() {
  cat <<'MD'
# Confidence ledger
> Per-component QA outcomes — a clean GO, or an ESCAPE (a defect that slipped past a GO, logged by step 12).
> The streak (clean GOs in a row since the last escape) is the trust signal for lowering presence on a
> task class. The merge-gate hook still enforces the gates regardless — confidence lowers ceremony, not the
> safety floor. Append-only; one row per cycle outcome.

| # | Component / area | Outcome | Run / ADW id | Date |
|---|------------------|---------|--------------|------|
MD
}

# normalize a value for storage/compare: strip surrounding space, drop pipes/newlines
norm() { printf '%s' "$1" | tr '|' '/' | tr '\n' ' ' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'; }

datarows() {
  if [ -f "$file" ]; then
    grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file" 2>/dev/null || true
  else
    echo 0
  fi
}

# clean GOs in a row since the last ESCAPE for a component (case-insensitive component match)
compute_streak() {
  local comp; comp="$(norm "$1" | tr 'A-Z' 'a-z')"
  [ -f "$file" ] || { echo 0; return; }
  awk -F'|' -v comp="$comp" '
    /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
      c=$3; gsub(/^[[:space:]]+|[[:space:]]+$/,"",c); c=tolower(c)
      o=$4; gsub(/^[[:space:]]+|[[:space:]]+$/,"",o); o=toupper(o)
      if (c==comp) { n++; out[n]=o }
    }
    END { s=0; for (i=n;i>=1;i--){ if (out[i]=="GO") s++; else break } print s }
  ' "$file"
}

case "$cmd" in
  record)
    comp="$(norm "${3:-}")"; outcome="$(norm "${4:-}" | tr 'a-z' 'A-Z')"; runid="$(norm "${5:--}")"; date="${6:-$(date +%F)}"
    [ -n "$comp" ] && [ -n "$outcome" ] || { echo 'usage: confidence.sh record <file> "<component>" go|escape [run-id] [date]' >&2; exit 2; }
    case "$outcome" in GO|ESCAPE) ;; *) echo "outcome must be 'go' or 'escape', got: $outcome" >&2; exit 2;; esac
    [ -n "$runid" ] || runid="-"
    [ -f "$file" ] || header > "$file"
    n=$(( $(datarows) + 1 ))
    printf '| %s | %s | %s | %s | %s |\n' "$n" "$comp" "$outcome" "$runid" "$date" >> "$file"
    echo "CONFIDENCE-RECORDED: #$n $comp $outcome (streak now $(compute_streak "$comp"))"
    ;;
  streak)
    [ -n "${3:-}" ] || { echo 'usage: confidence.sh streak <file> "<component>"' >&2; exit 2; }
    compute_streak "${3}"
    ;;
  suggest)
    comp="${3:-}"
    [ -n "$comp" ] || { echo 'usage: confidence.sh suggest <file> "<component>" [threshold]' >&2; exit 2; }
    thr="${4:-$DEFAULT_THRESHOLD}"
    case "$thr" in ''|*[!0-9]*) echo "threshold must be a positive integer, got: $thr" >&2; exit 2;; esac
    s="$(compute_streak "$comp")"
    if [ "$s" -ge "$thr" ]; then
      echo "READY-FOR-PRESENCE-REDUCTION: '$comp' has $s clean GO(s) in a row (>= $thr). A task in this class is a candidate for auto-approve / ZTE — the merge-gate hook still enforces the gates. Lowering presence is the user's explicit opt-in, not automatic."
    else
      echo "KEEP-PRESENCE: '$comp' at $s/$thr clean GO(s) — keep manual approval (step 7)."
    fi
    ;;
  list)
    if [ ! -f "$file" ] || [ "$(datarows)" -eq 0 ]; then echo "NONE"; exit 0; fi
    grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$file"
    ;;
  *)
    echo "unknown command: $cmd (use record|streak|suggest|list)" >&2; exit 2;;
esac
