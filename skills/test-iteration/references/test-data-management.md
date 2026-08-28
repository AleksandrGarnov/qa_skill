# Reference — test data management (TDM)

Test data is the ground every result stands on. Industry data is blunt about it: **30–40% of testing time is lost to data prep, ~40% of flaky failures trace to test data, and ~70% of teams have no deliberate TDM strategy** (Total Shift Left, TestRail 2026). The skill already mandates a **freshly-created subject per scenario** (step 5/8) — this reference covers the rest of the lifecycle that mandate implies but doesn't spell out: isolate it, source it safely, validate it before the run, and **tear it down after**.

This is manual staging QA, not a CI container farm — so TDM here is a discipline, not a tool. But the lifecycle is the same: **identify → provision → isolate → validate → execute → teardown/retire.**

## 1. Identify (before the run — folds into per-item preconditions)
For each non-trivial check, name exactly what data it needs: account/role, feature-flag state, seed rows, the *shape* that triggers the case (a legacy record with null fields, a user with 15 roles, a 10-year-old date, a list long enough to paginate). Most `blocked` results are really "the data wasn't ready" — surface the need up front (the checklist's Test-data preconditions table).

## 2. Provision safely — never production PII
- **Prefer synthetic / freshly-created data.** Register a new user, create new records through the real entry point (this also exercises the produce leg of the journey). Synthetic data carries **zero compliance risk** and no coupling to another test's state.
- **If you need production-like volume/shape, use a masked, subsetted copy — never a raw production dump.** Mask every PII/financial/health field with deterministic masking (same input → same masked value, so referential integrity survives). Subset (the 5 GB that covers the scenarios, not the 500 GB full copy). This aligns with the hard rule: **production data is off-limits; a masked non-prod copy is the only production-shaped data you touch.**
- Realistic shape matters: testing with 100 clean rows when production has 10M messy ones hides pagination, performance, null-handling, and date bugs. Cover the messy classes deliberately (nulls, legacy formats, unicode, extreme dates, many-roles).

## 3. Isolate per run (the single highest-leverage fix for flaky)
Shared mutable test data is the most common cause of "why did this pass yesterday" flakiness. Give each scenario its **own** subject/data so runs can't pollute each other — a fresh account, a unique key (UUID/timestamp), a distinct record set. A reused fixture carries accumulated state and hidden coupling and skips the real creation path; a fresh, isolated subject exercises produce-then-consume cleanly and can't be corrupted by a parallel check.

## 4. Validate before executing
Before the run, confirm the data is actually in the state the check assumes — the account exists with the right role, the flag is set, the seed rows are present and well-formed. Catching a data problem here saves it being mis-diagnosed as a product `blocked` mid-run.

## 5. Teardown / retire (the step everyone skips)
Tests that create data must clean it up — otherwise staging accumulates stale records that slow queries, exhaust unique identifiers, and turn into false positives/negatives for the next run (and the next tester). Choose the lightest teardown that works:
- **API-driven teardown** — delete what you created through the app's own endpoints (preferred for E2E-style manual runs that span services).
- **Transaction rollback** — where the check is a single-store operation you can wrap and roll back.
- **Snapshot/reset** — restore a known-clean baseline between suites where the environment supports it.
- **Retire the long-lived cruft** — expire old test accounts, tokens, and fixtures on a cadence; don't let last quarter's `test-user-42469` become everyone's implicit dependency.
Record the teardown in the report (what was created, how it was removed, or why it was safe to leave) so the environment stays a clean baseline, not a landfill.

## 6. Refresh cadence (for shared staging data)
Stale data hides bugs that only appear against current shapes; refreshing too often breaks fixture-dependent checks. Typical landing spot: refresh shared staging weekly / per sprint (masked subset), with on-demand refresh when debugging a specific data-shape issue. Whatever the cadence — document it; "nobody knows when staging data was last refreshed" is itself a defect source.

## How it plugs into the cycle
- **Step 6 (checklist):** the Test-data **preconditions** table (setup) gains a matching **teardown** line per item — creation and cleanup are one decision, not an afterthought.
- **Step 8 (execution):** provision a fresh, isolated subject per scenario; validate its state before triggering; tear it down (or record why it's safe to leave) after.
- **Never** let TDM become a reason to touch production: masked non-prod copies and synthetic data only.

> Sources: Total Shift Left — *Test Data Management Strategy 2026* (per-run isolation, containerized provisioning, cleanup/teardown, "poor test data = #1 cause of flaky, ~40% of failures"); TestRail — *Test Data Management Best Practices* (masking, synthetic data, refresh cadence); ARDURA — *Test Data Management Strategy Guide* (masked-vs-synthetic tradeoff, GDPR/CCPA); *Test Environment Management: A Practical Guide* (isolation, scheduled decommissioning, "30–40% of testing time lost to data prep").
