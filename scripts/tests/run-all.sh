#!/usr/bin/env bash
# Runs every *.test.sh in this directory and exits non-zero if any suite fails.
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
failed=0

for t in "$DIR"/*.test.sh; do
  echo "==> $(basename "$t")"
  if bash "$t"; then :; else failed=$((failed+1)); fi
  echo
done

if [ "$failed" -eq 0 ]; then
  echo "ALL SUITES PASSED"
else
  echo "$failed SUITE(S) FAILED"
fi
[ "$failed" -eq 0 ]
