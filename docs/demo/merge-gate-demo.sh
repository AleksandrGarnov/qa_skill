#!/usr/bin/env bash
# Self-contained demo of the merge-gate hook for the README GIF.
#
# It builds a throwaway QA scene (a frozen manifest + a report) in a temp dir and runs the
# REAL hook handler (scripts/finalize-gate.sh) against a simulated `git merge` PreToolUse event —
# first with a red gate (a checklist item left 'not executed'), then after the gap is fixed.
# Nothing here is faked: the same verify-context / verify-report / verify-coverage scripts that
# guard a real run decide the outcome. No network, no git writes; cleans up after itself.
#
# Usage: bash docs/demo/merge-gate-demo.sh
set -uo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
gate="$repo/scripts/finalize-gate.sh"
scene="$(mktemp -d)"; trap 'rm -rf "$scene"' EXIT

beat() { sleep "${DEMO_BEAT:-1.4}"; }
say()  { printf '\033[2m%s\033[0m\n' "$*"; }     # dim narration
cmd()  { printf '\033[36m$ %s\033[0m\n' "$*"; }  # cyan prompt line

# --- frozen, approved checklist manifest (context + journeys + items) ---
cat > "$scene/manifest.md" <<'EOF'
## Context

### Discussion
- PR #42 reviewed; Jira PROJ-123 comments fetched — no blocking concerns.

### Prior tests
FRESH — no earlier QA run for this branch.

### Research (Exa)
- Auth-flow edge cases and rate-limit guidance folded into the items below.

## Journeys

| J  | Journey                                  |
|----|------------------------------------------|
| J1 | User logs in                             |

## Items

| ID | Journey | Check                                       |
|----|---------|---------------------------------------------|
| 1  | J1      | Valid login returns 200 + session cookie    |
| 2  | J1      | Wrong password returns 401, no session      |
EOF

# --- report v1: item 2 left 'not executed' under a clean GO -> gates go red ---
cat > "$scene/report.md" <<'EOF'
**Prior-test basis:** FRESH

## Checklist results

| # | Check          | Result        | Evidence                                   |
|---|----------------|---------------|--------------------------------------------|
| 1 | Valid login    | pass          | 200 + Set-Cookie observed (raw log quoted) |
| 2 | Wrong password | not executed  | n/a                                        |

**Verdict: GO**
EOF

cat > "$scene/qa-run.json" <<EOF
{ "manifest": "$scene/manifest.md", "report": "$scene/report.md", "branch": "feature/PROJ-123-login" }
EOF

# Simulate the Claude Code PreToolUse(Bash) event for a branch merge.
fire_gate() {
  printf '{"tool_input":{"command":"git merge feature/PROJ-123-login"},"cwd":"%s"}' "$scene" \
    | QA_RUN_STATE="$scene/qa-run.json" bash "$gate"
}

clear
say "A QA run is active on feature/PROJ-123-login. The agent goes to merge it."
beat
cmd "git merge feature/PROJ-123-login    # (Claude Code fires the PreToolUse hook)"
beat
fire_gate; rc=$?
printf '\033[31m  → blocked, exit %s\033[0m\n' "$rc"
beat; beat

say "Item 2 (wrong-password path) was never run, but the report says GO. The gate won't allow that."
say "QA runs item 2, records the 401 with evidence, and the report is completed."
beat

# --- report v2: item 2 executed with evidence -> gates go green ---
cat > "$scene/report.md" <<'EOF'
**Prior-test basis:** FRESH

## Checklist results

| # | Check          | Result | Evidence                                       |
|---|----------------|--------|------------------------------------------------|
| 1 | Valid login    | pass   | 200 + Set-Cookie observed (raw log quoted)     |
| 2 | Wrong password | pass   | 401 returned, no Set-Cookie (raw response cited) |

**Verdict: GO**
EOF

cmd "git merge feature/PROJ-123-login    # retry — gates re-checked"
beat
fire_gate; rc=$?
printf '\033[32m  → allowed, exit %s\033[0m\n' "$rc"
beat
say "The merge proceeds — and only because every acceptance criterion is backed by a real observation."
