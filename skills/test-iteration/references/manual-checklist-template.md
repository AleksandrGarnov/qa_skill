# Manual test checklist — <feature / branch>

**Branch:** <branch>
**Base branch:** <base-branch (e.g. develop)>
**Build / commit:** <build-id / commit-hash>
**Date:** <date>
**Environment:** <stage-url>
**Test data / accounts:** <logins, roles, test cards, seeds>
**What changed (1-2 lines):** <summary of changes>
**Acceptance criteria (from jira-context):** <AC1, AC2, … one line each — or "AC missing/inferred — flagged">

---

## Scope & tailoring (right-size before you fill this in)
> Depth must match the change. A one-line CSS tweak does not earn a concurrency or full-negative pass; a payment-flow change earns all of it. Select sections by what the **diff actually touches** and the risk — do not run every section blindly, and do not silently delete the ones you skip.

Rules:
- **Keep a section** if the diff touches its concern (UI changed → UX/UI; endpoint/query changed → Performance + negative; auth/payment/PII → security + full negative).
- **Mark a skipped section `N/A — <reason>`** instead of deleting it (e.g. `Performance — N/A: no runtime path changed, copy-only edit`). Skipping must be a recorded decision, never a silent gap.
- **Smoke + Regression are never skipped** — even a copy change can break a build or an adjacent view.
- **Pull a domain pack** when the change touches a known domain — [domain-packs/](domain-packs/): payments, auth-sessions, forms, file-upload, search, i18n-l10n. Fold the relevant items in; drop the rest as `N/A`.
- The more risk/blast-radius, the more feature-specific items you add on top of the standard sets.

| Change shape | Typically run | Typically N/A |
|--------------|---------------|---------------|
| Copy / CSS-only | Smoke, UX/UI (visual), Regression | Performance (runtime), negative-API, security |
| Pure backend / API | Smoke, Functional, negative, Performance (API), Regression | UX/UI |
| Full feature (UI + API) | All sections | — |
| Config / infra flag | Smoke, Functional (both flag states), Regression | UX/UI, negative-input |

---

## Entry criteria (check before the run)
- [ ] Environment is available and responding (<stage-url>)
- [ ] The required build/commit is deployed to the environment (<build-id / commit-hash>)
- [ ] Test data and accounts are ready (<roles, test cards, seeds>)

> Start the run only after all entry criteria are met. If not met — testing is blocked.

## Test-data preconditions (per item — prepare BEFORE the run)
> Most `blocked` results are really "the data wasn't ready". List what each non-trivial check needs, so it's set up in advance instead of discovered as a block mid-run.

| For item(s) | Account / role | Feature flag | Seed data / fixture | Env |
|-------------|----------------|--------------|---------------------|-----|
| <#…> | <…> | <flag=state> | <…> | <…> |

---

> **All test sections below are tables, one row per check** — columns: **# · What to check · How to run** (the *exact* command / UI steps / API call, verbatim) **· Expected result · Risk** (H/M/L) **· Trace** (AC / ticket). One row = one concrete, runnable check with a verifiable result.

## User journeys (the SPINE — fill this first)
> The checklist is built from journeys, not from code concerns. **Name the user(s)** — often layered: the end-user whose actions create the data, AND the downstream consumer of the output (analyst/service/operator). Each journey is end-to-end: *actor → real action → what it produces across the system → run the feature → observable outcome the actor should see*. The technical/code-branch checks below (filters, type mapping, SQL clauses) are **sub-checks of a journey**, not standalone items. A journey passes only when it works for that user.
> **Live journey vs existing data:** performing the action yourself (produce + consume, traced across every store) covers the journey; validating only against pre-existing/historical data covers the *consuming* half and leaves the *producing* half (action → all stores) `blocked` — mark it so, don't pass it as a live journey.

| # | Actor | Journey (real action, in order) | What it produces/changes (all stores) | How verified (run the feature) | Expected outcome for the actor | Trace |
|---|-------|----------------------------------|----------------------------------------|--------------------------------|--------------------------------|-------|
| J1 | <end-user> | <the action they take> | <rows/events/state created> | <exact command/UI/API> | <what the user should observe> | <AC> |
| J2 | <downstream consumer> | <reads/acts on the output> | — | <exact method> | <output is correct & trustworthy> | <AC> |

