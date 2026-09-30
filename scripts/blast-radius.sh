#!/usr/bin/env bash
# Blast-radius (M3) — for each CHANGED symbol, list the callers elsewhere in the codebase, so the
# reverse-dependencies of a change surface as REGRESSION items instead of being forgotten. Afferent
# coupling is risk: code many files depend on needs proportionally more regression coverage.
#
# Advisory, NOT a gate: it produces candidate regression targets for step-6 triage. (A hard gate on
# blast-radius would be noisy/flaky — reverse-dep detection is heuristic; the Test-Gap gate stays the
# hard floor.) Uses plain recursive grep so it needs no git index and is portable/testable.
#
# Usage:
#   blast-radius.sh <branch> [base]                    # derive changed symbols, grep the repo root
#   blast-radius.sh --surfaces <file> [--root <dir>]   # explicit surfaces list + search root (tests)
# Output (one line per changed symbol with a name):
#   <symbol>  (<defining file>)  <-  caller1, caller2      | or "(no external callers found)"
set -uo pipefail

surfaces_file=""; root=""
if [ "${1:-}" = "--surfaces" ]; then
  surfaces_file="${2:-}"; shift 2 || true
  [ "${1:-}" = "--root" ] && { root="${2:-}"; shift 2 || true; }
  [ -n "$surfaces_file" ] && [ -f "$surfaces_file" ] || { echo "usage: blast-radius.sh --surfaces <file> [--root <dir>]" >&2; exit 2; }
  [ -n "$root" ] || root="$PWD"
else
  branch="${1:-}"; base="${2:-}"
  [ -n "$branch" ] || { echo "usage: blast-radius.sh <branch> [base] | --surfaces <file> [--root <dir>]" >&2; exit 2; }
  here="$(cd "$(dirname "$0")" && pwd)"
  surfaces_file="$(mktemp)"; trap 'rm -f "$surfaces_file"' EXIT
  "$here/changed-surfaces.sh" "$branch" "$base" > "$surfaces_file" || { echo "ERROR: could not enumerate changed surfaces" >&2; exit 1; }
  root="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
fi

# Extract the defining file + a symbol name from each "file::context" surface (bare files have no
# symbol to trace and are skipped here — they are already covered by the Test-Gap gate).
printf '%s\n' "# blast-radius: reverse-dependencies of changed symbols (regression candidates)"
found_any=0
while IFS= read -r line; do
  case "$line" in ""|\#*) continue;; esac
  case "$line" in *"::"*) : ;; *) continue;; esac        # only symbol surfaces
  deffile="${line%%::*}"
  ctx="${line#*::}"
  # the identifier immediately before the last "(" — a language-agnostic function-name heuristic
  name="$(printf '%s' "$ctx" | grep -oE '[A-Za-z_][A-Za-z0-9_]*\(' | tail -1 | sed 's/($//; s/(//')"
  [ -n "$name" ] || continue
  found_any=1
  callers="$(grep -rlIw "$name" "$root" 2>/dev/null \
    | grep -vE '(/tests?/|/__tests__/|/__mocks__/|/spec/|\.test\.|\.spec\.|/node_modules/|/vendor/|/dist/|/build/|/\.git/)' \
    | grep -vF "$deffile" | sort -u)"
  if [ -n "$callers" ]; then
    joined="$(printf '%s' "$callers" | sed "s#^$root/##" | paste -sd, - | sed 's/,/, /g')"
    printf '%s  (%s)  <-  %s\n' "$name" "$deffile" "$joined"
  else
    printf '%s  (%s)  <-  (no external callers found)\n' "$name" "$deffile"
  fi
done < "$surfaces_file"

[ "$found_any" = "1" ] || printf '%s\n' "(no named symbols in the changed surfaces — file-level changes only; rely on the Test-Gap map)"
