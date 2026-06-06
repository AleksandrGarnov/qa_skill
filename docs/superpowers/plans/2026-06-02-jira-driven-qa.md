# Jira-driven QA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `qa-skill` derive what to test from the Jira ticket behind a branch (acceptance criteria + repro), gate the verdict on measurable binary exit criteria, and prove coverage with an AC↔tests↔defects traceability matrix.

**Architecture:** One new standalone skill (`jira-context`) + one deterministic read-only script (`jira-key.sh`) plug into the existing `test-iteration` cycle exactly like `branch-review`/`qa-research` already do. The Atlassian MCP is optional and degrades to a manual-paste fallback. No Python, no writes to Jira, no `.env` reads.

**Tech Stack:** Markdown SKILL.md instructions, Bash (POSIX-ish, `set -euo pipefail`), Atlassian MCP (`getJiraIssue`), `gh` CLI (optional), `git`.

**Delivery:** This plan is **PR 1** on branch `feat/jira-driven-qa`. The full doc description is **PR 2** on a separate branch (see final section) — not part of these commits.

---

## File structure

| File | Responsibility | Action |
|------|----------------|--------|
| `scripts/jira-key.sh` | Deterministic Jira-key resolver (branch→PR→commits) | Create |
| `scripts/tests/jira-key.test.sh` | Self-contained shell tests for the resolver | Create |
| `skills/jira-context/SKILL.md` | key → fetch → extract AC/repro → structured block | Create |
| `skills/test-iteration/SKILL.md` | Wire jira-context into steps 1, 5, 6, 9 | Modify |
| `skills/test-iteration/references/test-report-template.md` | Add traceability matrix section | Modify |
| `skills/test-iteration/references/manual-checklist-template.md` | Add "AC source" line to header | Modify |
| `.claude-plugin/plugin.json` | Version bump + describe jira-context | Modify |
| `CHANGELOG.md` | 2.1.0 entry | Modify |

---

## Task 1: `jira-key.sh` resolver (TDD)

**Files:**
- Create: `scripts/jira-key.sh`
- Test: `scripts/tests/jira-key.test.sh`

- [ ] **Step 1: Write the failing test**

Create `scripts/tests/jira-key.test.sh`:

```bash
#!/usr/bin/env bash
# Self-contained tests for jira-key.sh — no external test framework.
# Builds throwaway git repos in temp dirs and asserts the resolver output.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
JIRA_KEY="$SCRIPT_DIR/jira-key.sh"
pass=0; fail=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "ok   - $desc"; pass=$((pass+1))
  else
    echo "FAIL - $desc"; echo "       expected: [$expected]"; echo "       actual:   [$actual]"; fail=$((fail+1))
  fi
}

new_repo() {
  local dir; dir="$(mktemp -d)"
  git -C "$dir" init -q
  git -C "$dir" config user.email t@t.t
  git -C "$dir" config user.name t
  git -C "$dir" commit -q --allow-empty -m "init"
  printf '%s' "$dir"
}

run_key() { ( cd "$1" && "$JIRA_KEY" "$2" "${3:-}" 2>/dev/null | sed -n 's/^key: //p' ); }
run_src() { ( cd "$1" && "$JIRA_KEY" "$2" "${3:-}" 2>/dev/null | sed -n 's/^source: //p' ); }

# Case 1: key in branch name -> source branch (canonical)
r="$(new_repo)"; git -C "$r" checkout -q -b feature/PROJ-123-add-login
assert_eq "key from branch name" "PROJ-123" "$(run_key "$r" feature/PROJ-123-add-login)"
assert_eq "source is branch"     "branch"   "$(run_src "$r" feature/PROJ-123-add-login)"

# Case 2: no key in branch, key in a non-merge commit -> source commit
r="$(new_repo)"; git -C "$r" checkout -q -b plain-branch
git -C "$r" commit -q --allow-empty -m "fix bug ABC-9 in parser"
assert_eq "key from commit msg"  "ABC-9"  "$(run_key "$r" plain-branch)"
assert_eq "source is commit"     "commit" "$(run_src "$r" plain-branch)"

# Case 3: nothing anywhere -> NONE
r="$(new_repo)"; git -C "$r" checkout -q -b nothing-here
git -C "$r" commit -q --allow-empty -m "no ticket here"
assert_eq "no key -> NONE"        "NONE" "$(run_key "$r" nothing-here)"
assert_eq "no key -> source none" "none" "$(run_src "$r" nothing-here)"

# Case 4: lowercase / single-letter prefix must NOT match (format discipline)
r="$(new_repo)"; git -C "$r" checkout -q -b proj-5-lower
assert_eq "lowercase not a key -> NONE" "NONE" "$(run_key "$r" proj-5-lower)"

echo "---"; echo "passed: $pass, failed: $fail"
[ "$fail" -eq 0 ]
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bash scripts/tests/jira-key.test.sh`
Expected: FAIL — `jira-key.sh` does not exist yet, every case prints `FAIL`, final exit non-zero.

