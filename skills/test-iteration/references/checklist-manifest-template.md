# Checklist manifest — <feature / branch>
> The **frozen, approved contract** for this run (locked at step 7). The report (step 9) is cross-checked against it by `scripts/verify-coverage.sh`, which fails closed if **any item ID here has no result row** (a skipped item) or **any item doesn't trace to a journey** below. Built from **user journeys, not code concerns** — define the journeys first, then hang every item off one.

**Branch:** <branch>   **Build / commit:** <commit>   **Approved:** <date>
**Sidecars:** `manifest.json` mirrors this file for automation; keep the same journey IDs (`J#`) and item IDs here and there, and mirror each item's `technique` field alongside its `acRefs`.

## Context (system guidelines — gathered BEFORE approval; gate: `verify-context.sh`)
> Fill each block by running the **tool**, not from memory — the gate fails closed on an empty/placeholder block, and so does the merge-gate hook. This makes the front-loaded steps non-skippable.

### Discussion — GitHub PR + Jira comments  *(guideline 1)*
<paste the fetched `gh pr view <PR> --comments` output + the Jira ticket discussion — or `no PR` / `no ticket`>

### Prior tests  *(guideline 4)*
<`prior-tests.sh` result — one of: `FRESH — first test (NONE)` · `RE-TEST of <prior doc>@<commit> — carried findings: <R1…>`. On RE-TEST the items below are built on the old runs.>

### Research (Exa)  *(guideline 2)*
<the Exa findings turned into checks, each dispositioned — or `research skipped: <reason>` only if no search tool exists>

### Adversarial (break-it pass — step 4.5)
<the adversarial subagent's landed + not-landed attacks, each dispositioned into an item below: a landed break → a FAIL-candidate item with its reproducing test; a not-landed attack → a hardening/regression check. State `no attacks landed` only after a real pass ran — never leave this empty to skip the pass.>

### Clarifications (pre-test interview — step 4.7, `qa-interview`)
<the Q→A from the interview that shaped the checklist: the oracle each computed/money/state item was checked against, the business rules behind each decision-table, valid/forbidden transitions, real boundaries (null vs 0), out-of-scope, and the "done" bar. Each answer should trace to an item/Expected source/exit-criterion below. An unresolved CRITICAL question goes to the report's "Open questions for PO" block AND a `blocked` critical item — never guessed. Omit this block only for a trivial change with no intent to clarify.>

## Journeys (the SPINE — define these FIRST)
> Name the real user(s) — often layered: the actor who *creates* the data and the downstream *consumer* of the output. A journey is end-to-end: actor → real action → what it produces across stores → observable outcome the actor sees. If you can't name a journey, you're about to write a code-concern checklist — stop.

| J | Actor | Action (real, in order) | Observable outcome the actor sees |
|---|-------|-------------------------|-----------------------------------|
| J1 | <end-user> | <the action they take> | <what they should observe> |
| J2 | <downstream consumer> | <reads / acts on the output> | <output is correct & trustworthy> |

## Items (every item traces to a J above)
> One row per check. The **ID** is stable and is reused verbatim as the `#` in the report's Checklist results table — that's how coverage is matched. **Journey** must be one of the J ids above (an item with no journey is rejected). **AC refs** must point at the acceptance-criteria IDs carried from `jira-context`, and the same refs go into `manifest.json`. **Technique** names the test-design technique that produced the row's values/combination/sequence — one of `equivalence`, `boundary`, `decision-table`, `state-transition`, `use-case`, `pairwise`, `error-guessing`, `classification-tree`, `exploratory`, or `n/a — <reason>` for a trivial single-value smoke/regression check ([test-design-techniques.md](test-design-techniques.md)); `verify-coverage.sh` rejects a blank cell or a value outside this vocabulary (choosing the *right* technique is checked at the step-6.5 review, not by the gate). **Expected + Expected source**: the expected result and where it was derived — a source that is **not the implementation under test** (spec/formula, hand calc, invariant, reference impl, trusted historical), or a **metamorphic invariant** for an oracle-hard item ([test-oracle.md](test-oracle.md)); an expected of "whatever the code returns" is not a valid oracle. **Once approved, every item is non-skippable** — there is no "important vs optional" tier; if it's in the contract it must be executed. Smoke + Regression are never dropped; right-size the rest (`N/A — <reason>` at checklist time instead of adding it).

| ID | Journey | AC refs | Technique | What to run (exact command / UI steps / API call) | Expected | Expected source (independent of the impl) |
|----|---------|---------|-----------|----------------------------------------------------|----------|-------------------------------------------|
| 1 | J1 | AC1 | boundary | <exact method> | <expected value> | <spec §/hand calc/invariant/reference — or metamorphic rule> |
| 2 | J1 | AC2 | decision-table | <exact method> | <expected value> | <…> |
| 3 | J2 | AC3 | state-transition | <exact method> | <expected value> | <…> |

> After approval this file is the contract. `verify-coverage.sh <this-file> <report.md>` → `COVERAGE-OK` requires the step-9 report to carry a result row for **every** ID above **and** that none is `not executed`/absent (run it, or `blocked` with a documented attempt — never silently skipped), all journey-rooted, each declaring a recognized `Technique` and an independent `Expected source`.

## Technique coverage (quantify each enumerable technique — a complex space can't collapse to one check)
> One row per **enumerable** technique you used (`decision-table`, `state-transition`, `pairwise`, `boundary`) with a **numeric** coverage claim. `verify-coverage.sh` fails closed if an enumerable technique is used in `## Items` but this section is missing or its claim states no number (whether the number is *arithmetically right* is the step-6.5 review's call). Non-enumerable techniques (`equivalence`/`use-case`/`error-guessing`/`classification-tree`/`exploratory`/`n/a`) need no row here.

| Technique | Coverage claim (state the numbers) |
|-----------|------------------------------------|
| decision-table | <N feasible rules, N covered (dropped M infeasible, merged K don't-cares)> |
| state-transition | <criterion, V valid + I invalid transitions> |
| pairwise | <N cases, all 2-way pairs; t=3 on {…}> |
| boundary | <N classes / min−1·min·max·max+1 per ordered field {…}> |

## Changed-surface coverage (Test-Gap — every changed behaviour maps to a check, so the checklist scales to the diff)
> **Frozen from `changed-surfaces.sh <branch> [base]` at approval.** This is what stops a big change ("2000 lines") from being "covered" by a handful of items: each changed behaviour-surface (a changed non-noise file, or `file::function` where git names the hunk) must map to **≥1 item ID from ## Items**, or an explicit **`N/A — <reason>`** (pure refactor/rename, config-only, dead code, generated). `verify-gap.sh <this-file> <surfaces-file>` fails closed on any surface with **no row** (unmapped) or a row with **no covering item and no reasoned N/A**. Structural only — that the named items *truly exercise* the surface is checked at the step-6.5 review. Paste the `changed-surfaces.sh` output as the rows; do **not** trim it to make the gate pass (the frozen surfaces file is the source of truth the merge-gate re-checks).

| Changed surface | Covered by items | Notes |
|-----------------|------------------|-------|
| <path/to/File.ext::function or method> | I1, I8 | <how these items exercise it> |
| <path/to/Other.ext> | I3 | <…> |
| <path/to/Migration_or_config.ext> | N/A | <schema-only, no behaviour path> |

> Every surface emitted by `changed-surfaces.sh` must appear here. A surface tested on multiple journeys lists all covering IDs. An `N/A` needs a real reason — a bare `N/A` is rejected. The blast-radius of the change (callers of the changed code) should surface as **Regression** items above, not be dropped here.
