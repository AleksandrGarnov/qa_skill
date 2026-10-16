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
# is a git merge/push (or gh pr merge) AND (b) a QA run-state file exists (written by test-iteration at
# steps 7 & 9) AND (c) the command operates on the run-state's OWN branch — a push/merge of a DIFFERENT
# branch in the same working copy is allowed (it is not this run's concern; we only relax when we can
# prove a different branch, never opening a bypass). So it never interferes with unrelated pushes — it
# only guarantees that, once a QA run is started, you cannot merge THAT branch without CONTEXT-OK +
# REPORT-OK + COVERAGE-OK and, when JSON sidecars are present, SIDECARS-OK (md/json item IDs agree) +
# EVIDENCE-OK.
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
#     "surfaces": "<abs path>",   # frozen changed-surfaces.sh list -> enables the Test-Gap (GAP) gate
#     "knowledge": "<abs path>",  # qa-knowledge.md -> enables the Learned-risk (LEARNED) gate (needs surfaces too)
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

# Only engage on a branch-finalizing action. Allow `git [global-opts] push|merge` — so
# `git -C <dir> push`, `git -c k=v push`, `git --no-pager push` are NOT a silent bypass — plus
# `gh pr merge`. Anything else: allow.
git_push_merge='(^|[^[:alnum:]])git([[:space:]]+--?[A-Za-z][^[:space:]]*([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+(push|merge)([^[:alnum:]]|$)'
gh_pr_merge='(^|[^[:alnum:]])gh[[:space:]]+pr[[:space:]]+merge([^[:alnum:]]|$)'
printf '%s' "$cmd" | grep -qE "$git_push_merge|$gh_pr_merge" || exit 0

# --- locate the QA run-state ---
proj="${CLAUDE_PROJECT_DIR:-${cwd:-$PWD}}"
state="${QA_RUN_STATE:-$proj/.claude/qa-run.json}"

# No QA run in progress -> this hook is a QA gate, not a general merge policy. Allow.
[ -f "$state" ] || exit 0

manifest="$(jq -r '.manifestMd // .manifest // empty' "$state" 2>/dev/null || true)"
report="$(jq -r '.reportMd // .report // empty' "$state" 2>/dev/null || true)"
manifest_json="$(jq -r '.manifestJson // empty' "$state" 2>/dev/null || true)"
report_json="$(jq -r '.reportJson // empty' "$state" 2>/dev/null || true)"
surfaces="$(jq -r '.surfaces // empty' "$state" 2>/dev/null || true)"
knowledge="$(jq -r '.knowledge // empty' "$state" 2>/dev/null || true)"
schema_version="$(jq -r '.schemaVersion // empty' "$state" 2>/dev/null || true)"
state_branch="$(jq -r '.branch // empty' "$state" 2>/dev/null || true)"

# --- scope the gate to the QA run's OWN branch ---
# This gate guards ONE branch's QA run (state.branch). A push/merge operating on a DIFFERENT branch in
# the same working copy is not this run's concern — blocking it is a false positive. Resolve the branch
# the command operates on and, ONLY when we're confident it's a different branch, allow. We never relax
# when the command could touch the QA branch (its HEAD is the QA branch, or the QA branch is named in
# the command) — so this strictly removes false blocks without opening a bypass. A legacy state with no
# `branch`, or an undeterminable current branch, leaves behaviour unchanged (enforce).
repo_dir="${cwd:-$PWD}"
case "$cmd" in
  *" -C "*) repo_dir="$(printf '%s' "$cmd" | sed -E 's/.*[[:space:]]-C[[:space:]]+([^[:space:]]+).*/\1/')";;
esac
if printf '%s' "$cmd" | grep -qE "$gh_pr_merge"; then
  pr_num="$(printf '%s' "$cmd" | sed -E 's/.*gh[[:space:]]+pr[[:space:]]+merge[[:space:]]+#?([0-9]+).*/\1/')"
  cur_branch="$( (cd "$repo_dir" 2>/dev/null && gh pr view "$pr_num" --json headRefName -q .headRefName) 2>/dev/null || true)"
