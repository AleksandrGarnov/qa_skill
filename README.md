# qa_skill

**Pre-merge QA for Claude Code that won't rubber-stamp green tests.**

You know the one: the AI writes the tests, everything's green, coverage hits the ceiling — and prod still goes down. Coverage lies, mocks test themselves, and a green CI lulls you to sleep. qa_skill doesn't let that slide. It runs a branch through a full QA cycle and **holds the gate**: a clean GO is blocked until every acceptance criterion is backed by a *raw observation* — not a code-read, not a mocked test. And it won't let the merge through while the gates are red.

![Claude Code](https://img.shields.io/badge/Claude%20Code-plugin-d97757)
![version](https://img.shields.io/badge/version-2.21.1-blue)
![license](https://img.shields.io/badge/license-MIT-green)
![tests](https://img.shields.io/badge/scripts-self--tested-success)
<!-- TODO add install-count badge once listed in a marketplace -->

<!-- Demo GIF: from the repo root run `vhs docs/demo.tape` to record docs/demo.gif (the merge-gate hook blocking a bad merge, then allowing it once the gates are green), then uncomment the line below. The .tape drives the real hook via docs/demo/merge-gate-demo.sh — nothing staged. -->
<!-- ![qa_skill demo: the merge-gate hook blocks a merge while the QA gates are red, then allows it once they're green](docs/demo.gif) -->

### Why qa_skill?

Most AI QA assistants do one thing — generate *more* tests. That's the cheap part of the job, and it's exactly what AI commoditizes. The value was never in the count of tests; it's in whether they actually catch bugs. This skill is built the other way around: not "crank out cases" but "prove the feature works" — with the discipline a naive generator skips.

### What it does

One command gives Claude Code the discipline of a senior QA: it pulls context from Jira (acceptance criteria), reviews the diff, researches the risks, builds a right-sized checklist, runs it on staging, and returns a go/no-go verdict — backed by raw observations, not "looks fine in the code". You keep writing code. The skill holds the line on quality.

```
branch → context (Jira AC) → review + research → checklist
       → staging run → evidence-gate → GO / NO-GO
                             │
                             └─ merge-gate hook: blocks the merge while gates are red
```

It runs on a **bare Claude Code install** — no plugins required. Richer tools (ruflo, Exa, Atlassian MCP) are optional upgrades, never hard dependencies.

### Install

**skills CLI** (one line, works across Claude Code, Cursor, Codex, Gemini and 50+ agents):

```
npx skills add AleksandrGarnov/qa_skill
```

**Or as a Claude Code plugin** (version-tracked, auto-updates):

```
/plugin marketplace add AleksandrGarnov/qa_skill
/plugin install qa-skill@qa-suite
```

Cross-platform (macOS/Linux/Windows). Full options (manual symlink, per-project) in [Installation](#installation).

## Skills

| Skill | What it does |
|-------|------------|
| `test-iteration` | Orchestrates a full pre-merge QA cycle for a branch: context from CLAUDE.md (incl. the test-docs path) **+ Jira acceptance criteria** + **prior-test check** (if the task was tested before, start from the old bug doc) → deterministic diff → `branch-review` + `qa-research` (in parallel) → triage anchored on the ACs (with code-derived checks + blast-radius + **domain packs** + hotspots) → right-sized checklist (with per-item test-data preconditions) + measurable exit criteria (locked mandatory core) → **independent completeness review** → approval → entry-checked staging run (every result tagged with its **evidence type**) → report with two-axis traceability (AC↔tests and changed-code↔tests), an **evidence-gate** (a runtime AC can't pass on code-read or a mocked unit test — a clean GO is blocked until every AC/critical-path pass quotes a raw observation), and a fail-closed GO / GO-with-deferrals / NO-GO verdict → re-test loop with round tracking. |
| `branch-review` | Standalone: code review + a separate security pass on a branch's diff, returning deduplicated, risk-ranked findings — each confirmed defect carrying an ISTQB severity, high-risk areas flagged as `hotspot:` for the QA cycle to up-weight. |
| `qa-research` | Standalone: researches current, sourced best practices for a branch's changes and turns them into **evidence-checkable** checks (each with an observable signal + evidence type, so it slots into the evidence-gate). |
| `jira-context` | Standalone: resolves the Jira issue key for a branch and pulls the ticket's essence — summary, acceptance criteria (each tagged `runtime`/`static` for the evidence-gate), and (for bugs) reproduction steps — as a structured context block. Degrades to manual paste when the Atlassian MCP is absent. |
| `learned-backfill` | One-shot: seeds the **learned-checks store from the project's existing reports** ("learn from old data") — mines every past `## Found bugs`, curates the recurring / GO-escaped ones into reusable checks, and (after you approve) appends them so future checklists start from accumulated experience. Run once; `test-iteration` steps 5/12 keep the loop going. |

Each skill is independently invocable; `test-iteration` composes the others.

### Tool-agnostic with fallbacks

Skills prefer richer tools but always end on something that works on a **bare Claude Code install** — no plugin silently no-ops:

- **Code / security review:** `ruflo-core:reviewer` / `ruflo-security-audit` → built-in `/code-review` / `/security-review` → a `general-purpose` subagent acting as reviewer/auditor (always available).
- **Research:** Exa MCP → `context7` → built-in `WebSearch` → only if truly nothing exists, a clear "research skipped" note.
- **Jira context:** Atlassian MCP (`getJiraIssue`) → if absent or the key can't be resolved, ask the user to paste the ticket text. The ticket is never invented; missing acceptance criteria are flagged, not guessed.

### Bundled scripts (determinism)

Deterministic, security-sensitive steps run as scripts, not as model improvisation (invoked via `${CLAUDE_PLUGIN_ROOT}/scripts/`):

- `branch-diff.sh <branch> [base]` — fetch, checkout, resolve base, print diff stat + changed files. Read-only against history (never merges/pushes/resets).
- `verify-deploy.sh <version-url> <commit>` — confirms **this branch's commit is the one deployed to staging** before testing, so a verdict can't be based on the wrong build.
- `jira-key.sh <branch> [base]` — resolves the **Jira issue key** for a branch deterministically (official format `[A-Z][A-Z]+-[0-9]+`), in priority order branch name → PR title → non-merge commits. Read-only against git/`gh`; never writes to Jira. Returns `NONE` instead of guessing when no key is found.
- `prior-tests.sh <docs-dir> <key> [extra-id]` — lists prior test reports/checklists for a task (filename or content match) so a re-test starts from existing findings instead of from scratch. Read-only. Prints `PRIOR-DOCS`, `NONE`, or `DOCS-PATH-MISSING`.
- `verify-report.sh <report.md>` — structural completeness gate for a filled report: fails closed if any item's execution record (`how run` / result / evidence / raw output) or the `Prior-test basis` line is blank or a placeholder. Run before the verdict. Checks structure, not truthfulness.
- `verify-coverage.sh <manifest> <report>` — set-diff against the approved, frozen checklist manifest: fails if any approved item is missing a result row **or marked `not executed`** (every approved item is non-skippable), or any item isn't rooted in a defined user journey (a code-built checklist).
- `verify-context.sh <manifest>` — the **system input-guidelines gate**: fails closed unless the manifest's `## Context` carries the *fetched* PR+Jira discussion (read the comments), a `prior-tests` basis (`FRESH`/`RE-TEST` — re-tests build on old runs), and Exa research. Makes the front-loaded steps non-skippable.
- `learned-checks.sh add|list|match <file> …` — the **feedback loop**: a growing, project-level store of checks distilled from real outcomes (escaped defects, recurring killer items). Step 12 appends; step 5 pulls the rows matching the changed components back into the checklist, so a check that caught a bug re-enters future runs. Plain markdown + grep — in-context learning, not model training.
- `finalize-gate.sh` — the **PreToolUse hook handler** (see below).

All scripts have self-contained tests under `scripts/tests/` (no framework needed) — run them with `bash scripts/tests/run-all.sh`.

### Merge-gate hook (hard enforcement — discloses a behavior change)

This plugin ships a **PreToolUse hook** (`hooks/hooks.json`) that fires before a branch-finalizing command (`git merge` / `git push` / `gh pr merge`) and **blocks it (exit 2)** while a QA run is active but its gates aren't green (`CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK`). This moves enforcement out of the agent's step list — a checklist item can't be skipped even if the agent skips running the gate. It is a **no-op unless `.claude/qa-run.json` exists** (written by `test-iteration` at approval), so ordinary pushes outside a QA run are never affected. If your project merges via PR/CI rather than locally, retarget the matcher in `hooks/hooks.json` (documented in `scripts/finalize-gate.sh`).

## Jira-driven QA

By default a QA cycle could only infer *what to test* from the diff and `CLAUDE.md` — which silently misses anything the change was supposed to do but didn't. `jira-context` closes that gap: tests are derived from the **acceptance criteria of the ticket behind the branch**, and the diff becomes the secondary source (what actually changed).

### How the ticket is found

`jira-key.sh` resolves the issue key deterministically — no guessing by the model:

1. **Branch name** (canonical, e.g. `feature/PROJ-123-add-login`)
2. **PR title** (via `gh`, if available)
3. **Non-merge commit messages**

The key must match the official Jira format `[A-Z][A-Z]+-[0-9]+` (two or more uppercase letters, a hyphen, digits). If a key appears in several places, the branch name wins. If none is found, the script returns `NONE` and the skill asks you for the ticket rather than inventing one.

### Where acceptance criteria come from

The ticket is fetched via the Atlassian MCP (`getJiraIssue`), pulling only the fields QA needs (summary, type, description, priority, components, links). **Acceptance criteria are read from the `description`** — parsed for `Given/When/Then` blocks, checklists, or numbered "must" statements (with a soft fallback to a dedicated AC custom field or a Checklist app if the project uses one).

- **AC present** → each becomes a discrete, id'd, checkable item (`AC1`, `AC2`, …).
- **AC missing or partial** → flagged explicitly (`AC missing/inferred`). The skill does **not** silently invent coverage — missing criteria are a signal, not a license to guess.
- **AC implicit** (buried in prose) → reconstructed as declarative `Given/When/Then` plus edge/negative cases, each marked "inferred — confirm with PO".
- **Bug tickets** → steps to reproduce, expected, and actual are extracted too (and flagged if absent).

### What it changes downstream

Inside `test-iteration` the ACs drive the rest of the cycle: triage maps every AC to at least one check, exit criteria become **measurable and binary** (`count == 0`, `coverage == 100%`, with validation commands where machine-checkable), and the report carries an **AC ↔ tests ↔ defects traceability matrix** with two-way orphan detection (ACs with no test = coverage gaps; tests with no AC = unfounded). The verdict is derived **fail-closed** against those fixed criteria.

### Standalone use

`jira-context` is independently invocable when you only want the requirement context behind a branch:

```
/qa-skill:jira-context <git-branch>
```

The Atlassian MCP is **optional** — without it (or when no key resolves) the skill asks you to paste the ticket text. It is strictly read-only: it never writes to Jira.

## Installation

### Option A — skills CLI (recommended, cross-agent)

One command installs the skills for every Claude-compatible agent at once (Claude Code, Cursor, Codex, Gemini, and 50+ others):

```
npx skills add AleksandrGarnov/qa_skill
```

Add `-g` to install globally (all projects) and `-y` to skip prompts. Requires Node.js 18+. Start a new Claude Code session and the skills are picked up automatically — invoke with `/test-iteration <git-branch>`.

### Option B — Claude Code plugin marketplace (version-tracked)

Add the marketplace and install the plugin from inside Claude Code:

```
/plugin marketplace add AleksandrGarnov/qa_skill
/plugin install qa-skill@qa-suite
```

Claude Code fetches the plugin, tracks its version, and handles updates (`/plugin update qa-skill`). This works on macOS, Linux, and Windows — plugins are copied into the plugin cache, no shell script or symlink needed.

### Option C — manual symlink, all projects (macOS/Linux fallback)

Clone and symlink the skills into `~/.claude/skills/` with a single script:

```bash
git clone https://github.com/AleksandrGarnov/qa_skill.git
cd qa_skill
./install.sh
```

A later `git pull` in this folder updates the skills automatically (symlink, not a copy). Note: bash + symlinks — not for native Windows; use Option A or B there.

### Option D — per project (share with team via git)

Copy the skills you need into the project's repository and commit them. Note `test-iteration` composes `branch-review` and `qa-research` and uses the bundled `scripts/`, so copy all of them for the full cycle:

```bash
cp -r skills/test-iteration skills/branch-review skills/qa-research /path/to/project/.claude/skills/
cp -r scripts /path/to/project/.claude/skills/test-iteration/   # keep scripts reachable
```

> **Plugin vs manual install.** `${CLAUDE_PLUGIN_ROOT}` and cross-skill invocation are only guaranteed under the **plugin install (Option B)** or the **skills CLI (Option A)**. With a manual symlink/per-project copy (Options C/D) the skills fall back to running the equivalent git commands inline — they still work, just without the script-level determinism. Option A or B is recommended.

### Requirements / dependencies

For **full** functionality, **ruflo** (richer review), **Exa MCP** (richer research), and the **Atlassian MCP** (Jira ticket context) are recommended. But nothing is hard-required: the skills always fall back to built-ins (`/code-review`, `/security-review`, `WebSearch`) and ultimately to a `general-purpose` subagent, and `jira-context` falls back to a manual ticket paste — so they run on a bare Claude Code install. The minimal baseline is Claude Code itself and access to a git branch.

## Usage

After installation, restart Claude Code and run:

```
/qa-skill:test-iteration <git-branch>
```

(With the skills CLI or a manual install — Options A/C/D — the skill is invoked as `/test-iteration <git-branch>`, without the plugin namespace.)

The skill reads the test environment from the project's `CLAUDE.md`/`README`, or asks for it.

## Security & trust

Skills are code that runs locally with your privileges — review before installing, as you would any dependency.

What this skill does, so you can audit it:

- **Runs git commands** (`git fetch`, `git checkout`, `git status`, `git log`, diffs) against your repository.
- **Invokes review tools** — `ruflo-core:reviewer` / `ruflo-security-audit` if present, otherwise the built-in `/code-review` and `/security-review`.
- **Spawns a `general-purpose` subagent** to independently review the *checklist itself* for completeness before you see it (step 6.5) — fresh context, given only the inputs, asked what's missing/unfounded.
- **Fetches third-party content from the web** via Exa MCP (`mcp__exa__web_search_exa`, `mcp__exa__web_fetch_exa`) or the `context7`/`WebSearch` fallbacks, for best-practices research.
- **Reads a Jira ticket** (read-only) via the Atlassian MCP (`getJiraIssue`) to pull acceptance criteria and repro steps, when the branch resolves to an issue key. Falls back to asking you to paste the ticket.
- **Runs the approved checklist on a staging environment** (browser automation, API/status/log checks).
- **Optionally posts a QA summary comment** back to the ticket (`addCommentToJiraIssue`) as the final step — but only after showing you the exact text and getting your explicit "yes". Skipped silently if you decline or the MCP is absent.

What it does **not** do:

- No hardcoded secrets, internal URLs, tickets, or credentials.
- Never reads `.env` or secret files — if a step needs a variable, it asks you.
- **Never tests against production.** All testing runs on staging / non-prod; the production database is off-limits — no writes, no reads, no test data. If only prod is available, it stops and tells you.
- Does not push, merge, or modify your branch — it tests and reports; you decide.
- `jira-context` reads Jira tickets **read-only** — it never comments on, transitions, or otherwise writes to an issue, and `jira-key.sh` only inspects git/`gh`. The **only** write `test-iteration` can make is the optional final summary comment above, and only with your explicit per-run confirmation — it never transitions issues, edits fields, or writes without asking.

It does not declare a broad `allowed-tools: Bash(*)` and contains no dynamic-context (`!`) shell commands in its frontmatter.

---

> **About portability.** It is important to distinguish two things here:
> - **Security (stays as is):** the skills contain **no hardcoded secrets, internal test-environment URLs, tickets, credentials, or internal service names.** The project supplies the specifics itself from its own `CLAUDE.md`.
> - **Tool dependencies:** the `test-iteration` skill is **not fully tool-agnostic** — it is optimized for ruflo, Exa MCP, and the Atlassian MCP. These dependencies are **optional** and degrade through fallbacks (`/code-review`, `/security-review`, `context7`/`WebSearch`, and a manual ticket paste for Jira); unavailable steps are marked as skipped or downgraded, and the skill does not crash.
