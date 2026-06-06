#!/usr/bin/env bash
# Self-contained tests for verify-context.sh (system input-guideline gate: discussion / prior / research).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VC="$SCRIPT_DIR/verify-context.sh"
pass=0; fail=0
assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then echo "ok   - $desc"; pass=$((pass+1))
  else echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1)); fi
}
rc() { "$VC" "$1" >/dev/null 2>&1; echo "$?"; }
tmp="$(mktemp -d)"

# Full, valid context -> CONTEXT-OK (0)
cat > "$tmp/full.md" <<'MD'
# Checklist manifest
## Context
> guidance line that should not count as content
### Discussion — GitHub PR + Jira
PR #3146: reviewer flagged Redis desync window. Jira QA-9735: dev says repair runs on worker.
### Prior tests
RE-TEST of QA-9735-2026-06-04.md@92e314ad8 — carried R1 findings: BUG-01 balance drift (open).
### Research (Exa)
Octane RollbackOpenTransactions leaks tx across requests -> item 3; Sanctum token visibility -> item 5.
## Items
| ID | Must | Journey | What to run | Expected |
|----|------|---------|-------------|----------|
| 1 | yes | J1 | `curl /charge` | ok |
MD
assert_eq "full context -> exit 0" "0" "$(rc "$tmp/full.md")"

# Research as an explicit skip -> still OK
cat > "$tmp/skip.md" <<'MD'
# Checklist manifest
## Context
### Discussion
PR: no PR for this branch. Jira QA-1: no comments.
### Prior tests
FRESH — first test (prior-tests.sh = NONE)
### Research (Exa)
research skipped: no search tool on this install
## Items
| ID | Must | Journey | What to run | Expected |
|----|------|---------|-------------|----------|
| 1 | — | J1 | `x` | ok |
MD
assert_eq "research skipped (explicit) -> exit 0" "0" "$(rc "$tmp/skip.md")"

# Missing Discussion block -> FAIL
cat > "$tmp/no_disc.md" <<'MD'
# Checklist manifest
## Context
### Prior tests
FRESH
### Research (Exa)
findings here
## Items
| ID | Must | Journey | What | Exp |
MD
assert_eq "missing discussion -> exit 1" "1" "$(rc "$tmp/no_disc.md")"

# Discussion block present but empty (only a placeholder) -> FAIL
cat > "$tmp/empty_disc.md" <<'MD'
# Checklist manifest
## Context
### Discussion
<fetched comments here>
### Prior tests
FRESH
### Research (Exa)
findings
## Items
| ID | Must | Journey | What | Exp |
MD
assert_eq "empty discussion (placeholder) -> exit 1" "1" "$(rc "$tmp/empty_disc.md")"

# Prior block without FRESH/RE-TEST -> FAIL
cat > "$tmp/bad_prior.md" <<'MD'
# Checklist manifest
## Context
### Discussion
PR comments fetched here.
### Prior tests
checked, looks fine
### Research (Exa)
findings
## Items
| ID | Must | Journey | What | Exp |
MD
assert_eq "prior without FRESH/RE-TEST -> exit 1" "1" "$(rc "$tmp/bad_prior.md")"

# Missing Research block -> FAIL
cat > "$tmp/no_research.md" <<'MD'
# Checklist manifest
## Context
### Discussion
PR comments here.
### Prior tests
FRESH
## Items
| ID | Must | Journey | What | Exp |
MD
assert_eq "missing research -> exit 1" "1" "$(rc "$tmp/no_research.md")"

# No ## Context section at all -> FAIL
cat > "$tmp/none.md" <<'MD'
# Checklist manifest
## Items
| ID | Must | Journey | What | Exp |
| 1 | yes | J1 | x | ok |
MD
assert_eq "no Context section -> exit 1" "1" "$(rc "$tmp/none.md")"

# Missing file -> exit 1
assert_eq "missing file -> exit 1" "1" "$(rc "$tmp/nope.md")"

rm -rf "$tmp"
echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
