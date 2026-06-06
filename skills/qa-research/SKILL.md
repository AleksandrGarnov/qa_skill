---
name: qa-research
description: Researches current best practices for the technologies and changes in a git branch, and turns them into concrete things to verify. Works on a bare Claude Code install via WebSearch. Use when you need fresh, sourced guidance for reviewing or testing a change, standalone or as part of a QA cycle.
argument-hint: "[git-branch]"
---

# QA Research

Gathers current, sourced best practices relevant to a branch's changes and converts them into **concrete checks**, not decorative notes. Standalone, and also used by `test-iteration`.

## 1. Identify topics

From the branch diff (use `"${CLAUDE_PLUGIN_ROOT}/scripts/branch-diff.sh" <branch> [base]` if available, otherwise `git diff --name-only origin/<base>...HEAD` inline), identify the affected technologies / behaviours worth researching (e.g. "JWT refresh rotation", "idempotent payment callbacks", "React Server Components caching").
**Done when:** you have a short, deduplicated topic list.

## 2. Research — tool-agnostic with fallbacks

Pick the first available search tool. The last option works on a bare Claude Code install, so research is never silently skipped unless truly nothing is available.

- Exa MCP (`mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`) → `context7` (for library/framework docs) → built-in **`WebSearch`** → only if none exist, mark **"research skipped: no search tool"** and continue.

**Loading Exa for subagents.** Exa tools may be deferred — a subagent first calls `ToolSearch query:"select:mcp__exa__web_search_exa,mcp__exa__web_fetch_exa"`. If a custom subagent doesn't receive MCP (a known Claude Code bug), run a `general-purpose` agent and name the full tool `mcp__exa__web_search_exa` in its prompt.

**Scale effort.** 1-2 topics → 1 agent; 3-5 topics → one agent per topic; don't spawn multiple agents for a single topic.

**One pass is not enough — drill the specifics.** A first broad search surfaces *names* (a mechanism, a class, a known failure mode); each specific that bears on the change gets a **follow-up search** to turn it into a concrete, testable scenario. Don't stop at the general hit and paste a summary — the value is the surfaced scenarios becoming checks, not the citation.

**Per-agent prompt** (avoid duplication): (a) the diff / changed files, (b) the one topic assigned to this agent, (c) the drill-specifics rule above, (d) output format below, (e) "done" = surfaced scenarios are concrete and sourced, specifics drilled, no filler.

## 3. Output — recommendations as evidence-checkable checks

Each finding must be actionable, sourced, and **turnable into a check whose pass needs a real observation** — not a note someone nods at. Phrase it as an **observable signal**, and tag the evidence type that would verify it (so it slots straight into `test-iteration`'s evidence-gate):

```
<recommendation> | check: <observable signal to verify> | evidence: observed-data|api-response|log|static | applies to: <area/behaviour> | source: <URL>
```

- `evidence: static` is for things settled by reading config/markup (e.g. a header is present); everything asserting **runtime behaviour** needs `observed-data`/`api-response`/`log` — a recommendation that can only be "confirmed" by reading the code is not yet a check.
- **Disposition every concrete scenario you surfaced — never silently drop it.** A specific scenario a search turned up (a named failure mode, a documented gotcha) is either turned into an observable `check:` **or** carried as an explicit `rejected: <why it doesn't apply here>`. Only a genuinely vague, non-observable note is dropped — and even that you name, not vanish. "Ran the search, wrote one summary line" is a failed pass.

**Done when:** every concrete scenario you surfaced is either an observable `check:` (with an `evidence:` type) or an explicit `rejected: <reason>`, specifics were drilled, and the result is sourced (or a clear "research skipped: <reason>" note).