- [ ] **Step 3: Write the resolver**

Create `scripts/jira-key.sh`:

```bash
#!/usr/bin/env bash
# Deterministic Jira issue-key resolver for the QA skills.
# Extracts a Jira key (official format: 2+ uppercase letters, '-', digits) from,
# in priority order: the branch name -> the PR title (via gh) -> non-merge commit
# messages on the branch. Read-only: never writes to git, gh, or Jira. Output is
# meant to be read by the model instead of having it guess the ticket key.
#
# Usage: jira-key.sh <branch> [base]
#   <branch>  branch to inspect (required)
#   [base]    base branch for the commit-range scan (optional)
#
# Output:
#   key: <KEY|NONE>
#   source: <branch|pr|commit|none>
# Exit codes: 0 = key found, 3 = no key (NONE), 1 = usage/not-a-git-repo.
set -euo pipefail

branch="${1:?usage: jira-key.sh <branch> [base]}"
base="${2:-}"

# Official Jira key format: project key (2+ uppercase) + '-' + number.
KEY_RE='[A-Z][A-Z]+-[0-9]+'

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
  echo "ERROR: not inside a git repository" >&2
  exit 1
}

first_key() { grep -oE "$KEY_RE" | head -n1; }

# 1. Branch name (canonical when present).
key="$(printf '%s' "$branch" | first_key || true)"
if [ -n "$key" ]; then
  echo "key: $key"; echo "source: branch"; exit 0
fi

# 2. PR title via gh, if installed and the branch has a PR.
if command -v gh >/dev/null 2>&1; then
  pr_title="$(gh pr view "$branch" --json title --jq .title 2>/dev/null || true)"
  key="$(printf '%s' "$pr_title" | first_key || true)"
  if [ -n "$key" ]; then
    echo "key: $key"; echo "source: pr"; exit 0
  fi
fi

# 3. Non-merge commit messages on the branch (scoped to base if known).
range="$branch"
if [ -n "$base" ] && git show-ref --verify --quiet "refs/remotes/origin/$base"; then
  range="origin/$base..$branch"
fi
commit_msgs="$(git log --no-merges --format='%s %b' "$range" 2>/dev/null || true)"
key="$(printf '%s' "$commit_msgs" | first_key || true)"
if [ -n "$key" ]; then
  echo "key: $key"; echo "source: commit"; exit 0
fi

echo "key: NONE"
echo "source: none"
echo "WARN: no Jira key (format ${KEY_RE}) in branch/PR/commits — ask the user or paste the ticket" >&2
exit 3
```

- [ ] **Step 4: Make it executable**

Run: `chmod +x scripts/jira-key.sh scripts/tests/jira-key.test.sh`

- [ ] **Step 5: Syntax-check then run the test to verify it passes**

Run: `bash -n scripts/jira-key.sh && bash scripts/tests/jira-key.test.sh`
Expected: PASS — every case `ok`, final line `passed: 7, failed: 0`, exit 0.

