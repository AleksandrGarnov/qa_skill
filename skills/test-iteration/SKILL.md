---
name: test-iteration
description: Runs a git branch through a full pre-merge QA cycle for Claude Code — project + Jira acceptance-criteria context, branch review, best-practices research, a right-sized test checklist, execution on the staging environment, and an evidence-gated go/no-go verdict (a clean GO is blocked until every acceptance criterion is backed by a raw observation, not a code-read or a mocked test). Use when a feature or branch needs real QA before merging.
argument-hint: "[git-branch]"
---

# Feature Test Iteration

**Branch:** `$ARGUMENTS` (if not provided, stop and ask for the branch).

Runs a git branch through a full pre-merge QA cycle and produces a fail-closed verdict (✅ GO / ⚠️ GO with deferrals / ⛔ NO-GO). Delegates review to `branch-review` and research to `qa-research`; uses bundled scripts for the deterministic git/deploy/report steps.

## Principles

- **Do everything yourself — as a manual tester, through the product's real interfaces.** git, review, research, then **trigger the user's action through the real entry point** (drive the UI by hand, or call the API as a client) and read logs/status to observe. `repl`/`cli`/DB queries on **non-prod** are **supporting** — set up preconditions, read resulting state, isolated assists — **not** the flow-driver: never reconstruct the *whole flow* in `repl` (calling internal services is a proxy for the user, not the user journey, and can't close a user-facing AC). The **one hard boundary: never put a *file* on the server** — no `scp`/`docker cp`/deployed script/harness/probe, not even read-only; run the logic as a direct command instead. Turn to the user only at step 7, for a visual check, or for access you lack.
- **Never test against production.** All testing runs on staging/non-prod; the production DB is off-limits — no writes, no reads, no test data, ever. Treat every access/credential/URL you're handed as non-prod; a request that seems to require editing prod is a misread — stop and confirm. A behaviour only visible in prod is a `blocked` gap, not a reason to touch prod.
- **Test to FALSIFY, not confirm — dangerous conditions and user journeys first.** Find how the change *loses/corrupts* data; don't re-confirm the dev's happy path (their green unit tests already do, on clean data). Lead with "how does this lose/corrupt the user's data?" and the dangerous conditions (stale cache, a concurrent action *in the window* between two steps, negative/boundary, compensation/retry mid-run, out-of-order/duplicate/partial-failure) **before** clean inputs. Organize checks by **user journey**, not by code concern — a checklist of "filters / type-mapping / clauses" tested the code, not the feature.
- **Coverage is what you executed and observed — nothing else counts.** A pass needs a **quoted raw observation of that item's own claim** (`observed-data`/`api`/`log`). *Not* a pass: reasoning ("surely it self-heals", "B is just A"); a **proxy** (a mechanism observation under a scenario item); a green **mock** (`unit:mocked` proves the code agrees with itself, not that it works on real data); or validating only against **existing/historical** data — that tests the *consuming* half, not whether the user's action *produces* the right state across every store (the producing leg is `blocked` until run live). No assumed equivalence between flows; the sweep is "done" only when every enumerated flow is exhausted by execution. Unrun work is `blocked`/`not executed` and **surfaced** — never hidden, substituted, or self-downgraded. **Surfacing is not a resolution:** an approved check is *executed*, or it's `blocked` only after a documented real attempt — you never offer the user a "leave it uncovered, you decide" choice; if you lack access, ask for it to *finish* the check, not for permission to ship the gap. A `blocked`/unrun **critical-path or AC** item is a ⛔ NO-GO — never downgraded to a deferral (deferral is for a *defect* with mitigation + owner + fix-date, never a way to skip a check).
- **Gates over judgment.** The checklist is independently reviewed before anyone trusts it (6.5); exit criteria — including a non-overridable mandatory core — are locked before testing (6–7); the verdict is fail-closed and a **script** (`verify-report.sh`) blocks it if the report is incomplete. A discipline you can't pass without proof survives "the report looks done" pressure; a paragraph you're merely asked to honor does not.
- **Read the task's discussion before analysing it.** Before forming bug theories or designing checks, read the **Jira comments + PR review comments** — the dev's rationale and reviewers' findings often confirm/refute a theory before a run is spent. Applies to ad-hoc work too, not only step 1.
- **Don't read secrets.** Never read `.env`/secret files; if a step needs a variable, ask the user.

## Steps

### 1. Context + prior-test history
Read `CLAUDE.md`: stack, **base branch**, **staging target** (+ any version/commit endpoint), the **test-docs path**, and how testing is done here (adapt if it differs — e.g. CI-only). Invoke **`jira-context`** for the ticket's summary, AC (tagged explicit/inferred and runtime/static), repro, status, and **discussion** comments. The AC — not the diff — are the primary source of what to verify.

**AC-missing gate:** if AC are missing and the user can't supply them, flag the run `exploratory — requirements unverified`, cap the verdict at `⚠️ GO (exploratory)` (never a clean GO), and run a structured exploratory pass ([exploratory-charter.md](references/exploratory-charter.md)).

**Prior-test gate — run it, don't recall it.** Gather the task's history from three sources:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/prior-tests.sh" <test-docs-path> <KEY> [branch]   # PRIOR-DOCS / NONE / DOCS-PATH-MISSING
```
plus the **Jira discussion** and **PR comments** (`gh pr view <PR> --comments`, skim bots). A status like *Awaiting / Returned testing* = a re-test: prior findings become **priority re-checks** (re-verified **live** on the current build; "fixed but not re-verified" = open), their components become hotspots, and you diff tested-commit↔HEAD. Continue that history (step 10), don't restart.
**Done when:** you know stack/base/staging, the AC/repro (or that they're missing), and whether this is fresh or a re-test — `prior-tests.sh` run, discussion + PR comments read.

### 2. Branch + diff (deterministic)
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/branch-diff.sh" "$ARGUMENTS" [base]
```
Fallback to inline git if no plugin root. Use the base from `CLAUDE.md`; if `base: UNKNOWN` and CLAUDE.md is silent, **ask — don't guess**. Note the **head commit** (needed at step 8).
**Done when:** head commit, confirmed base, changed-files list.

### 3-4. Review + research (in parallel)
Invoke **`branch-review`** (deduplicated, risk-ranked code + security findings, each defect with an ISTQB severity and high-risk areas tagged `hotspot:`) and **`qa-research`** (sourced, **evidence-checkable** best-practice checks). Both degrade gracefully on a bare install.

### 5. Triage → drive the checklist
Build the candidate checks in this order, then consolidate:
1. **Failure modes first (adversarial).** "How does this lose/corrupt data?" → stale snapshot used as truth, concurrent-action-in-the-window, negative/boundary/zero, compensation/retry mid-run, out-of-order/duplicate/partial-failure, the "optimization that swapped truth for a stale value" trap. Each → a high-priority check, **before** happy-path items. For a money/state change this list is **mandatory** (none = coverage gap = NO-GO). Source it from the **discussion**, **Exa** (`qa-research`), and the code — not memory.
2. **Every flow / entry point.** Read the codebase for *all* operations that reach the changed code (don't assume a fixed set). Each is covered by **running it live**, or proven to share the exact code path of one already run (with evidence) — never assumed. Carry the flow list into the report.
3. **User journeys (the spine).** Name the user(s) — often layered (the actor who creates the data **and** the downstream consumer of the output). Each journey end-to-end: *actor → action → what it produces across every store → run the feature → observable outcome*. Technical/code-branch checks fold in **under** the journey they validate. A **live** journey (you perform the action) ≠ validating against existing data (covers only the consuming half). Perform it on a **freshly-created subject** (register a new user / create new data per scenario), **not a reused fixture** — an old test account carries accumulated state and hidden coupling, and skips the real creation path; a fresh one isolates the action's effect and exercises produce-then-consume cleanly.
4. **Code-derived checks.** One per changed branch (`if/else`/switch incl. default), flag/state, code-visible edge case (falsy, race, async ordering), and persistence path (save/restore/clear); shared-component call-sites.
5. **Domain packs + hotspots + blast radius + learned checks.** Pull the matching [domain pack](references/domain-packs/); up-weight hotspots (escaped-defects log / memory / `branch-review` `hotspot:` tags); for each changed export, `git grep` its callers → regression checks. **Pull the project's learned checks** — distilled from past real outcomes — for the changed components, and fold every matching one in (this is how the system gets smarter run-over-run, not a blank slate each time):
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" match <test-docs-path>/learned-checks.md <changed-component-keywords…>
```
A matching learned check that you *don't* fold in is a coverage gap the step-6.5 review flags.
6. **Reconcile + map.** Anchor each AC to ≥1 check (an AC with none is a gap); log Jira↔code discrepancies as PO questions; keep a `changed-code → item` map for step 9's code-orphan check.
**Done when:** one risk-ranked list — AC-anchored, journey-organized, with failure-modes/flows/code/packs folded in, blast-radius callers as regression items, and the `changed-code → item` map built.

### 6. Checklist + exit criteria
Build it as **tables** ([manual-checklist-template.md](references/manual-checklist-template.md)) — one row per check, columns **# · what to check · how to run (exact command/UI steps/API call) · expected · risk · trace (AC)**. A vague item ("check it reconciles") is skippable/proxyable; a prescribed one ("run `<cmd>`, expect `<X>`, read `<field>` == `<Y>`") can only be done or `blocked`. **Right-size** (template's Scope & tailoring): skip a section only as a recorded `N/A — <reason>`; Smoke + Regression are never skipped. Derive **per-item test-data preconditions** up front (most `blocked` results are unready data).

Write **exit criteria** — measurable/binary, with a validation command where machine-checkable. **Mandatory core (non-overridable — neither you nor the user weakens it):** `0 open blocker/major` · `smoke all pass` · `critical-path coverage 100%` · `every explicit AC covered & passing — a runtime/user-facing AC closed on a live observation (observed-data/api/log), never on code-read/unit:mocked or repl alone` · `security findings closed/mitigated`. Add stricter project lines on top. Green unit/repl/code checks are *supporting* — they never by themselves grant GO for a user-facing change.
Also emit the checklist as a **frozen manifest** ([checklist-manifest-template.md](references/checklist-manifest-template.md)). It opens with a **`## Context` block you fill by running the tools** (the system's non-skippable input guidelines), then **journeys first** (named actor → action → observable outcome), then **items each carrying a stable ID and a journey ref**:
- **`### Discussion`** — paste the *fetched* `gh pr view <PR> --comments` + the Jira ticket discussion (guideline 1: read the comments — real content, not "I read them").
- **`### Prior tests`** — the `prior-tests.sh` result, `FRESH` or `RE-TEST of <doc>@<commit>`; on RE-TEST the items are built on the old runs (guideline 4).
- **`### Research (Exa)`** — the Exa findings turned into checks (guideline 2: always research; the journey-rooting enforces "user-flow first, code-branches under it").

Then gate the manifest **before showing it for approval**:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-context.sh"  <manifest.md>                # must print CONTEXT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-coverage.sh" <manifest.md> <report.md>    # journey-rooting (report may be a stub here)
```
`verify-context.sh` fails closed if the Discussion / Prior-tests / Research blocks are empty — so the front-loaded steps (read comments, prior runs, Exa) **cannot be skipped**; the merge-gate hook re-checks it at merge.
**Done when:** a journey-rooted manifest with a filled `## Context` (CONTEXT-OK) + items (ID + journey ref) + exit criteria including the mandatory core.

### 6.5. Independent completeness review
Have a **fresh `general-purpose` subagent** — given only the inputs (diff, AC, the `changed-code → item` map, the matching **learned checks** (step 5), the checklist, the exit criteria), **not** your reasoning — report **what's missing or unfounded**: an uncovered AC, an uncovered changed symbol, an item with no AC/code basis, **a `qa-research` finding that became neither a checklist item nor a recorded reject**, **a matching learned check that wasn't folded into the checklist**, an `N/A` whose reason doesn't hold, an exit criterion weaker than the core. Fold the real findings back; re-run once if material; cap at 2 rounds. No subagent → do a cold self-review in a separate, explicit pass and say so.
**Done when:** the checklist passed an independent (or explicit self-) completeness review; gaps closed or recorded.

### 7. Approval — PAUSE (user required)
Show the user the **manifest** (journeys + items) + exit criteria (post-6.5) and **wait for "ok" or edits before testing**. They approve scope and thresholds but **cannot weaken the mandatory core**. Don't proceed without explicit confirmation. On "ok" the manifest is **frozen** — it's the contract; the step-9 report must account for every item ID in it.

On freeze, **record the run-state** so the merge-gate hook can enforce the gates without depending on you remembering to run them:
```bash
mkdir -p "${CLAUDE_PROJECT_DIR:-.}/.claude"
printf '{"manifest":"%s","report":"%s","branch":"%s"}\n' "<abs manifest path>" "<abs report path (step 9)>" "$ARGUMENTS" \
  > "${CLAUDE_PROJECT_DIR:-.}/.claude/qa-run.json"
```
The bundled **PreToolUse hook** (`hooks/hooks.json` → `finalize-gate.sh`) reads this file and **blocks a `git merge`/`git push`/`gh pr merge` with exit 2** unless `CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK` all pass — so a skipped checklist item or ungathered context physically cannot reach a merge, regardless of what the agent does. (If this project merges via PR/CI rather than locally, point the hook's matcher at that action instead — see the hook comment.)

### 8. Run on staging — a full execution record per item
**Entry criteria (don't start until they hold):** the target is non-prod; staging is reachable; **THIS branch's commit is deployed** —
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-deploy.sh" <version-url> <head-commit-from-step-2>
```
(or confirm the build another way — a wrong build invalidates the verdict); test data/accounts/flags ready.

Run each item by hand — **trigger via the real entry point** (UI / API as a client); `repl`/`cli`/DB queries are for **setup and reading state**, not for driving the flow. **Never upload a file to the server.** For **every item** record a 4-part **execution record**:
- **how run** — the *verbatim* command/steps actually used (not "checked the balance");
- **raw output** — the actual response/log/value, quoted;
- **evidence type** — `observed-data`/`api-response`/`log`/`code-read`/`unit:mocked`/`unit:integration`;
- **bucket** — pass / fail / blocked / flaky / N/A (reason) / not executed.

Rules:
- Empty "how run" = `blocked`/`not executed`, never pass. A "how run" that doesn't match the prescribed action is a **proxy** — the item is not covered.
- **No silent skips or self-scope-cuts.** Every approved item is the contract — run it, or mark `blocked` (with reason) and surface it; you don't get to decide an item is "unnecessary". A `pass` needs evidence for *that item's own claim* (a mechanism observation ≠ a scenario pass).
- **Hard-to-reproduce / env-limited ≠ skip.** First try to make it runnable — a safe setup (`Queue::fake()`/`Event::fake()`, deterministic state injection, two processes / two real users), a historical period that has the data, a different account/read-replica. If the obvious entry point is missing (e.g. no debug endpoint), try the **other real channels** (admin UI, API as a client, a second account) and, if still stuck, **ask the user for the access to finish it** — `blocked` is the last resort, only after a documented attempt, and "couldn't reproduce the real flow" never becomes a `pass` via `repl` (it stays `blocked`). ("Can't write" ≠ "can't read": attempt the read-only observation first — on non-prod only.)
- **`flaky`** (flips on the same build) is a gap, not pass/fail — re-observe 1–2×; a retried pass is telemetry, not health. Flaky on the critical path blocks a clean GO.
**Done when:** every item has a full execution record; nothing was silently dropped, proxied, or self-downgraded; and no cited constraint went without a real attempt first.

### 8.5. Independent re-execution of the critical path (unbiased corroboration)
For **critical-path / money-state items only**, spawn a **fresh `general-purpose` subagent** — given only the frozen manifest's commands for those items + the staging target, **not** your run's results, evidence, or reasoning — and have it **re-execute** them and return the **raw outputs**. Then cross-check: each critical `pass` must be **corroborated by the independent run's raw output** (the two observations agree). A mismatch, or any critical `pass` the independent run **can't reproduce**, is a **GAP** that blocks a clean GO — investigate the discrepancy first (the gap between "verification says PASS" and "re-run says otherwise" is the most valuable signal, never ignore it). Record it in the report's *Independent re-execution* table. Scope to the critical path so it stays practical.
> This is **unbiased verification applied to execution, not review** (the executor doesn't self-certify; a blind second context does). It is **strong corroboration, not a hard guarantee** — both are LLMs and can share a blind spot. The only hard guarantee is a **runnable black-box acceptance test** for the flow (executes against staging, green/red by code, not judgement); where such a test exists, it supersedes this step for that flow.
**Done when:** every critical-path `pass` is corroborated by an independent blind re-run (outputs agree), or the discrepancy is surfaced as a GAP.

### 9. Report + fail-closed verdict
Write the report ([test-report-template.md](references/test-report-template.md)). It **leads with a coverage ledger** (`approved N · executed X · blocked Y · not-run Z`) — never a "clean/objective" narrative over an incomplete run. Every bug carries **exact, copy-pasteable repro steps from a clean start** (literal commands, not a mechanism summary).

Run **two-axis orphan detection**: **AC ↔ tests** and **changed-code ↔ tests** (from the step-5 map) — surface any uncovered AC, uncovered changed symbol, or unfounded/drift item. **Evidence-gate the AC matrix:** a runtime-behaviour AC on `code-read`/`unit:mocked` evidence alone is a **GAP** (needs ≥1 `observed-data`/`api`/`log`); an AC covered only by mocked tests needs ≥1 real-data corroboration of the same behaviour (the mock↔reality match — a contract test). Fill the **Open questions for PO** block from step-5 Jira↔code discrepancies.

**Pre-verdict self-audit:** for every AC-pass and critical-path item, quote the raw output that proves **its own claim** — nothing to quote ⇒ GAP. Then run the **mechanical gates**:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-context.sh"  <manifest.md>               # must print CONTEXT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-report.sh"   <report.md>                 # must print REPORT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-coverage.sh" <manifest.md> <report.md>   # must print COVERAGE-OK
```
`verify-report.sh` fails on: an incomplete execution record, an unfilled `Prior-test basis` line, a bug with no exact repro, or a **clean ✅ GO that still has a `not executed` row**. `verify-coverage.sh` fails (set-diff against the frozen manifest) on: **any approved item with no result row OR marked `not executed`** (a skip — every approved item is non-skippable, guideline 3) or **any item not rooted in a defined journey** (guideline 2) — making "the report quietly dropped/skipped checks" and "the checklist was built from code, not journeys" mechanically impossible.

Write the report path into the run-state (`.claude/qa-run.json`, step 7) so the **merge-gate hook** enforces these three gates at the irreversible action. You run them here for early feedback, **but the binding enforcement is the hook, not this step** — even if this step were skipped, the hook blocks the merge until all three are green.

**Verdict — fail-closed:** GO only if `CONTEXT-OK` **and** `REPORT-OK` **and** `COVERAGE-OK` **and** every critical-path `pass` is corroborated by the step-8.5 independent re-run (or guaranteed by a green acceptance test) **and** every exit criterion (core + project) is met against the fixed thresholds, not a fresh judgement at report time. Any open blocker/major, critical-path coverage <100%, a blocked/unrun critical item, an AC passing on sub-gate evidence, or a red regression → not a clean GO. `exploratory` caps at ⚠️ GO (exploratory); "GO with deferrals" only with mitigation + owner + fix-date per deferred item.
**Done when:** ledger + both orphan axes + Evidence column + self-audit + `CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK`; verdict justified against the fixed criteria.

### 10. Re-test loop (if not GO)
On new fixes, don't restart — re-run only the failed/blocked items + a regression pass on what they could touch, against the **bumped build** (re-testing the failed build proves nothing). Record each defect's `found in round` / `fix verified in round`; the AC matrix is the source of truth across rounds. Repeat until GO (or the user calls it).

### 11. Close the loop to Jira (optional — explicit confirmation)
Offer to post a concise QA summary as a ticket comment (verdict, executed/pass/fail counts, open blockers, report link). It's an **outward-facing write**: show the exact text, post only on explicit "yes", via the Atlassian MCP to the `jira-context` key. Skip silently if declined or the MCP is unavailable.

### 12. Learn from escapes (lite — only if a defect later escapes a GO build)
If a defect surfaces after GO, capture it ([escaped-defects.md](references/escaped-defects.md)) with its **"why not caught"** category (missing edge case / no real-data observation / thin regression / mocked-only / no AC), add a regression check, flag the component as a future hotspot, and if a category repeats, fix that step of the process — not just the bug. Then **distil it into a learned check** so it re-enters every future checklist for that component (the feedback loop, not just a one-off log):
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" add <test-docs-path>/learned-checks.md "<component>" "<the check that would have caught it>" "<the escape that taught it>"
```
A recurring killer item that proved its worth (caught bugs across runs) is also worth adding, not only post-GO escapes. Step 5 pulls these back in automatically. Lightweight: a log line + the learned-check row + a memory note.