else
  cur_branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
if [ -n "$state_branch" ] && [ -n "$cur_branch" ] && [ "$cur_branch" != "$state_branch" ] \
   && ! printf '%s' "$cmd" | grep -qF "$state_branch"; then
  exit 0   # operating on a different branch than this QA run — not our concern
fi

block() { echo "⛔ MERGE BLOCKED by QA gate: $*" >&2; echo "   (QA run: $state)" >&2; exit 2; }

[ -n "$manifest" ] && [ -f "$manifest" ] || block "QA run on branch '${state_branch:-?}' has no frozen checklist manifest — approve one (step 7) before merging"
[ -n "$report" ] && [ -f "$report" ] || block "QA run on branch '${state_branch:-?}' has no test report yet (you are on '${cur_branch:-?}') — finish it, or clear $state if that run was abandoned"

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
# Test-Gap gate — only when the run-state froze a surfaces list (backward-compatible: a legacy run
# without `.surfaces` skips GAP, exactly like the sidecar gates). When present, every changed
# behaviour-surface must map to a covering item or a reasoned N/A, or the merge is blocked.
if [ -n "$surfaces" ] && [ -f "$surfaces" ]; then
  "$here/verify-gap.sh" "$manifest" "$surfaces" >/dev/null 2>&1 || fails="$fails GAP"
fi
# Learned-risk gate — only when the run-state points at a knowledge base AND a surfaces list exist
# (backward-compatible: absent either one skips LEARNED). A changed component with a known recurring
# risk must be addressed in the manifest's ## Learned risks section.
if [ -n "$knowledge" ] && [ -f "$knowledge" ] && [ -n "$surfaces" ] && [ -f "$surfaces" ]; then
  "$here/verify-learned.sh" "$manifest" "$knowledge" "$surfaces" >/dev/null 2>&1 || fails="$fails LEARNED"
fi
if [ "$sidecar_aware" -eq 1 ]; then
  [ -n "$manifest_json" ] && [ -f "$manifest_json" ] || block "sidecar-aware QA run but manifestJson is empty/missing on disk — regenerate the bundle (the evidence gate can't be skipped once a structured run is started)"
  [ -n "$report_json" ] && [ -f "$report_json" ] || block "sidecar-aware QA run but reportJson is empty/missing on disk — regenerate the bundle (the evidence gate can't be skipped once a structured run is started)"
  artifacts_json="$(jq -r '.artifactsIndexJson // empty' "$state" 2>/dev/null || true)"
  [ -n "$artifacts_json" ] && [ -f "$artifacts_json" ] || block "artifactsIndexJson is required for a sidecar-aware run — regenerate the bundle before merging"
  # md-only gates and the json-only evidence gate read different files — cross-check they agree first,
  # so neither can pass on a picture the other doesn't share (out-of-sync item IDs across md/json).
  "$here/verify-sidecars.sh" "$manifest" "$manifest_json" "$report" "$report_json" >/dev/null 2>&1 || fails="$fails SIDECARS"
  "$here/verify-evidence.sh" "$manifest_json" "$report_json" "$artifacts_json" >/dev/null 2>&1 || fails="$fails EVIDENCE"
fi

if [ -n "$fails" ]; then
  block "gate(s) not green:$fails — run them to see why (context not gathered, a dropped or not-executed checklist item, an incomplete report, or invalid structured evidence). Fix and re-verify before merging."
fi

echo "✅ QA gates green (CONTEXT-OK · REPORT-OK · COVERAGE-OK${surfaces:+ · GAP-OK}${knowledge:+ · LEARNED-OK}${manifest_json:+ · SIDECARS-OK · EVIDENCE-OK}) — merge allowed." >&2
exit 0