- [ ] **Step 6: Commit**

```bash
git add scripts/jira-key.sh scripts/tests/jira-key.test.sh
git commit -m "feat: add deterministic Jira issue-key resolver (branch->PR->commits)"
```

---

## Task 2: `jira-context` skill

**Files:**
- Create: `skills/jira-context/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `skills/jira-context/SKILL.md`:

```markdown
---
name: jira-context
description: Resolves the Jira issue key for a git branch and pulls the ticket's essence — summary, acceptance criteria, and (for bugs) reproduction steps — as a structured context block for QA. Works without the Atlassian MCP via a manual-paste fallback. Use when you need the requirement/AC context behind a change, standalone or as part of a QA cycle.
argument-hint: "[git-branch]"
---

# Jira Context

Turns a git branch into the **requirement context behind it**: finds the Jira key, fetches the ticket, and extracts acceptance criteria + reproduction steps as concrete, traceable inputs for QA. Standalone, and also used by `test-iteration` (step 1). Read-only — it never writes to Jira.

## 1. Resolve the ticket key (deterministic)

Run the bundled script — do not guess the key:

\`\`\`bash
"${CLAUDE_PLUGIN_ROOT}/scripts/jira-key.sh" <branch> [base]
\`\`\`

It extracts a key in the official Jira format (\`[A-Z][A-Z]+-[0-9]+\`) from, in priority order: **branch name → PR title (\`gh\`) → non-merge commit messages**, and prints \`key:\` + \`source:\`. If \`${CLAUDE_PLUGIN_ROOT}\` is unset (manual install) or the script is missing, run the equivalent inline: \`printf '%s' "<branch>" | grep -oE '[A-Z][A-Z]+-[0-9]+' | head -n1\`.
**Done when:** you have a key + its source, or \`NONE\`.

## 2. Fetch the ticket — tool-agnostic with fallback

- If a key was found **and** the Atlassian MCP is available, fetch it. The MCP tools may be deferred — first \`ToolSearch query:"select:mcp__plugin_atlassian_atlassian__getJiraIssue"\` to load the schema, then call \`getJiraIssue\` for the key. Request only the fields QA needs: \`summary, issuetype, description, priority, components, labels, status, issuelinks\`, plus whether attachments exist. Do **not** pull worklog, watchers, full comment history, sprint metadata, or estimates — that is noise for test design.
- If the key is \`NONE\` or the MCP is unavailable, **ask the user to paste the ticket text** (summary + description + any acceptance criteria). Never invent the ticket.

**Done when:** you have the ticket's summary, type, description, and metadata (or a clear "no ticket: <reason>" note).

## 3. Extract acceptance criteria + repro

Acceptance criteria in this project live **inside \`description\`** — parse it for AC blocks: \`Given/When/Then\`, checklists, or numbered "must" statements. (Soft fallback if the project changes: a dedicated AC custom field via \`getJiraIssueTypeMetaWithFields\`, then a Checklist app.)

- **AC found:** list them as discrete, checkable items, each with a short id (\`AC1\`, \`AC2\`, …).
- **AC missing or partial:** flag it explicitly — **"AC missing/inferred"** — and do not silently invent tests. Missing testable criteria is a signal, not a license to guess.
- **AC implicit (buried in prose):** reconstruct them as \`Given/When/Then\`, written **declaratively** (behaviour, not UI selectors), and add the obvious edge/negative cases. Mark each reconstructed item "inferred — confirm with PO".
- **For a bug ticket** (\`issuetype\` = Bug): also extract **Steps to Reproduce**, **Expected**, and **Actual** from the description; flag any that is missing.

## 4. Output — structured context block

\`\`\`
ticket: <KEY|NONE>  (source: branch/pr/commit/manual)
type: <Bug|Story|Task|…>
summary: <one line>
priority: <…>   components: <…>   links: <KEY, KEY>
acceptance criteria:
  AC1: <criterion>            [explicit|inferred]
  AC2: <criterion>            [explicit|inferred]
bug (if type=Bug):
  steps: 1) … 2) …            [or: missing]
  expected: <…>               actual: <…>
flags: <AC missing/inferred | repro missing | no ticket — as applicable>
\`\`\`

**Done when:** you return this block (every AC tagged explicit/inferred) or a clear "no ticket" note — ready for \`test-iteration\` to trace tests against.
```

