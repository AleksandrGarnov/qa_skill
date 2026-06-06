#!/usr/bin/env bash
# Lists prior QA test docs (reports/checklists) for a task, so test-iteration
# starts from existing findings instead of testing from scratch. Read-only.
#
# Makes the "did we already test this?" check a deterministic step the model
# RUNS, not a prose instruction it can skip.
#
# Usage: prior-tests.sh <docs-dir> <key-or-id> [extra-id]
#   <docs-dir>   directory where prior test docs live (the path stated in CLAUDE.md)
#   <key-or-id>  Jira key or task id to match (e.g. QA-9801)
#   [extra-id]   optional second identifier (e.g. the branch name)
#
# Output:
#   DOCS-PATH-MISSING: <dir>   the configured docs dir does not exist (confirm path)
#   NONE                       no prior doc matches this task
#   PRIOR-DOCS (newest first): followed by matching file paths (newest first)
# Exit code is always 0 (it's a lookup, not a gate); the caller reads the output.
set -uo pipefail

dir="${1:?usage: prior-tests.sh <docs-dir> <key-or-id> [extra-id]}"
key="${2:?key/id required}"
extra="${3:-}"

if [ ! -d "$dir" ]; then
  echo "DOCS-PATH-MISSING: $dir"
  echo "(the test-docs path from CLAUDE.md does not exist — confirm it before concluding 'no prior tests')"
  exit 0
fi

# Match the key (and optional extra id) in filename OR file content, case-insensitive,
# as a fixed string (Jira keys aren't regexes). Union, de-duplicated.
matches="$(
  {
    find "$dir" -type f -iname "*${key}*" 2>/dev/null
    grep -rilF -- "$key" "$dir" 2>/dev/null
    if [ -n "$extra" ]; then
      find "$dir" -type f -iname "*${extra}*" 2>/dev/null
      grep -rilF -- "$extra" "$dir" 2>/dev/null
    fi
  } | sort -u
)"

if [ -z "$matches" ]; then
  echo "NONE"
  exit 0
fi

echo "PRIOR-DOCS (newest first):"
# Newest first. Test-doc filenames don't contain spaces/newlines; split on newlines.
IFS='
'
# shellcheck disable=SC2086
ls -t $matches 2>/dev/null
