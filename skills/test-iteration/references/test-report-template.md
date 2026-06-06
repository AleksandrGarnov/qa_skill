# Test Report — <feature / branch>

**Branch:** <branch>
**Date:** <date>
**Environment:** <stage-url>
**Base branch:** <main/develop>
**Build / commit:** <build / commit-hash>

**Prior-test basis (REQUIRED — fill before any verdict):** <one of:>
- `FRESH` — first test of this task (`prior-tests.sh` = NONE, no prior findings in the Jira discussion / PR comments), **or**
- `RE-TEST` of <prior doc path / Jira QA comment> on commit <prior-commit> → delta `<prior-commit>..<HEAD>` re-verified; carried-over findings: <R1…> with current status.

> This line is a **gate**: a clean ✅ GO is **forbidden while it is empty**. You cannot fill it honestly without having run the step-1 prior-test gate (`prior-tests.sh` + Jira discussion + PR comments) — so it fails closed even if step 1 was rushed. "Didn't check" is not a valid value.

## Verdict
> Answer first (Minto: conclusion on top, justification below).

**Verdict:** ✅ GO / ⚠️ GO WITH DEFERRALS / ⛔ NO-GO
**Coverage ledger (lead with this — honesty before conclusion):** approved <N> · executed <X> · blocked <Y> · not-run <Z> · N/A <W>  → executed coverage <X/N>
**Summary:** <1-2 lines: which exit criterion decided the outcome>

> **Don't present a "clean / objectively confirmed" report while approved checks are unrun.** The coverage ledger leads the verdict; unrun work is not a footnote. A clean **✅ GO is forbidden while `not-run > 0`** or any critical item is `blocked`. An unrun **check** is not deferrable: you **execute it**, or it's `blocked` only after a documented real attempt — and a `blocked`/unrun **critical-path or AC** item is a ⛔ NO-GO, never downgraded to ⚠️ GO by writing a reason. Deferral (⚠️ GO WITH DEFERRALS) is for a **defect** with mitigation + owner + fix-date, never a way to skip running a check. `verify-report.sh` fails a clean ✅ GO that still has `not executed` rows.

Verdict selection rules:
- **✅ GO** — all exit criteria met (mandatory core + project additions), no open blocker/major defects, **the Prior-test basis line above is filled** (FRESH or RE-TEST — never blank/"didn't check"), **and the pre-verdict evidence self-audit is clear** (every AC/critical-path pass backed by a quoted raw observation). Not attainable if the run is `exploratory — requirements unverified`.
- **⚠️ GO WITH DEFERRALS** — allowed ONLY when every deferred defect has a named **mitigation + owner + fix date**. Missing any one of the three → it's a NO-GO, not a "GO with deferrals".
- **⚠️ GO (exploratory)** — the cap when AC were missing and couldn't be supplied (step-1 gate): the change behaved acceptably against code/risk-derived checks, but with **no verified requirement basis**. Never report a clean ✅ GO in this case.
- **⛔ NO-GO** — any open blocker, any unmitigated major, critical-path coverage <100%, an open AC/code coverage gap on the critical path, a `blocked` critical-path check, a red regression, or an unresolved security risk.

## Exit criteria (fixed at approval, BEFORE the run)
> "A verdict is not a vibe": criteria are the ones approved together with the checklist (step 7-8), not invented here; the verdict is a fact measured against them.

> **Type:** `core` = mandatory, locked (cannot be weakened/removed by QA or user); `proj` = project-specific addition on top.

| # | Exit criterion | Threshold | Type | Status |
|---|----------------|-----------|------|--------|
| 1 | Open blocker / major | 0 | core | ☐ |
| 2 | Smoke suite | all pass | core | ☐ |
| 3 | Critical-path coverage | 100% | core | ☐ |
| 4 | Every explicit AC covered & passing | yes (N/A if exploratory) | core | ☐ |
| 5 | Security findings closed or mitigated | yes | core | ☐ |
| 6 | Regression | green | proj | ☐ |
| 7 | <additional project criterion> | <threshold> | proj | ☐ |

**NO-GO triggers (any single one is enough):** **Prior-test basis line empty / "didn't check"** • **money/state change with no adversarial failure-mode items (only confirmed the happy path)** • **an enumerated flow covered only by assumption/reasoning (not executed, not proven to share the same code path)** • open blocker • unmitigated major • critical-path coverage <100% • uncovered explicit AC • open AC/code coverage gap on the critical path • `blocked` critical-path check • **any AC/critical-path pass without a quoted raw observation (evidence self-audit not clear)** • red regression • unresolved security risk.

## Checklist results
> `Round` = which re-test round this result is from (R1 = first pass). On a re-test, only failed/blocked items + regression are re-run; carry forward the rest with their round.

