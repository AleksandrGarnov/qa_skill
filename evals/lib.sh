# evals/lib.sh — shared helpers for the maintainer-only behavioral eval harness.
#
# NOT part of the plugin: no skill references evals/, and nothing here runs during a user's QA run.
# Sourced (never executed) by evals/run.sh and each scenario's check.sh.
#
# Provides: assertion helpers, a hash-based "source unchanged" check, run_scenario() which drives one
# headless Claude Code session with this plugin loaded, and Skill-invocation probes read from the raw
# event stream (so "the skill never activated" and "it activated, then misbehaved" stay distinct bugs).

_sha() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Hash every source file in a workdir, ignoring eval bookkeeping, git internals, and transient
# artifacts a run may legitimately create (caches, the QA run-state, QA docs the skill writes).
_manifest() {
  ( cd "$1" 2>/dev/null && find . -type f \
      -not -name '.eval-*' \
      -not -path './.git/*' \
      -not -path './.claude/*' \
      -not -path './qa-docs/*' \
      -not -path '*/__pycache__/*' -not -name '*.pyc' \
      -not -path '*/node_modules/*' \
      -not -name '.DS_Store' \
    | LC_ALL=C sort \
    | while IFS= read -r f; do printf '%s  %s\n' "$(_sha "$f")" "$f"; done )
}

snapshot_source() { _manifest "$1" > "$1/.eval-orig-manifest"; }

: "${EVAL_FAILED:=0}"
ok()  { printf '    \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '    \033[31m✗\033[0m %s\n' "$*"; EVAL_FAILED=1; }

# assert_grep "desc" "ERE" file / refute_grep "desc" "ERE" file — case-insensitive.
assert_grep() { if [ -f "$3" ] && grep -qiE "$2" "$3" 2>/dev/null; then ok "$1"; else bad "$1"; fi; }
refute_grep() { if [ -f "$3" ] && grep -qiE "$2" "$3" 2>/dev/null; then bad "$1"; else ok "$1"; fi; }

# The read-only invariant: no source file changed since snapshot_source.
assert_source_unchanged() {
  local after diff_out
  after="$(mktemp)"; _manifest "$WORKDIR" > "$after"
  diff_out="$(diff "$WORKDIR/.eval-orig-manifest" "$after" 2>/dev/null)"
  rm -f "$after"
  if [ -z "$diff_out" ]; then ok "$1"; else bad "$1 — source tree changed:"; echo "$diff_out" | sed 's/^/        /'; fi
}

# assert_file_changed "desc" "relative/path" — the mirror: a fix WAS applied.
assert_file_changed() {
  local before after
  before="$(grep "  \./$2\$" "$WORKDIR/.eval-orig-manifest" | awk '{print $1}')"
  after="$(_sha "$WORKDIR/$2" 2>/dev/null)"
  if [ -n "$before" ] && [ "$before" != "$after" ]; then ok "$1"; else bad "$1 — $2 unchanged"; fi
}

# Skill names invoked in the run (one per line), filtered by an optional Python regex.
# Plugin skills may appear namespaced ("qa-skill:test-iteration") or bare ("test-iteration").
QA_SKILLS_RE='(^|:)(test-iteration|branch-review|qa-research|jira-context|qa-interview|qa-learn)$'
skill_invocations() {
  local events="$WORKDIR/.eval-events.jsonl" pattern="${1:-}"
  [ -f "$events" ] || return 0
  python3 -I - "$events" "$pattern" 2>/dev/null <<'PY'
import json, re, sys
events, pattern = sys.argv[1], re.compile(sys.argv[2])
for line in open(events, errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") != "assistant":
        continue
    for c in d.get("message", {}).get("content", []):
        if c.get("type") == "tool_use" and c.get("name") == "Skill":
            name = str(c.get("input", {}).get("skill", ""))
            if pattern.search(name):
                print(name)
PY
}

assert_skill_invoked() {
  local hits; hits="$(skill_invocations "$2")"
  if [ -n "$hits" ]; then ok "$1 ($(echo "$hits" | sort -u | tr '\n' ' ' | sed 's/ $//'))"
  else bad "$1 — no Skill call matching '$2' in the event stream"; fi
}

refute_skill_invoked() {
  local hits; hits="$(skill_invocations "$2")"
  if [ -z "$hits" ]; then ok "$1"; else bad "$1 — invoked: $(echo "$hits" | sort -u | tr '\n' ' ')"; fi
}

# run_scenario <workdir> <prompt> — one headless session with this plugin loaded.
# Permissions are bypassed on purpose, inside a throwaway copy, so the run CAN do anything and the
# checks then prove what it chose not to do. Spend is hard-capped per run by --max-budget-usd.
#
# Output is captured twice: the raw event stream (.eval-events.jsonl — tool calls, for Skill probes)
# and the flattened assistant text ($TRANSCRIPT — for the *_grep assertions).
run_scenario() {
  local workdir="$1" prompt="$2"
  local events="$workdir/.eval-events.jsonl"
  ( cd "$workdir" && claude --print \
      --output-format stream-json --verbose \
      --no-session-persistence \
      --plugin-dir "$PLUGIN_DIR" \
      --model "$MODEL" \
      --max-budget-usd "$BUDGET" \
      --permission-mode bypassPermissions \
      "$prompt" ) > "$events" 2>&1

  python3 -I - "$events" > "$TRANSCRIPT" 2>/dev/null <<'PY' || cp "$events" "$TRANSCRIPT"
import json, sys
for line in open(sys.argv[1], errors="replace"):
    line = line.strip()
    if not line.startswith("{"):
        print(line)
        continue
    try:
        d = json.loads(line)
    except ValueError:
        continue
    if d.get("type") == "assistant":
        for c in d.get("message", {}).get("content", []):
            if c.get("type") == "text":
                print(c.get("text", ""))
            # structured findings tools carry the content a text-only grep would miss
            elif c.get("type") == "tool_use" and c.get("name") in ("ReportFindings",):
                print(json.dumps(c.get("input", {}), ensure_ascii=False))
    elif d.get("type") == "result" and isinstance(d.get("result"), str):
        print(d["result"])
PY
}

# Every check.sh ends with this: its exit code is the scenario verdict.
eval_finish() { exit "$EVAL_FAILED"; }