- [ ] **Step 2: Verify structure (no secrets, required sections present)**

Run:
```bash
grep -q 'name: jira-context' skills/jira-context/SKILL.md \
  && grep -q 'jira-key.sh' skills/jira-context/SKILL.md \
  && grep -q 'getJiraIssue' skills/jira-context/SKILL.md \
  && grep -q 'ask the user to paste' skills/jira-context/SKILL.md \
  && ! grep -nE 'https?://[^ )]*atlassian\.net|[A-Z]{2,}-[0-9]+ |password|token|secret' skills/jira-context/SKILL.md \
  && echo "STRUCTURE OK"
```
Expected: prints `STRUCTURE OK` (required anchors present, no hardcoded Jira URL/secret/real ticket key).

- [ ] **Step 3: Commit**

```bash
git add skills/jira-context/SKILL.md
git commit -m "feat: add jira-context skill (key -> ticket -> AC/repro context)"
```

---

## Task 3: Wire `jira-context` into `test-iteration` (steps 1, 5, 6, 9)

**Files:**
- Modify: `skills/test-iteration/SKILL.md`

- [ ] **Step 1: Step 1 — pull requirement context**

In `skills/test-iteration/SKILL.md`, replace the body of `### 1. Project context` (the paragraph beginning "Read `CLAUDE.md`" through its `**Done when:**` line) with:

```markdown
Read `CLAUDE.md` at the project root (and nested ones). Extract: stack, conventions, the **base branch**, the **staging environment** (and a version/commit endpoint if any), and how testing is done here. If the project's testing process differs from this skill (e.g. CI-only, no staging), adapt — don't force a staging run that doesn't exist.

Then pull the **requirement context** behind the branch: invoke the **`jira-context`** skill on the branch. It returns the ticket's summary, acceptance criteria (each tagged explicit/inferred), and — for bugs — reproduction steps, or an explicit "no ticket / AC missing" flag. These acceptance criteria, not the diff, are the primary source of what to verify. If `jira-context` flags AC missing and the user can't supply them, record that in the report — do not invent coverage.
**Done when:** you know the stack, rules, base branch, staging target, testing approach, AND the ticket's acceptance criteria / repro (or an explicit note that they're unavailable).
```

- [ ] **Step 2: Step 5 — anchor triage on AC**

Replace the body of `### 5. Triage` with:

```markdown
Consolidate both streams into one list: **merge and deduplicate**, drop noise, **risk-rank** (risk = likelihood × impact, H/M/L). Every research recommendation must become a concrete *thing to verify*. **Anchor on the acceptance criteria from step 1: each AC must map to at least one thing to verify; the git diff is the secondary source (what actually changed), not the primary one.** An AC with no corresponding check is a coverage gap — surface it, don't drop it.
**Done when:** one deduplicated, risk-ranked list — with every AC mapped to ≥1 item — drives the checklist.
```

- [ ] **Step 3: Step 6 — measurable, binary exit criteria + validation commands**

Replace the body of `### 6. Manual test checklist + exit criteria` with:

```markdown
Build a concrete checklist following [references/manual-checklist-template.md](references/manual-checklist-template.md): items tied to actual changes and the ranked risks, highest-risk first, each **traced to a specific AC id** from step 1. In the same step, **write the exit criteria** — the explicit go/no-go thresholds.

Make every exit criterion **measurable and binary** (`metric >= threshold` or `count == 0`), never a vibe — e.g. `open blocker/major == 0`, `smoke suite: all pass`, `critical-path coverage == 100%`, `every AC: covered & passing`, `security risks: closed or mitigated`. Where a criterion is machine-checkable, write the **validation command** that proves it (a test command, an API/status check) — each must exit without error. Fixed here, not invented at report time.
**Done when:** you have a checklist (each item traced to an AC) AND measurable, binary exit criteria (with a validation command wherever one applies).
```