> Every row needs a full **execution record**: `How run` (verbatim command/steps), `Result`, `Evidence`, `Actual` (raw output). No cell left blank or as a `<placeholder>` — `scripts/verify-report.sh` fails the report otherwise.
> The `#` column **reuses the item ID from the approved manifest** verbatim. `scripts/verify-coverage.sh <manifest> <this report>` set-diffs the two: a manifest item ID with no row here is a **skipped item** and fails the verdict. Every approved item must appear — run it, or record it `blocked` (never silently absent).

| # | Item | How run (verbatim command / UI steps / API call) | Result | Evidence | Round | Actual (raw output observed — quote, don't paraphrase) |
|---|------|---------------------------------------------------|--------|----------|-------|-------------------------------------------------------|
| 1 | <item> | <the exact command / UI steps / API call you ran, verbatim> | pass / fail / blocked / flaky / N/A (reason) / not executed | observed-data / api-response / log / code-read / unit:mocked / unit:integration | R1 | <actual request/response/log/observed value> |

> `N/A` = genuinely doesn't apply (reason recorded at checklist time). An applicable check you couldn't run is **`blocked`** (a coverage gap), never `not executed`. `How run` must be the *actual* method you used — empty = the item wasn't done; a method that doesn't match the item = a proxy (not covered).
> **Evidence** = how you know. A `pass` on `code-read` or `unit:mocked` alone, for a runtime-behaviour item, is not a pass — it's a gap. "Can't write" ≠ "can't read": cite a constraint only after a read-only attempt.

**Summary:** executed <N>/<N> | pass <X> | fail <Y> | blocked <Z> | flaky <F> | not executed <W>
**Pass rate:** <X/executed = %>  •  **Coverage:** <requirement/AC items checked = %>
> Pass rate without coverage is a vanity metric. Always report both side by side.
> **A green checklist must mean GO.** If a blocker exists, the checklist is **not** green — record that blocker as a **checklist item with `fail`** (so the table itself is red), never as a footnote under a high pass-rate. "19/19 pass + a note about the money-loss blocker" is a checklist that lies: a single `fail`/blocker on the critical path makes the whole result a NO-GO, and the headline is the **verdict**, not the pass count. A scenario that only fails under concurrency/timing is a first-class `fail` item, not a "branch-green with a caveat".

## Traceability matrix (AC ↔ tests ↔ defects)
> Forward (AC → tests) finds coverage gaps; backward (test → AC) finds unfounded tests. Both directions are the audit artifact for this merge.

| AC id | Acceptance criterion | Covering checklist items | Evidence | Status (pass/fail/blocked/GAP) | Linked defects |
|-------|----------------------|--------------------------|----------|--------------------------------|----------------|
| AC1 | <criterion> | #1, #4 | observed-data | pass | — |

> **Evidence-gate:** a runtime-behaviour AC needs ≥1 `observed-data`/`api-response`/`log`. On `code-read` or `unit:mocked` alone → status **GAP**, not pass. An AC covered only by mocked tests needs ≥1 real-data observation of the *same* behaviour (mock↔reality verified at least once).

## Code coverage matrix (changed code ↔ tests)
> The mirror of the AC matrix, from the step-5 `changed-code → item` map. Keeps "derive checks from the code" honest: a changed symbol/branch with no covering item is a real gap, not an oversight.

| Changed symbol / branch | File | Covering checklist items | Status |
|-------------------------|------|--------------------------|--------|
| <fn / branch / flag> | <path> | #2 | pass |

## Flows / entry points (every operation that exercises the change)
> From the step-5 enumeration. Each flow is `executed` (you ran it) or `equivalent` (proven to share the *exact* code path of an executed one, with evidence) — never `assumed`. An `assumed`/unswept flow is a coverage gap (NO-GO). "Done" = no flow left unswept.

| Flow / operation | Covered by | Status |
|------------------|-----------|--------|
| <operation A — e.g. a credit> | item #3 (ran) | executed |
| <operation B — e.g. a debit> | item #4 (ran) | executed |
| <operation C> | <item # / "same code path as B — proof: …"> | executed / equivalent / **assumed (GAP)** |
| <list every operation in THIS project that reaches the changed code> | <…> | <…> |

**Orphan check (both axes, both directions):**
- **AC without tests (coverage gaps):** <AC ids, or "none">
- **Tests without an AC (unfounded/guessed):** <item #s, or "none">
- **Changed code without a covering test (code coverage gaps):** <symbols, or "none">
- **Tests referencing unchanged code (drift):** <item #s, or "none">
- **AC source:** <jira-context: KEY | manual paste | AC missing → run flagged `exploratory` — see verdict cap>

## Pre-verdict evidence self-audit (gate — fill BEFORE the verdict)
> For every AC marked pass and every critical-path item, quote the raw output that proves it. Nothing to quote → it's not a pass, downgrade to GAP. **A clean ✅ GO is forbidden while any row below is empty.** (Scope: AC + critical-path only, so it stays practical.)