> Smoke / Adversarial / Functional / etc. below are the **lenses** applied within these journeys — every row there should trace back to a journey (`J#`), not exist only to verify an internal clause.

## Smoke (critical path)
| # | What to check | How to run (exact command / UI steps / API call) | Expected result | Risk | Trace |
|---|---------------|--------------------------------------------------|-----------------|------|-------|
| 1 | <critical-path action> | <exact method> | <expected> | <H/M/L> | <AC> |

## Adversarial / failure-mode scenarios (try to BREAK it — run these FIRST)
> From the step-5 failure-mode list: "how does this lose/corrupt money/data?" These come *before* happy-path checks. **Mandatory** for any money/state-correctness change — a change of that kind with none here is a coverage gap, not a clean run. Set the dangerous condition deliberately (don't feed fresh consistent data).

| # | Failure mode | How to set the dangerous condition + run | Expected result | Risk | Trace |
|---|--------------|------------------------------------------|-----------------|------|-------|
| 1 | Concurrency / window | <a concurrent action commits in the window between step A and B> | not lost / not double-counted | <H/M/L> | <AC> |
| 2 | Stale snapshot / cache | <the cached/precomputed value is out of date when used> | real value used, not stale | <H/M/L> | <AC> |
| 3 | Negative / boundary / zero | <negative, 0, min/max, overflow> | <expected> | <H/M/L> | <AC> |
| 4 | Compensation / retry mid-run | <repair or retry fires while the operation is in flight> | consistent, no double effect | <H/M/L> | <AC> |
| 5 | Out-of-order / duplicate / partial failure | <events arrive reordered, twice, or one leg fails> | <expected> | <H/M/L> | <AC> |

## Functional checks (per branch changes)
| # | What to check | How to run | Expected result | Risk | Trace |
|---|---------------|-----------|-----------------|------|-------|
| 1 | <item> | <exact method> | <expected> | <H/M/L> | <AC> |

## Risks from code review
> Risk = likelihood × impact (H/M/L). Highest-risk rows first.

| # | Risk / finding | How we check | Expected behaviour | Risk | Trace |
|---|----------------|--------------|--------------------|------|-------|
| 1 | <finding @ file:line> | <exact method> | <expected> | <H/M/L> | <AC> |

## Risks from security review
> Risk = likelihood × impact (H/M/L). Highest-risk rows first.

| # | Vulnerability / risk | How we check | Expected behaviour | Risk | Trace |
|---|----------------------|--------------|--------------------|------|-------|
| 1 | <vuln @ file:line> | <exact method> | <expected> | <H/M/L> | <AC> |

## Edge cases / negative
> ~80% of bugs live at boundaries and in negative cases, not in the happy path. Run the standard set for each input field / endpoint, then add feature-specific rows.

| # | Negative case | How to run | Expected result | Trace |
|---|---------------|-----------|-----------------|-------|
| 1 | null / empty value | <method> | validation / clear error | <AC> |
| 2 | special characters (`' " < > & ; %`) | <method> | correct escaping, no 500 | <AC> |
| 3 | unicode / emoji / RTL | <method> | correct storage & display | <AC> |
| 4 | wrong data type (string↔number) | <method> | rejected with an error | <AC> |
| 5 | BVA boundary: min-1 / min / max / max+1 | <method> | min-1 & max+1 rejected, min & max accepted | <AC> |
| 6 | injection via devtools / direct API (bypass UI) | <method> | server-side validation holds | <AC> |
| 7 | double submit (rapid repeat / two requests) | <method> | no duplicates, idempotent | <AC> |
| 8 | network failure (offline / timeout / drop mid-request) | <method> | clear state, no data loss/corruption | <AC> |
| 9 | <feature-specific invalid input / limit / race> | <method> | <expected> | <AC> |

## UX/UI checks
> Run for any surface a user actually sees. Skip a sub-group only when the change has no UI at all (say so explicitly).
> **How to measure:** responsive → DevTools device toolbar at each breakpoint; accessibility → axe / Lighthouse a11y + a manual keyboard pass (Tab/Shift-Tab/Enter/Esc); contrast → DevTools contrast checker; reduced-motion → emulate `prefers-reduced-motion: reduce`.

| # | What to check | How to run / measure | Expected result | Risk | Trace |
|---|---------------|----------------------|-----------------|------|-------|
| 1 | Responsive at 320 / 375 / 768 / 1024 / 1440 | DevTools device toolbar | no overflow / broken layout; correct reflow | <H/M/L> | <AC> |
| 2 | Visual consistency (spacing/typography/states; shared Button/Input/Modal unchanged where unintended) | by eye vs design | matches design system | <H/M/L> | <AC> |
| 3 | Interaction states hover / focus / active / disabled | keyboard + pointer | present, distinct, focus visible | <H/M/L> | <AC> |
| 4 | User feedback: loading / empty / success / error | trigger each state | clear correct message, no raw error/silent fail | <H/M/L> | <AC> |
| 5 | Accessibility: keyboard reach, labels/ARIA, contrast, reduced-motion | axe + keyboard pass | all controls reachable, adequate contrast | <H/M/L> | <AC> |

## Performance checks
> Compare against the project's targets; if web, the CWV thresholds (LCP < 2.5s, INP < 200ms, CLS < 0.1, FCP < 1.5s). Record the measured number, not "feels fast".
> **How to measure:** CWV → Lighthouse / PageSpeed; INP → DevTools Performance; API time → DevTools Network or `curl -w "%{time_total}\n" -o /dev/null -s <url>`; load → `k6`/`ab` only where warranted.

| # | What to check | How to measure | Measured / Target | Risk | Trace |
|---|---------------|----------------|-------------------|------|-------|
| 1 | Page / view load time | Lighthouse / PageSpeed | <value> / <target> | <H/M/L> | <AC> |
| 2 | API response time (changed endpoints) | DevTools Network / curl | <ms> / <target ms> | <H/M/L> | <AC> |
| 3 | No layout shift (CLS) / no jank from async content | DevTools Performance | <value> / <0.1> | <H/M/L> | <AC> |
| 4 | Behaviour under load / concurrency where relevant | k6 / ab / repeated actions | no degradation, no leaks | <H/M/L> | <AC> |

## Regression (what nearby could have broken)
| # | Adjacent functionality | How to run | Expected result | Trace |
|---|------------------------|-----------|-----------------|-------|
| 1 | <adjacent feature> | <exact method> | <unchanged behaviour> | <AC> |

---

## Exit criteria (go/no-go thresholds — fix and approve BEFORE testing)
> These define the verdict in advance, so it is measured against fixed thresholds rather than judged after the fact. Get them approved together with the checklist. Any unmet criterion → NO-GO.

**Mandatory core — locked (neither QA nor the user may weaken or remove these):**
- [ ] 0 open blocker/major bugs
- [ ] All Smoke (critical path) items pass
- [ ] Critical-path coverage = 100% (no critical item left blocked / not executed)
- [ ] Every explicit AC covered & passing *(N/A only if the run is flagged `exploratory — no AC`; verdict then capped at ⚠️ GO (exploratory))*
- [ ] Security findings closed or explicitly mitigated

**Project-specific — add stricter lines on top (never to replace the core):**
- [ ] Regression is green
- [ ] <feature-specific threshold, e.g. `p95 API latency <= 300ms`, `0 console errors`>

---

> Checklist is **tabular**: one row per check, columns **# · What to check · How to run · Expected result · Risk · Trace**. Each row = a concrete, runnable action with a verifiable result and an *exact* method (a command/UI-steps/API-call, not "check that it works"). Tie every row to a real change, an identified risk, or an AC — coverage must be traceable. (At execution the report's results table extends each row with `Result · Evidence · Actual raw output`.)

### Risk rubric (so H/M/L isn't a gut call)
Risk = **impact × likelihood**. Anchor each axis, then combine (High on either axis with Medium+ on the other → H).

| | High | Medium | Low |
|---|------|--------|-----|
| **Impact** | money, auth, security, PII, data loss/corruption, blocks the core flow | wrong-but-recoverable behaviour, degraded UX, workaround exists | cosmetic, copy, non-blocking edge |
| **Likelihood** | on the main path, common input, no workaround, touches changed core logic | secondary path, specific-but-realistic input, partial mitigation | rare/contrived input, hard-to-hit timing, far from the change |

> Record results: bucket each item **pass / fail / blocked / flaky / N/A (reason) / not executed**. An applicable check you couldn't run is **blocked** (a gap), not `not executed`. A result that flips pass/fail on the same build is **flaky** (a gap — see [flaky-protocol.md](flaky-protocol.md)), not a `pass`. Never let a real check silently evaporate.