- [ ] **Step 4: Step 9 — traceability matrix + fail-closed verdict**

Replace the body of `### 9. Test report` with:

```markdown
Write the report following [references/test-report-template.md](references/test-report-template.md): per-item results, bugs with repro steps, key review/security findings, research applied. Fill the **traceability matrix** (`AC → checklist items → status → linked defects`) and run **orphan-detection both ways**: any AC with no covering test (coverage gap) and any test with no AC behind it (unfounded/guessed). Derive the verdict **fail-closed**: it is GO only if every measurable exit criterion fixed at step 6-7 is met — comparing facts against those fixed criteria, not a fresh judgement at report time. ✅ GO / ⚠️ GO with deferrals / ⛔ NO-GO ("GO with deferrals" only with a mitigation + owner + fix date per deferred item).
**Done when:** a concise report with the traceability matrix filled, orphans surfaced, and a verdict justified fail-closed against the exit criteria.
```

- [ ] **Step 5: Verify the edits landed**

Run:
```bash
grep -q "invoke the \*\*\`jira-context\`\*\* skill" skills/test-iteration/SKILL.md \
  && grep -q "Anchor on the acceptance criteria" skills/test-iteration/SKILL.md \
  && grep -q "measurable and binary" skills/test-iteration/SKILL.md \
  && grep -q "traceability matrix" skills/test-iteration/SKILL.md \
  && grep -q "fail-closed" skills/test-iteration/SKILL.md \
  && echo "WIRING OK"
```
Expected: prints `WIRING OK`.

- [ ] **Step 6: Commit**

```bash
git add skills/test-iteration/SKILL.md
git commit -m "feat: trace test-iteration to Jira AC and gate the verdict fail-closed"
```

---

## Task 4: Templates — traceability matrix + AC source

**Files:**
- Modify: `skills/test-iteration/references/test-report-template.md`
- Modify: `skills/test-iteration/references/manual-checklist-template.md`

- [ ] **Step 1: Add the traceability matrix to the report template**

In `skills/test-report-template.md`, insert this section **immediately after** the `## Checklist results` block (after its `> Pass rate without coverage...` line) and **before** `## Found bugs`:

```markdown
## Traceability matrix (AC ↔ tests ↔ defects)
> Forward (AC → tests) finds coverage gaps; backward (test → AC) finds unfounded tests. Both directions are the audit artifact for this merge.

| AC id | Acceptance criterion | Covering checklist items | Status (pass/fail/blocked) | Linked defects |
|-------|----------------------|--------------------------|----------------------------|----------------|
| AC1 | <criterion> | #1, #4 | pass | — |

**Orphan check:**
- **AC without tests (coverage gaps):** <AC ids, or "none">
- **Tests without an AC (unfounded/guessed):** <item #s, or "none">
- **AC source:** <jira-context: KEY | manual paste | AC missing — see flags>
```

- [ ] **Step 2: Add the AC-source line to the checklist template header**

In `skills/manual-checklist-template.md`, insert this line **immediately after** the `**What changed (1-2 lines):** <summary of changes>` line:

```markdown
**Acceptance criteria (from jira-context):** <AC1, AC2, … one line each — or "AC missing/inferred — flagged">
```

- [ ] **Step 3: Verify both edits**

Run:
```bash
grep -q "Traceability matrix (AC" skills/test-iteration/references/test-report-template.md \
  && grep -q "Orphan check" skills/test-iteration/references/test-report-template.md \
  && grep -q "Acceptance criteria (from jira-context)" skills/test-iteration/references/manual-checklist-template.md \
  && echo "TEMPLATES OK"
```
Expected: prints `TEMPLATES OK`.

- [ ] **Step 4: Commit**