| AC / critical item | Status | Evidence type | Raw output quoted (paste the actual line) |
|--------------------|--------|---------------|-------------------------------------------|
| AC1 | pass | observed-data | `<paste request/response/log/observed value>` |
| AC2 | GAP | unit:mocked | — *(no real-data observation → not a pass)* |

**Audit result:** <all AC/critical-path passes have a raw quote → gate clear | N rows empty → those become GAP, clean GO blocked>

## Independent re-execution (critical path — step 8.5)
> A blind second context re-ran the critical-path items from the frozen manifest and reported raw output, with no sight of the primary run. A critical `pass` that the re-run can't reproduce, or whose output disagrees, is a **GAP** that blocks a clean GO — investigate the discrepancy, don't average it away. (Strong corroboration, not a hard guarantee; a green acceptance test for the flow supersedes this row.)

| Item ID | Primary actual (quoted) | Independent re-run actual (quoted) | Agree? | Note |
|---------|-------------------------|------------------------------------|--------|------|
| 1 | `<primary raw output>` | `<independent raw output>` | yes / **NO → GAP** | <covered by acceptance test? / discrepancy to chase> |

**Corroboration result:** <all critical-path passes corroborated by the blind re-run → clear | N disagree/unreproduced → GAP, clean GO blocked>

## Found bugs
> One bug — one block. Severity (impact) and Priority (urgency) are two DIFFERENT fields.

> **Severity / Priority rubric (so they aren't a gut call — ISTQB: severity = technical impact, set by QA; priority = business urgency, set by PO).** They are independent: a crash in a dead legacy feature can be high-severity/low-priority; a homepage typo can be low-severity/high-priority.
>
> | Severity | Meaning | Priority | Meaning |
> |----------|---------|----------|---------|
> | blocker | crash / data loss / core feature down, no workaround | high | fix now (before release / hotfix) |
> | major | major feature broken or awkward workaround, many users | medium | fix this cycle |
> | minor | cosmetic / incorrect-but-recoverable, easy workaround | low | backlog |

### <PAY-XXX-BUG-NN> — [<Feature>] <what breaks> <where>
- **Severity:** blocker / major / minor
- **Priority:** high / medium / low
- **Found in round:** R<N>   •   **Fix verified in round:** R<N> / open
- **Build verified against:** <commit/build of the round where the fix was re-tested>
- **Impact:** <who is affected; is there a workaround>
- **Environment:** environment/URL <...>, build/commit <...>, browser+version <...>, device <...>, account <...>, feature flags <...>
- **Repro steps** (EXACT and copy-pasteable, from a clean start — **mandatory for every bug**):
  > Not a mechanism summary — the literal steps a developer can paste and re-run to see the bug: the exact commands (the `psql`/`repl`/`curl`/API call **with real inputs**), the precise UI clicks, and the starting state to set up. "Mechanism + observed states" is not repro; if a dev can't reproduce it from these lines alone, they're not done. A bug without exact repro steps is an **incomplete report** (`verify-report.sh` fails it).
  1. <set up the starting state — exact command/data>
  2. <the exact action that triggers it — verbatim command / request / clicks>
  3. <where to observe the wrong result — exact query/endpoint to read>
- **Expected:** <observable expected behavior>
- **Actual:** <observable actual behavior, no root-cause interpretation>
- **Evidence:** screenshot / video / console+network logs / the raw output of the steps above <links>

## Deferred / Variances
> What was not tested / deviations from the plan and why.

| What | Reason | Impact on verdict |
|------|--------|-------------------|
| <area / case> | <why skipped / blocked> | <none / risk / mitigation> |

## Open questions for PO / discrepancies
> Where the implementation and the ticket disagree, or an AC is missing/ambiguous. Each item is a decision the QA cannot make alone — route it to the Product Owner before the verdict is final.

| # | Question / discrepancy | Jira says | Code does | Needs decision from |
|---|------------------------|-----------|-----------|---------------------|
| 1 | <what is unclear or conflicting> | <AC / description> | <actual behaviour in diff> | PO / Tech lead |

> "none" if the implementation matches the ticket and all AC are explicit.

## Code-review findings
- <file: issue, severity, status>

## Security-review findings
- <vulnerability/risk, severity, status>

## Test data & environment
- **Environment / URL:** <...>
- **Accounts:** <logins / roles>
- **Test cards / payment data:** <...>
- **Feature flags:** <flag = state>
- **Browsers / devices:** <...>
- **Other:** <configs, integrations, test data>

## Best practices (research) — what was applied
- <recommendation + what it applies to + link>  <!-- or "research skipped: <reason>" if tools were unavailable -->

## Recommendation
<What to finish before merge, what to split into a separate ticket, what is OK.>

## Sign-off
| Role | Name | Verdict confirmed | Date |
|------|------|-------------------|------|
| QA | <...> | ✅ / ⚠️ / ⛔ | <date> |
| <Tech lead / PO> | <...> | ✅ / ⚠️ / ⛔ | <date> |
