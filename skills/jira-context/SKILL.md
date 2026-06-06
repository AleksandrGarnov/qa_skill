---
name: jira-context
description: Resolves the Jira issue key for a git branch and pulls the ticket's essence — summary, acceptance criteria, and (for bugs) reproduction steps — as a structured context block for QA. Works without the Atlassian MCP via a manual-paste fallback. Use when you need the requirement/AC context behind a change, standalone or as part of a QA cycle.
argument-hint: "[git-branch]"
---

# Jira Context

Turns a git branch into the **requirement context behind it**: finds the Jira key, fetches the ticket, and extracts acceptance criteria + reproduction steps as concrete, traceable inputs for QA. Standalone, and also used by `test-iteration` (step 1). Read-only — it never writes to Jira.

## 1. Resolve the ticket key (deterministic)

Run the bundled script — do not guess the key:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/jira-key.sh" <branch> [base]
```

It extracts a key in the official Jira format (`[A-Z][A-Z]+-[0-9]+`) from, in priority order: **branch name → PR title (`gh`) → non-merge commit messages**, and prints `key:` + `source:`. If `${CLAUDE_PLUGIN_ROOT}` is unset (manual install) or the script is missing, run the equivalent inline: `printf '%s' "<branch>" | grep -oE '[A-Z][A-Z]+-[0-9]+' | head -n1`.
**Done when:** you have a key + its source, or `NONE`.

## 2. Fetch the ticket — tool-agnostic with fallback

- If a key was found **and** the Atlassian MCP is available, fetch it. The MCP tools may be deferred — first `ToolSearch query:"select:mcp__plugin_atlassian_atlassian__getJiraIssue"` to load the schema, then call `getJiraIssue` for the key. Request the fields QA needs: `summary, issuetype, description, priority, components, labels, status, issuelinks`, plus whether attachments exist. Skip worklog, watchers, sprint metadata, estimates — noise for test design.
- **Pull the signal comments** (not the whole noisy thread). The discussion carries what the description doesn't — and for a re-test it *is* the spec of what to verify. Extract: **QA findings / return-to-rework** comments, **developer "fixed / pushed" replies** (which finding, which commit), **reviewer blockers/decisions**, and any **status transition** notes. Filter out bot noise (CodeRabbit/Copilot summaries) to a skim. **A `status` like "Awaiting testing" / "Returned for rework" means this is a re-test — pulling the comments is then mandatory, not optional.**
- If the key is `NONE` or the MCP is unavailable, **ask the user to paste the ticket text** (summary + description + acceptance criteria + the relevant comments). Never invent the ticket.

**Done when:** you have the ticket's summary, type, description, metadata, AND the signal comments (or a clear "no ticket: <reason>" note) — flag explicitly if the status implies a re-test.

## 3. Extract acceptance criteria + repro

Find acceptance criteria by walking an **ordered source chain** — stop at the first source that yields concrete, testable criteria, and **record which source they came from** (so a thin source is visible, not hidden):

1. **`description` AC blocks** (primary for this project) — `Given/When/Then`, a checklist, or numbered "must/should" statements.
2. **Dedicated AC custom field** — only if (1) is empty: `getJiraIssueTypeMetaWithFields` to find a field named like *Acceptance Criteria*; read it if present.
3. **Checklist-app field / panel** — only if (1)–(2) are empty and the project uses one (its items surface in a custom field).
4. **Linked requirement / parent story** — only if (1)–(3) are empty and an `issuelink` points to a spec.

Each step is **bounded** — try it once, don't loop. If the chain is exhausted with nothing concrete, that is the **AC-missing** flag below (a signal, not a prompt to keep digging or to invent).

- **AC found:** list them as discrete, checkable items, each with a short id (`AC1`, `AC2`, …).
- **Tag each AC `runtime` or `static`:** `runtime` = asserts what the system *does* (computes, stores, returns, transitions) and therefore needs observed/API/log evidence downstream; `static` = a pure UI-copy / presence / layout fact that a read or screenshot settles. This tag feeds `test-iteration`'s evidence-gate — a `runtime` AC can't be closed on code-read or a mocked unit test alone.
- **AC missing or partial:** flag it explicitly — **"AC missing/inferred"** — and do not silently invent tests. Missing testable criteria is a signal, not a license to guess.
- **AC implicit (buried in prose):** reconstruct them as `Given/When/Then`, written **declaratively** (behaviour, not UI selectors), and add the obvious edge/negative cases. Mark each reconstructed item "inferred — confirm with PO".
- **For a bug ticket** (`issuetype` = Bug): also extract **Steps to Reproduce**, **Expected**, and **Actual** from the description; flag any that is missing.

## 4. Output — structured context block

```
ticket: <KEY|NONE>  (source: branch/pr/commit/manual)
type: <Bug|Story|Task|…>   status: <…>   re-test: <yes|no — yes if status = awaiting/returned testing>
summary: <one line>
priority: <…>   components: <…>   links: <KEY, KEY>
acceptance criteria:   (ac-source: description | ac-field | checklist-app | linked | none)
  AC1: <criterion>            [explicit|inferred] [runtime|static]
  AC2: <criterion>            [explicit|inferred] [runtime|static]
bug (if type=Bug):
  steps: 1) … 2) …            [or: missing]
  expected: <…>               actual: <…>
discussion (signal comments — newest first):
  - <author/date> QA: <findings / returned with R1…>      [or: none]
  - <author/date> dev: <fixed R1→…, pushed commit …>
  - <author/date> reviewer: <blocker/decision>
flags: <AC missing/inferred | repro missing | re-test | no ticket — as applicable>
```

**Done when:** you return this block (every AC tagged; status + re-test flag set; signal comments captured) or a clear "no ticket" note — ready for `test-iteration` to trace tests against.
