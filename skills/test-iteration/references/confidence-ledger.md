# Confidence ledger

The trust metric that decides **when a task class is safe to run with less human presence** — the KPI
from the agentic-engineering idea of a growing streak of clean, one-shot runs. It is the input to the
presence decision at step 7 (and, when enabled, the ZTE/auto-approve path).

## What it tracks

A plain markdown table (`<test-docs>/qa-confidence.md`), one row per QA cycle outcome, per component:

| # | Component / area | Outcome | Run / ADW id | Date |
|---|------------------|---------|--------------|------|
| 1 | bonus            | GO      | adw-39       | 2026-06-07 |
| 2 | bonus            | ESCAPE  | adw-51       | 2026-06-12 |
| 3 | bonus            | GO      | adw-58       | 2026-06-13 |

- **GO** — written at step 9 on a **clean** ✅ GO only (never for GO-with-deferrals, exploratory, or NO-GO).
- **ESCAPE** — written at step 12 when a defect slips past a GO and later surfaces.

## The streak

`streak` = the number of clean GOs in a row **since the last escape** for that component. In the table
above, `bonus` has a streak of **1** (the escape at row 2 reset it; only row 3 counts).

The streak — not the raw count — is the signal, because an escape means the agent layer is *not yet*
reliable for that class, and trust has to be re-earned.

## How the skill uses it

- **Step 1 — read (advice only):** `confidence.sh suggest <file> "<component>"`
  - `READY-FOR-PRESENCE-REDUCTION` (streak ≥ threshold, default 5) → **offer** the user a lower-presence
    / auto-approve run at step 7. Never auto-applied — lowering presence is the user's explicit opt-in.
  - `KEEP-PRESENCE` → manual approval as usual.
- **Step 9 — write GO:** on a clean GO, `confidence.sh record <file> "<component>" go "<run id>"`.
- **Step 12 — write ESCAPE:** on a post-GO escape, `confidence.sh record <file> "<component>" escape "<run id>"`.

## Why this is safe

Confidence lowers **ceremony**, never the **safety floor**. Even at a high streak with presence reduced,
the merge-gate hook (`finalize-gate.sh`) still physically blocks the merge unless `CONTEXT-OK` +
`REPORT-OK` + `COVERAGE-OK` all pass. The ledger decides *how much a human watches*; the gates decide
*whether the work is allowed to merge* — and those gates never relax.

The threshold is configurable via `CONFIDENCE_THRESHOLD` (default 5).