```bash
git add skills/test-iteration/references/test-report-template.md skills/test-iteration/references/manual-checklist-template.md
git commit -m "feat: add AC traceability matrix to report + AC source to checklist"
```

---

## Task 5: Manifest + changelog

**Files:**
- Modify: `.claude-plugin/plugin.json`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump version and describe jira-context**

In `.claude-plugin/plugin.json`:
- change `"version": "2.0.0"` → `"version": "2.1.0"`
- replace the `"description"` value with:
  `"QA skills for Claude Code: test-iteration (orchestrates a full pre-merge QA cycle), branch-review (code + security review of a branch), qa-research (sourced best-practices for a change), and jira-context (pulls a ticket's acceptance criteria & repro for QA). Tool-agnostic with fallbacks; ships deterministic git/deploy/jira scripts."`
- in `"keywords"`, add `"jira"` after `"testing"`.

- [ ] **Step 2: Validate JSON**

Run: `python3 -m json.tool .claude-plugin/plugin.json >/dev/null && echo "JSON OK"`
Expected: prints `JSON OK`.

- [ ] **Step 3: Add a changelog entry**

Open `CHANGELOG.md`, read its existing format, and insert a new entry at the top (below the title, above the most recent version) following that format. Content:

```markdown
## 2.1.0

### Added
- `jira-context` skill: resolves the Jira key for a branch (deterministic `jira-key.sh`: branch → PR → commits) and pulls the ticket's summary, acceptance criteria, and bug repro into a structured context block. Atlassian MCP optional; degrades to manual paste.
- Traceability matrix (AC ↔ tests ↔ defects) with two-way orphan detection in the test report.

### Changed
- `test-iteration` now derives what to test from Jira acceptance criteria (diff is secondary), requires measurable/binary exit criteria with validation commands, and derives the verdict fail-closed against them.
```

- [ ] **Step 4: Commit**

```bash
git add .claude-plugin/plugin.json CHANGELOG.md
git commit -m "chore: bump to 2.1.0, document jira-context"
```

---

## Task 6: Full-cycle verification + push PR 1

- [ ] **Step 1: Re-run the resolver tests and JSON check together**

Run:
```bash
bash scripts/tests/jira-key.test.sh \
  && python3 -m json.tool .claude-plugin/plugin.json >/dev/null \
  && echo "ALL GREEN"
```
Expected: `passed: 7, failed: 0` then `ALL GREEN`.

- [ ] **Step 2: Secret/URL sweep across the new + changed files**

Run:
```bash
! grep -rnE 'https?://[^ )]*atlassian\.net|password|secret|ghp_|sk-ant' \
  skills/jira-context scripts/jira-key.sh \
  && echo "NO SECRETS"
```
Expected: prints `NO SECRETS`.

- [ ] **Step 3: Push and open PR 1**

```bash
git push -u origin feat/jira-driven-qa
gh pr create --base main --title "feat: Jira-driven QA — ticket AC as the source of tests + fail-closed gate" \
  --body "Adds jira-context skill + jira-key.sh, wires Jira acceptance criteria into test-iteration as the primary source of what to test, makes exit criteria measurable/binary, and adds an AC↔tests↔defects traceability matrix. Atlassian MCP optional (manual-paste fallback). Read-only on Jira; no secrets. Docs description ships separately in PR 2."
```

---

## Follow-up: PR 2 — documentation (separate branch)

Not part of `feat/jira-driven-qa`. After PR 1 is opened/merged, branch `docs/jira-driven-qa-description` from the base and write the full description: a "Jira-driven QA" section in `README.md` (what it does, the `jira-key.sh` source priority, the AC-missing behaviour, the MCP-optional/manual-paste fallback, the traceability matrix) and add `jira-context` to the Skills table. Keep it its own PR so the feature and the docs can be reviewed/accepted independently. A dedicated plan for PR 2 can be written when we get there; it is documentation-only (no code), so it may not need the full TDD plan treatment.
```
