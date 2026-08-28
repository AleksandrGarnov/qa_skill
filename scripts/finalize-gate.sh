#!/usr/bin/env bash
# PreToolUse hook handler — the HARD, agent-proof enforcement of the QA gates.
#
# The verdict gates (verify-context / verify-report / verify-coverage) used to run at step 9,
# i.e. the agent had to remember to run them — so a negligent agent could skip the gate itself.
# This handler moves enforcement OUT of the agent's step list: Claude Code fires it BEFORE the
# irreversible action (a `git merge` / `git push`), and `exit 2` blocks that action when a QA run
# is in progress but its gates aren't green. The agent cannot talk past it — it's outside the
# token stream.
#
# Wiring: hooks/hooks.json registers this on PreToolUse(Bash). It is a no-op unless (a) the command
# is a git merge/push AND (b) a QA run-state file exists (written by test-iteration at steps 7 & 9).
# So it never interferes with ordinary pushes when no QA is in progress — it only guarantees that,
# once a QA run is started, you cannot merge it without CONTEXT-OK + REPORT-OK + COVERAGE-OK
# and, when JSON sidecars are present, EVIDENCE-OK.
#
# Run-state file (written by the skill): $CLAUDE_PROJECT_DIR/.claude/qa-run.json (override: $QA_RUN_STATE)
# Legacy minimum:
#   { "manifest": "<abs path>", "report": "<abs path>", "branch": "<name>" }
# Richer sidecar-aware shape (backward-compatible):
#   {
#     "schemaVersion": 1,
#     "runId": "...",
#     "status": "approved|running|retesting|...",
#     "manifest": "<abs path>",
#     "manifestMd": "<abs path>",
#     "manifestJson": "<abs path>",
#     "report": "<abs path>",
#     "reportMd": "<abs path>",
#     "reportJson": "<abs path>",
#     "branch": "<name>",
#     "gates": {"context":"pending|green|red", ...}
#   }
#
# Exit: 0 = allow (not our concern / gates green) · 2 = BLOCK (gates red / report missing mid-run).
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- read the PreToolUse event ---
input="$(cat 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"

# Only engage on a branch-finalizing action (git merge/push, gh pr merge). Anything else: allow.
printf '%s' "$cmd" | grep -qE '(^|[^[:alnum:]])(git[[:space:]]+(merge|push)|gh[[:space:]]+pr[[:space:]]+merge)([^[:alnum:]]|$)' || exit 0

# --- locate the QA run-state ---
proj="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"
state="${QA_RUN_STATE:-$proj/.claude/qa-run.json}"

# No QA run in progress -> this hook is a QA gate, not a general merge policy. Allow.
[ -f "$state" ] || exit 0

manifest="$(jq -r '.manifestMd // .manifest // empty' "$state" 2>/dev/null || true)"
report="$(jq -r '.reportMd // .report // empty' "$state" 2>/dev/null || true)"
manifest_json="$(jq -r '.manifestJson // empty' "$state" 2>/dev/null || true)"
report_json="$(jq -r '.reportJson // empty' "$state" 2>/dev/null || true)"
schema_version="$(jq -r '.schemaVersion // empty' "$state" 2>/dev/null || true)"

block() { echo "⛔ MERGE BLOCKED by QA gate: $*" >&2; echo "   (a QA run is active: $state)" >&2; exit 2; }

[ -n "$manifest" ] && [ -f "$manifest" ] || block "no frozen checklist manifest found — approve a manifest (step 7) before merging"
[ -n "$report" ] && [ -f "$report" ] || block "no test report yet — a QA run is in progress for this branch but has no report; finish it before merging"

# A SIDECAR-AWARE run-state (schemaVersion set, or any sidecar path declared) MUST carry both JSON
# sidecars + the artifacts index and pass EVIDENCE-OK. Keying "run the evidence gate" on BOTH
# sidecars being non-empty let an empty reportJson silently opt out of the evidence gate mid-run —
# and the agent writes this file. So once a structured run is started, an absent/empty sidecar is a
# BLOCK, not a skip. A legacy {manifest,report,branch} state has none of these and legitimately skips.
sidecar_aware=0
if [ -n "$schema_version" ] || [ -n "$manifest_json" ] || [ -n "$report_json" ]; then
  sidecar_aware=1
fi

# --- run the gates; any red blocks the merge ---
fails=""
"$here/verify-context.sh"  "$manifest"             >/dev/null 2>&1 || fails="$fails CONTEXT"
"$here/verify-report.sh"   "$report"               >/dev/null 2>&1 || fails="$fails REPORT"
"$here/verify-coverage.sh" "$manifest" "$report"  >/dev/null 2>&1 || fails="$fails COVERAGE"
if [ "$sidecar_aware" -eq 1 ]; then
  [ -n "$manifest_json" ] && [ -f "$manifest_json" ] || block "sidecar-aware QA run but manifestJson is empty/missing on disk — regenerate the bundle (the evidence gate can't be skipped once a structured run is started)"
  [ -n "$report_json" ] && [ -f "$report_json" ] || block "sidecar-aware QA run but reportJson is empty/missing on disk — regenerate the bundle (the evidence gate can't be skipped once a structured run is started)"
  artifacts_json="$(jq -r '.artifactsIndexJson // empty' "$state" 2>/dev/null || true)"
  [ -n "$artifacts_json" ] && [ -f "$artifacts_json" ] || block "artifactsIndexJson is required for a sidecar-aware run — regenerate the bundle before merging"
  "$here/verify-evidence.sh" "$manifest_json" "$report_json" "$artifacts_json" >/dev/null 2>&1 || fails="$fails EVIDENCE"
fi

if [ -n "$fails" ]; then
  block "gate(s) not green:$fails — run them to see why (context not gathered, a dropped or not-executed checklist item, an incomplete report, or invalid structured evidence). Fix and re-verify before merging."
fi

echo "✅ QA gates green (CONTEXT-OK · REPORT-OK · COVERAGE-OK${manifest_json:+ · EVIDENCE-OK}) — merge allowed." >&2
exit 0
