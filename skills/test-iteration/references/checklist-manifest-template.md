# Checklist manifest — <feature / branch>
> The **frozen, approved contract** for this run (locked at step 7). The report (step 9) is cross-checked against it by `scripts/verify-coverage.sh`, which fails closed if **any item ID here has no result row** (a skipped item) or **any item doesn't trace to a journey** below. Built from **user journeys, not code concerns** — define the journeys first, then hang every item off one.

**Branch:** <branch>   **Build / commit:** <commit>   **Approved:** <date>

## Context (system guidelines — gathered BEFORE approval; gate: `verify-context.sh`)
> Fill each block by running the **tool**, not from memory — the gate fails closed on an empty/placeholder block, and so does the merge-gate hook. This makes the front-loaded steps non-skippable.

### Discussion — GitHub PR + Jira comments  *(guideline 1)*
<paste the fetched `gh pr view <PR> --comments` output + the Jira ticket discussion — or `no PR` / `no ticket`>

### Prior tests  *(guideline 4)*
<`prior-tests.sh` result — one of: `FRESH — first test (NONE)` · `RE-TEST of <prior doc>@<commit> — carried findings: <R1…>`. On RE-TEST the items below are built on the old runs.>

### Research (Exa)  *(guideline 2)*
<the Exa findings turned into checks, each dispositioned — or `research skipped: <reason>` only if no search tool exists>

## Journeys (the SPINE — define these FIRST)
> Name the real user(s) — often layered: the actor who *creates* the data and the downstream *consumer* of the output. A journey is end-to-end: actor → real action → what it produces across stores → observable outcome the actor sees. If you can't name a journey, you're about to write a code-concern checklist — stop.

| J | Actor | Action (real, in order) | Observable outcome the actor sees |
|---|-------|-------------------------|-----------------------------------|
| J1 | <end-user> | <the action they take> | <what they should observe> |
| J2 | <downstream consumer> | <reads / acts on the output> | <output is correct & trustworthy> |

## Items (every item traces to a J above)
> One row per check. The **ID** is stable and is reused verbatim as the `#` in the report's Checklist results table — that's how coverage is matched. **Journey** must be one of the J ids above (an item with no journey is rejected). **Once approved, every item is non-skippable** — there is no "important vs optional" tier; if it's in the contract it must be executed. Smoke + Regression are never dropped; right-size the rest (`N/A — <reason>` at checklist time instead of adding it).

| ID | Journey | What to run (exact command / UI steps / API call) | Expected |
|----|---------|----------------------------------------------------|----------|
| 1 | J1 | <exact method> | <expected> |
| 2 | J1 | <exact method> | <expected> |
| 3 | J2 | <exact method> | <expected> |

> After approval this file is the contract. `verify-coverage.sh <this-file> <report.md>` → `COVERAGE-OK` requires the step-9 report to carry a result row for **every** ID above **and** that none is `not executed`/absent (run it, or `blocked` with a documented attempt — never silently skipped), all journey-rooted.
