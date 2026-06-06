#!/usr/bin/env bash
# Context gate — enforces the system's non-skippable INPUT guidelines before a manifest is trusted.
# Structural (presence + substance of fetched artifacts), not semantic. The skill populates the
# manifest's `## Context` section by running TOOLS (gh pr view --comments, Jira fetch, prior-tests.sh,
# qa-research/Exa) — this gate fails closed if any required block is missing or empty, so the
# front-loaded steps the agent keeps skipping cannot be skipped.
#
# Required `## Context` sub-blocks (### headings, matched by keyword):
#   - Discussion  (GitHub PR + Jira comments)  -> guideline 1   (fetched content, or "no PR"/"no ticket")
#   - Prior tests                              -> guideline 4   (must state FRESH or RE-TEST)
#   - Research (Exa)                           -> guideline 2   (findings, or "research skipped: <reason>")
# (Guideline 2's "user-flow first" journey-rooting is enforced by verify-coverage.sh;
#  guideline 3 "never skip an item" by verify-coverage.)
#
# Usage: verify-context.sh <manifest.md>
# Output: CONTEXT-OK (exit 0) or a list of missing/empty blocks (exit 1).
set -uo pipefail

man="${1:?usage: verify-context.sh <manifest.md>}"
[ -f "$man" ] || { echo "MANIFEST-MISSING: $man"; exit 1; }

viol=0
fail() { echo "FAIL: $*"; viol=$((viol+1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# Emit, per ### block inside ## Context:  <lc-heading> \t <has-substance 0/1> \t <body text>
awk '
  /^## Context/ {inctx=1; next}
  inctx && /^## / {inctx=0}
  inctx && /^### / {
    if (hdr!="") emit()
    hdr=tolower($0); sub(/^###[[:space:]]*/,"",hdr); body=""; has=0; next
  }
  inctx && hdr!="" {
    line=$0; gsub(/^[[:space:]]+|[[:space:]]+$/,"",line)
    if (line=="") next
    if (substr(line,1,1)==">") next            # template guidance lines dont count as content
    if (line ~ /^<.*>$/) next                  # an unfilled <placeholder> doesnt count
    has=1; body=body" "line
  }
  END { if (hdr!="") emit() }
  function emit() { gsub(/\t/," ",body); print hdr "\t" has "\t" body }
' "$man" > "$tmp/blocks"

[ -s "$tmp/blocks" ] || fail "no '## Context' section with filled blocks — gather PR+Jira comments, prior-tests, and Exa research before approving the manifest"

# helper: find first block whose heading matches a keyword; echoes "<has>\t<body>"
block() { awk -F'\t' -v k="$1" 'tolower($1) ~ k {print $2"\t"$3; exit}' "$tmp/blocks"; }

# Guideline 1 — Discussion (GitHub PR + Jira comments)
d="$(block 'discussion|comment')"
if [ -z "$d" ]; then fail "guideline 1: no Discussion block (GitHub PR + Jira comments not fetched)"
elif [ "${d%%$'\t'*}" != "1" ]; then fail "guideline 1: Discussion block is empty — fetch the PR/Jira comments (or state 'no PR'/'no ticket')"; fi

# Guideline 4 — Prior tests (FRESH / RE-TEST)
p="$(block 'prior')"
if [ -z "$p" ]; then fail "guideline 4: no Prior tests block — run prior-tests.sh and record FRESH or RE-TEST"
else
  phas="${p%%$'\t'*}"; pbody="${p#*$'\t'}"
  if [ "$phas" != "1" ]; then fail "guideline 4: Prior tests block is empty"
  elif ! printf '%s' "$pbody" | grep -qiE 'FRESH|RE-TEST'; then fail "guideline 4: Prior tests block must state FRESH or RE-TEST (run prior-tests.sh; a re-test builds on the old docs)"; fi
fi

# Guideline 2 — Research (Exa) present (findings, or an explicit skip)
r="$(block 'research')"
if [ -z "$r" ]; then fail "guideline 2: no Research block — always run Exa for the checklist (or state 'research skipped: <reason>')"
elif [ "${r%%$'\t'*}" != "1" ]; then fail "guideline 2: Research block is empty — run Exa (or state 'research skipped: <reason>')"; fi

if [ "$viol" -eq 0 ]; then
  echo "CONTEXT-OK: discussion + prior-tests + research gathered before approval"
  exit 0
fi
echo "---"
echo "$viol context guideline(s) not satisfied — the manifest cannot be approved until the inputs are gathered"
exit 1
