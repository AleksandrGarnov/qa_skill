# Learned checks — the feedback loop

How the QA process gets **smarter run-over-run** without training a model: a growing, project-level
table of checks distilled from real outcomes. Past checklists and reports are not thrown away — the
checks that *caught bugs* (or escaped and shouldn't have) re-enter every relevant future checklist.

This is **in-context learning + a curated store**, not fine-tuning. Plain markdown + `grep`, no
embeddings (add those only if the store grows large enough that keyword `match` starts missing).

## Where it lives
One file per project, in the **test-docs path** (the same place reports/checklists are stored, read
from `CLAUDE.md`): `<test-docs-path>/learned-checks.md`. Managed by `scripts/learned-checks.sh`.

## The loop
- **Write (step 12):** when a defect escapes a GO build, *or* a killer item proves its worth across
  runs, distil it into a row:
  ```bash
  learned-checks.sh add <test-docs>/learned-checks.md "<component>" "<the check>" "<why it was learned>"
  ```
- **Read (step 5):** when building a new checklist, pull the rows matching the changed components and
  fold every match in:
  ```bash
  learned-checks.sh match <test-docs>/learned-checks.md <changed-component-keywords…>
  ```
- **Enforce (step 6.5):** the independent completeness review is given the matching learned checks and
  flags any that weren't folded into the checklist — so a hard-won check can't quietly drop out.

## Row format
| # | Component / area | Check (what to verify) | Why (the escape/recurrence that taught it) | Added |
|---|------------------|------------------------|--------------------------------------------|-------|
| 1 | wallet/balance | a concurrent debit in the window between read and write doesn't double-count | QA-8771: balance drift escaped GO under an Octane tx leak | 2026-06-05 |

Keep it append-only and curated — a short, high-signal store of checks that earned their place, not a
dump of every item ever written. Relationship to [escaped-defects.md](escaped-defects.md): that logs
the *incident*; this stores the *reusable check* it produced.

## Backfill from history (seed the store from old reports — run once)
The store doesn't have to start empty. If a corpus of past reports already exists in the test-docs
path, mine it once to seed `learned-checks.md`, then the going-forward loop continues it:
```bash
learned-checks.sh scan <test-docs-path>        # lists <report-file>\t<bug heading> for every past bug
```
`scan` is **mechanical** — it extracts the bug candidates from every report's `## Found bugs` section
so you don't open each file by hand. Then **curate**: the highest-signal candidates are the ones that
**recur** (same component/bug across multiple reports) or **escaped a GO** — distil those into reusable
checks with `add`, skip the one-offs. Backfill is a seed, not gospel: rough rows you refine, not a
guarantee. Old reports that predate the `## Found bugs` format are read by hand.
