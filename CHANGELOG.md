# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres
to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.22.0] - 2026-06-07

### Added
- **Confidence ledger — a trust metric for lowering human presence on a task class** (`scripts/confidence.sh`
  + `skills/test-iteration/references/confidence-ledger.md`). A per-component markdown ledger of QA outcomes:
  step 9 records a clean GO, step 12 records an escape (which resets the streak). The *streak* — clean GOs in
  a row since the last escape — is the signal that the agent layer handles that task class reliably. Step 1
  reads `confidence.sh suggest` and, on a long streak, **offers** the user a lower-presence / auto-approve run
  at step 7. Lowering presence is always the user's explicit opt-in, and the merge-gate hook still enforces
  `CONTEXT-OK + REPORT-OK + COVERAGE-OK` regardless — confidence lowers ceremony, never the safety floor.
  Plain markdown + awk, same shape as `learned-checks.sh`; 17 self-contained tests in `scripts/tests/`.

## [2.21.1] - 2026-06-06

### Changed
- **README reworked for clarity and conversion** — a value-prop lead ("won't rubber-stamp green tests"),
  a Why / What-it-does framing, a flow diagram, badges, and a placeholder for a merge-gate demo GIF.
  Install is surfaced up top, with the skills CLI (`npx skills add`) as the recommended cross-agent
  method alongside the plugin marketplace; install options were renumbered accordingly.
- **`test-iteration` description** now front-loads triggers (pre-merge, Claude Code, Jira AC) and the
  evidence-gate differentiator, so the skill triggers more reliably and reads better in marketplace
  listings. Docs/metadata only — no behavior change.

## [2.21.0] - 2026-06-05

### Added
- **Learning loop — the QA process gets smarter run-over-run from past checklists/reports (no model
  training).** New `scripts/learned-checks.sh` maintains a growing, project-level store
  (`<test-docs>/learned-checks.md`) of checks distilled from **real outcomes**: a defect that escaped a
  GO, or a killer item that proved its worth across runs. The loop:
  - **Write (step 12):** an escape / recurring killer item is distilled into a learned-check row
    (`learned-checks.sh add`), alongside the existing escaped-defects log.
  - **Read (step 5):** the checklist build pulls the rows matching the changed components
    (`learned-checks.sh match`) and folds every match in — so a check that caught a bug re-enters every
    relevant future run instead of being re-derived from a blank slate.
  - **Enforce (step 6.5):** the independent completeness review is given the matching learned checks and
    flags any not folded into the checklist.
  This is **in-context learning + a curated store**, not fine-tuning — plain markdown + `grep`, no
  embeddings (add those only if the store outgrows keyword `match`). See `references/learned-checks.md`.
  - **Backfill from history:** `learned-checks.sh scan <test-docs-path>` mines the *existing* corpus of
    past reports (every `## Found bugs` block) for candidates, so the store can be seeded from history in
    one pass rather than only learning from new runs forward; you then curate the recurring/escaped ones
    into `add`. 18 tests total.
  - **`/learned-backfill` skill** — a one-shot command that wraps the backfill end-to-end: resolve the
    test-docs path → `scan` → curate the recurring/GO-escaped candidates → **pause for your approval** →
    `add`. "Learn from old data" in a single invocation; run once, then the going-forward loop continues.

## [2.20.0] - 2026-06-05

### Added
- **System input-guidelines gate (`verify-context.sh`) — the front-loaded steps become non-skippable
  invariants, not prose.** The manifest opens with a `## Context` block the agent fills by running the
  *tools*, and the gate fails closed (and the merge-gate hook re-checks) unless each block has real
  content: **`Discussion`** = the *fetched* GitHub PR + Jira comments (guideline 1 — read the comments,
  not "I read them"); **`Prior tests`** = a `FRESH`/`RE-TEST` basis from `prior-tests.sh` (guideline 4 —
  a re-test builds on the old runs); **`Research (Exa)`** = the Exa findings (guideline 2 — always
  research; journey-rooting in `verify-coverage.sh` enforces "user-flow first, code-branches under it").
  Guideline 3 (never skip a checklist item) is the manifest/coverage/required gates already in this
  release. `CONTEXT-OK` is now required for a clean GO and is enforced at the merge wall. 8 tests.
  **Honest limit:** guarantees the inputs were *gathered and present*, not that the agent *absorbed*
  them — that stays the human approval gate.
- **Merge-gate hook — enforcement moves OUT of the agent's step list, so a checklist item can't be
  skipped even if the agent skips the gate.** The step-9 gates only bind if the agent remembers to run
  them; a negligent agent could skip the gate itself. This ships a **PreToolUse hook**
  (`hooks/hooks.json` → `scripts/finalize-gate.sh`) that Claude Code fires *before* a branch-finalizing
  command (`git merge` / `git push` / `gh pr merge`) and **blocks it with exit code 2** unless
  `CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK` all pass. It's outside the agent's token stream — the
  agent cannot talk past it (per Anthropic issue #39851: prose "NEVER skip" is bypassable; an exit-2
  PreToolUse hook is the only reliable Claude Code block). It is a **no-op unless a QA run is in
  progress**: the skill writes a run-state file (`.claude/qa-run.json`, manifest + report paths) at
  steps 7/9, and the hook only engages when that file exists — so ordinary pushes outside a QA run are
  never touched. Once a run is started, its branch cannot be merged with a skipped/not-executed
  checklist item, ungathered context, or an incomplete report. 8 hook tests.
  - **Disclosure:** this plugin now ships a hook that can block `git merge`/`push`/`gh pr merge` while a
    QA run is active. If your project merges via PR/CI rather than locally, retarget the matcher in
    `hooks/hooks.json` (documented in `scripts/finalize-gate.sh`).
  - **Honest limit:** guarantees an active QA run can't be merged until the gates are green; a fully
    adversarial agent deleting `.claude/qa-run.json` is out of scope (forbidden at the prompt level) —
    this stops the *negligent* skip, which is the actual recurring failure.
- Fixed `verify-coverage.sh` to locate the manifest's Journey column by header (was positional col-2),
  so it survives the new `Must` column.

## [2.19.0] - 2026-06-04

### Added
- **Frozen checklist manifest + `verify-coverage.sh` — kills the two recurring escapes: skipped
  items and code-rooted checklists.** Both are *structural* set-membership checks (not the semantic
  parsing reverted in 2.18.0), so they bind reliably:
  - The approved checklist is emitted as a **frozen manifest** ([checklist-manifest-template.md]) —
    **journeys defined first** (named actor → action → observable outcome), then **items each with a
    stable ID and a journey ref**. Frozen at step-7 approval; it's the contract.
  - `scripts/verify-coverage.sh <manifest> <report>` set-diffs item IDs: **any approved ID with no
    result row in the report fails the verdict** (a skipped item can't go silently missing), and **any
    item with no journey / a manifest with no journeys fails** (a checklist built from code concerns
    instead of user journeys is rejected by construction). Drift (rows added during the run) is a NOTE,
    not a failure. The report's `#` column reuses the manifest IDs verbatim so the diff matches.
  - Wired into steps 6 (emit manifest), 7 (freeze on approval), 9 (run alongside `verify-report.sh`;
    `COVERAGE-OK` is now required for a clean GO). 8 new tests.
  - **Honest limit:** this guarantees no item *disappears* and the checklist *is* journey-rooted; it
    does not prove a `pass` is truthful or a journey is genuine — that stays the evidence self-audit +
    the step-6.5 independent reviewer + the human verdict.
- **Every approved checklist item is non-skippable (no "important vs optional" tier).** Rather than a
  per-item must-pass flag, `verify-coverage.sh` now fails the verdict if any approved manifest item is
  **missing a result row OR marked `not executed`** — once a check is in the approved contract it must be
  run (or `blocked` with a documented attempt), never silently skipped. Pure structural set-membership +
  status check (no semantic parsing); the manifest is approved by the user, so the contract is theirs.
  Backed by a 4-agent research fan-out (orchestration / aviation+surgical checklists / policy-as-code /
  LLM reliability) that converged: a step is never skipped only when something *outside the LLM's tokens*
  blocks progress without a proof artifact — prose never binds (the hard block is the merge-gate hook,
  below). **Honest limit:** guarantees a checklist item is *present and executed*, not that its `pass` is
  truthful — that stays the step-8.5 independent re-run + the human verdict.
- **Independent re-execution of the critical path (step 8.5) — unbiased corroboration of a `pass`.**
  A fresh blind subagent re-executes the critical-path / money-state items from the frozen manifest
  (commands only — no sight of the primary run's results or reasoning) and returns raw outputs; each
  critical `pass` must be **corroborated by the independent re-run** (outputs agree), or the
  discrepancy is a **GAP** that blocks a clean GO. New report section *Independent re-execution*, and
  the verdict now requires critical-path corroboration. **This is strong corroboration, not a hard
  guarantee** (both are LLMs) — the only hard guarantee is a runnable black-box acceptance test for
  the flow (green/red by code), which supersedes this step where it exists; that bridge is the next
  step (needs staging access).

## [2.18.0] - 2026-06-04

### Changed
- **Reverted the script-level enforcement gates added in 2.17.0; kept their principles as prose.**
  An independent audit found the 2.17.0 approach net-negative: making `verify-report.sh` parse
  markdown tables to enforce *semantic* QA rules (evidence-gate, clean-GO self-audit, Research ledger,
  Trigger column) was **brittle and gave false confidence** — verdict detection keyed on a `**Verdict:**`
  line the template doesn't force (so the clean-GO gates silently no-op on the template's own shape),
  substring matches like `ev ~ /api/` fired on "r**api**d", and column reads were positional. It also
  **re-grew the "wall of prose"** the 243→111 consolidation removed (the same rule restated 4–7×) and
  forced **mandatory Research-ledger + Trigger columns onto every report**, contradicting the skill's own
  right-size principle. So `verify-report.sh` returns to its honest role — checking that a report is
  **structurally complete** (nothing blank/placeholder), not semantically correct — and the four
  principles are kept as **one prose anchor each**, not a bash gate:
  - **A user-facing change isn't closed by green code checks.** Mandatory core: a runtime/user-facing AC
    is closed on a live observation (`observed-data`/`api`/`log`), never on `code-read`/`unit:mocked`/`repl`
    alone (the evidence-gate + self-audit prose already in step 9 carry this).
  - **`repl`/`cli`/DB are supporting tools, not the flow-driver.** Trigger the action via the real
    entry point (UI / API as a client); never reconstruct the whole flow in `repl` (a proxy).
  - **Surfacing is not a resolution (no punt).** An approved check is executed, or `blocked` after a
    documented attempt; you ask for access to *finish* it, not for permission to ship the gap; a
    `blocked`/unrun critical-path/AC item is ⛔ NO-GO, never a deferral (deferral is for a *defect*).
  - **Research is mined into checks.** Drill the specifics with follow-up searches; disposition every
    surfaced scenario to a check or an explicit `rejected: <reason>`; step-6.5's independent review flags
    a finding that became neither.
  Net diff vs 2.17.0: **+36 / −335 lines**; `verify-report.sh` 201→95, test-report-template 182→174.

## [2.17.0] - 2026-06-04

### Changed
- **Two core rules turned from prose into mechanical gates in `verify-report.sh` — so they can't
  be skipped under "the report looks done" pressure.** Both rules already existed as guidance; they
  now fail the report closed:
  - **A user-facing change can't reach GO on green code checks.** The AC traceability evidence-gate
    is now script-enforced: an AC row marked `pass` while its Evidence is only `code-read`/`unit:mocked`
    fails the report — a runtime/user-facing AC's verdict must rest on a real observation
    (`observed-data`/`api`/`log`), never on supporting unit/repl/code checks alone. The
    live-observation clause is also written into the **non-overridable mandatory core** (step 6), and a
    clean ✅ GO now requires a **filled Pre-verdict evidence self-audit** (every `pass` row quotes its
    raw output) — both checked by the script.
  - **Research must be mined into checks, not run-and-summarized.** New **Research ledger** section
    (replaces the loose "Best practices applied" bullet list): every concrete scenario a search surfaced
    is dispositioned to a checklist item or an explicit `rejected: <reason>`. `verify-report.sh` fails a
    report whose ledger is missing, has an unfilled row, or lists no dispositioned finding (unless research
    was genuinely skipped on a bare install).
- **`qa-research` no longer treats research as one broad pass.** Added a **drill-the-specifics** step
  (a first search surfaces *names* — a mechanism, a class, a known failure mode — each gets a follow-up
  search to nail the concrete scenario) and changed the done-when: every surfaced scenario is either an
  observable `check:` or an explicit `rejected: <reason>` — silently dropping a concrete scenario, or
  pasting one summary line, is a failed research pass. Step 6.5's independent completeness review now also
  flags any research finding that became neither a check nor a recorded reject.
- Added 8 `verify-report.sh` test cases covering the new gates (evidence-gate pass/fail, self-audit
  presence + empty-quote, research-ledger missing / summary-only / placeholder).
- **`repl`/`cli`/DB are supporting tools, not the flow-driver — we are manual testers (now a hard gate).** The
  user's action is triggered through the **real entry point** (UI, or the API as a client); `repl`
  is for setting up preconditions, reading the resulting state, and isolated assists. **The whole flow
  is never reconstructed in `repl`** — calling an internal service/method stands in for the user
  (a proxy for the code path), not the user journey, so it can't close a user-facing AC. If the flow
  is API-drivable, drive it via the API yourself and let `repl` help. Enforced by a new **`Trigger`
  column** (`ui`/`api`/`command`/`db`/`n-a`) on the report's checklist results table: `verify-report.sh`
  **fails** any `pass` row with `Trigger=repl`, and fails a checklist missing the column outright.
  Also reclassified in the Principles + step 8 (5-part execution record) and named in the proxy rule.

## [2.16.0] - 2026-06-04

### Changed
- **Consolidated `test-iteration` SKILL.md (243 → 111 lines, ~9k → ~3.1k tokens).** Sixteen
  releases had grown the skill into ~12 overlapping principles and two huge steps; a wall of prose
  is harder for a model to honor under pressure, not easier. Merged the integrity cluster
  (falsify / coverage-by-execution / no-proxy / no-assumed-equivalence / live≠historical /
  honest-ledger / raw-observation) into a single **"Coverage is what you executed and observed"**
  principle, tightened steps 5 and 8, and leaned on the **scripts** (`verify-report.sh` et al.) as
  the real enforcement rather than repeating their rationale in prose. **Every gate, script, and
  rule is preserved** (verified); behaviour is unchanged. Also folds in **"read the task's
  discussion before analysing it"** as a Principle (was only reachable via step 1's full cycle, so
  ad-hoc bug-theorising skipped it).
- **Test on freshly-created subjects, not reused fixtures.** A live journey must be run on a
  newly-created subject (register a new user / create new data per scenario), not an old reused
  test account — a reused fixture carries accumulated state and hidden coupling and skips the real
  creation path; a fresh one isolates the action's effect and exercises produce-then-consume cleanly.

## [2.15.0] - 2026-06-04

### Added
- **Live journey ≠ validating against existing data (produce vs consume).** step 5 now states:
  validating a read-only feature over accumulated/historical data tests only the **consuming** half
  (does the code read/count correctly), not the **producing** half (does the user's action create
  the right state across **every** store). A journey is covered only by performing the action
  and tracing it end-to-end, or by justifying the production leg out-of-scope with evidence;
  "validated on existing data" is a proxy that silently drops the production leg → record the
  journey as `blocked`, not pass.

## [2.14.0] - 2026-06-04

### Added
- **Honest coverage ledger + no clean GO over an incomplete run.** Prevents a report presenting
  "objectively confirmed / clean" while several approved checks are unrun (the unrun work buried
  as a footnote). Now the report **leads with a coverage ledger**
  (`approved N · executed X · blocked Y · not-run Z`) before any conclusion, and `verify-report.sh`
  **fails a clean `✅ GO` that still has `not executed` rows** — unrun items must be deferred-with-
  reason (→ GO-with-deferrals) or run.
- **Work around an environment limit before accepting `blocked` (step 8).** "No data for this type
  in the window" / "no test DB" is not a stopping point — first try to make it runnable (find a
  historical period with the data, another account/seed, a read-replica) and document the attempt;
  only then is the item `blocked`.

## [2.13.1] - 2026-06-04

### Fixed
- `example-cycle.md` (the worked example) still showed the old bullet checklist with no journey —
  now consistent with 2.13.0: leads with a **User journey (the spine)** row and renders the checks
  as a **table**, so the golden example matches the directive it illustrates.

## [2.13.0] - 2026-06-04

### Changed
- **Checklist is now tabular.** The manual-checklist template's test sections (Smoke, Adversarial,
  Functional, code/security risks, Edge/negative, UX/UI, Performance, Regression) and the
  preconditions block are **tables, one row per check** — columns **# · What to check · How to run
  (exact command/UI steps/API call) · Expected · Risk · Trace** — instead of a prose bullet list
  with `→ steps → expected`. Scannable, and it forces every column (method/expected/risk/trace)
  to be filled per row. Step 6 now instructs building the checklist as tables. At execution the
  report results table extends each row with `Result · Evidence · Actual raw output`.
- **Checklist is organized BY user journey, not by code concern.** Hardens against building a
  checklist structured by *code concern* — "filters", "type mapping", "the window", "the
  optimization" — i.e. testing the code, not the feature.
  Now step 5 makes journey-first the **primary structure**: identify the user(s) — often layered
  (the end-user whose actions create the data **and** the downstream consumer of the output, e.g.
  an analyst) — and build each journey end-to-end (*actor → action → what it produces → run the
  feature → observable outcome*); technical/code-branch checks fold in as **sub-checks of a
  journey**, not standalone items. New **User journeys (the spine)** section leads the checklist
  template; a checklist organized by code concern is called out as the smell that you tested the
  code, not the feature.

## [2.12.0] - 2026-06-04

### Added
- **Adversarial-by-default testing — falsify, don't confirm.** Counters the default of confirming
  the dev's happy path on clean data (branch-by-branch), which lets interaction bugs (e.g. a
  stale-snapshot race) pass every branch in isolation while a blocker sits next to them. Now: a
  new Principle — **test to FALSIFY,
  start from "how does this lose/corrupt the user's money/data?", and run the dangerous conditions
  first** (stale cache, concurrent action in the window, negative/boundary, compensation/retry
  mid-run, out-of-order/duplicate/partial failure). Step 5 **enumerates failure modes first**
  (Exa-sourced), each becoming a high-priority adversarial check ordered before happy-path items.
  New **Adversarial / failure-mode** checklist section (run before Functional). For a money/state
  change this is mandatory — **no adversarial items = a coverage gap and a NO-GO trigger**;
  confirming each branch on clean data is not coverage.
- **Coverage is earned by execution, not reasoning (enumerate every flow).** Hardens against the
  same pattern one level up: declaring the sweep "done" before exhausting scenarios and substituting
  reasoning for a run (e.g. "operation B is just operation A"). New Principle — a coverage/
  equivalence claim is a hypothesis until executed; **no assumed equivalence between flows**
  ("X reduces to Y" must be proven via the same code path, with evidence, or both are run); the
  sweep is "done" only when the enumerated set is exhausted by execution, and finding a blocker
  doesn't end it. Step 5 now **enumerates every flow/entry point** that exercises a shared change;
  the report carries a **Flows / entry points** table (`executed` / `equivalent` / `assumed=GAP`)
  and a flow left on assumption is a NO-GO.
- **Exact repro steps per bug, enforced.** Every found bug must carry **copy-pasteable repro steps
  from a clean start** (the literal commands/requests/clicks, not a mechanism summary). `verify-report.sh`
  now **fails the report** if any bug block lacks a real numbered repro step.
- **Domain-neutral templates.** Removed project-specific examples from the generic skill content —
  the skill is distributed for any project, so step 5 and the report template use neutral
  placeholders ("list the operations THIS project has that reach the changed code"). Domain
  specifics stay in the payments pack and the worked example, where they belong.

## [2.11.0] - 2026-06-04

### Added
- **One hard boundary: never upload a file to the server** — prevents the agent `scp`/`docker cp`'ing
  probe/harness script files onto a staging container on its own initiative. The rule is precise:
  **everything a tester does is allowed**
  (`repl`, `cli`, DB changes, queries, running commands directly on the non-prod env to
  set up state, exercise the feature, and observe) — the **only** prohibition is putting a file
  onto the server/container (`scp`/`docker cp`/deploying a script/harness/probe file). Run the
  logic as a direct command instead. `test-iteration` Principles + step 8 + the evidence-gate
  now state this single rule. (Production stays fully off-limits — separate boundary.)
- **Checklist-item integrity (no proxy, no self-authorized scope cuts)** — prevents the agent
  **deciding on its own not to run an approved checklist item** (e.g. a hard-to-reproduce race),
  substituting a weaker *mechanism* proof and citing a prior cycle's "can't reproduce" as
  justification. Step 8 now states: the approved checklist is
  the contract — **do every item**; an item is `pass` only on evidence for *that* item (a
  mechanism observation does not close a scenario item — no pass-by-proxy); a hard-to-reproduce
  item (race/timing/load) must first be **attempted for real** with a safe setup
  (`Queue::fake()`/`Event::fake()`, deterministic state injection, two processes), and only if
  genuinely impossible is marked **`blocked` + surfaced to the user** — never silently downgraded;
  a prior cycle's "couldn't reproduce" carries forward as the **same open gap**, not permission to
  skip. The step-9 self-audit now requires the quote to prove the item's **own** claim.
- **Regimented actions + per-item execution record, enforced by a script.** Every checklist item
  must now state its **exact method** (the precise command / UI steps / API call) at build time
  (step 6), and at execution (step 8) the agent records a four-part **execution record** per item —
  **`how run`** (the *verbatim* command/steps actually used), `raw output`, `evidence type`, `bucket`.
  New report column **`How run`**. New gate script **`scripts/verify-report.sh`** (run in step 9
  before the verdict) **fails the report closed** if any item's execution record or the
  `Prior-test basis` line is blank or a placeholder — so a hand-waved/rushed report can't reach a
  verdict. It checks structure (nothing left blank), not truthfulness (the self-audit covers that).

## [2.10.0] - 2026-06-04

Hardens against `test-iteration` skipping step 1's prior-test check (prose got jumped 1→2) and
never reading the ticket's comment thread, where the whole re-test signal lives. Turns "gather
the task's test history" from prose into mechanical steps.

### Added
- **`scripts/prior-tests.sh`** + tests — deterministically lists prior test docs for a task
  (filename or content match) at the CLAUDE.md docs path; prints `PRIOR-DOCS` / `NONE` /
  `DOCS-PATH-MISSING`. The prior-test gate now **runs this script** instead of relying on the
  model to remember to look.

### Changed
- **`test-iteration` step 1 prior-test gate** now gathers the task's history from three sources
  as run-the-step actions: (1) `prior-tests.sh` for saved docs, (2) the Jira **discussion**
  (QA findings / dev "fixed/pushed" / reviewer blockers / status), (3) **PR review comments**
  (`gh pr view --comments`, bots skimmed). If any shows prior findings → analyze them first,
  diff tested-commit↔HEAD, re-verify on the current build. Done-when requires the script was run
  and the discussion + PR comments were read.
- **`jira-context`** no longer skips comments wholesale. It now pulls the **signal comments**
  (QA findings, dev fix-confirmations, reviewer decisions, status transitions; bot noise skimmed)
  and sets a **`re-test` flag** when the status is *Awaiting/Returned testing* — pulling comments
  is then mandatory. New `status`, `re-test`, and `discussion` fields in the output block.
- **Terminal `Prior-test basis` gate (fail-closed).** The script lives inside step 1, which a
  rushed run can jump — so the report now carries a **required `Prior-test basis` line**
  (`FRESH` / `RE-TEST of <doc> on <commit>`). A clean ✅ GO is **forbidden while it is empty**, and
  an empty value is a NO-GO trigger. It can't be filled honestly without having run the gate — so
  a skipped step 1 fails closed at verdict time, not silently.

## [2.9.0] - 2026-06-03

### Added
- **Hard "never test against production" boundary.** New principle + step-8 entry criterion in
  `test-iteration`: all testing (data, writes, queries, side effects, observations) runs on
  **staging / non-prod** only; the production database is off-limits — no writes, no reads, no
  test data, ever. If only prod is available, the skill stops and tells the user. The evidence-gate's
  "can't write ≠ can't observe" read-only fallback is clarified to apply to the test env only,
  never prod (removing the earlier "prod DB" example that contradicted this). The principle also
  states: treat every handed-to-you access/credential/URL as non-prod, and a request that appears
  to require editing production is a misread — stop and confirm, never act on it.

## [2.8.0] - 2026-06-03

### Added
- **Prior-test gate** (`test-iteration` step 1): if the task was already tested, don't start
  from a clean slate. Step 1 now reads the **test-docs path stated directly in `CLAUDE.md`**,
  looks there (and on the ticket) for an existing report/checklist for the same key/branch, and
  if one records bugs, begins by analyzing it — prior bugs become priority re-checks (re-verified
  on the *current* build, evidence-gate; "fixed but not re-verified" = open), their components
  become hotspots + a regression pass, and the run continues round-tracking instead of
  re-discovering known issues.

## [2.7.0] - 2026-06-03

Self-consistency pass — the QA plugin now tests its own deterministic scripts and
fixes a packaging drift.

### Fixed
- `marketplace.json` plugin description omitted **`jira-context`** (a skill since 2.1.0)
  and the `jira` tag — marketplace users saw an incomplete skill list. Corrected.

### Added
- **Tests for `verify-deploy.sh`** (`scripts/tests/verify-deploy.test.sh`): match / short-hash
  match / wrong-build mismatch / unreachable / case-insensitive — asserts the exit-code contract
  (0/1/2) via `file://` fixtures.
- **Tests for `branch-diff.sh`** (`scripts/tests/branch-diff.test.sh`): base auto-detection,
  explicit base, unknown-branch error, and `base: UNKNOWN` — against throwaway origin+clone repos.
- **`scripts/tests/run-all.sh`** — runs every `*.test.sh` and exits non-zero if any suite fails.
- `jira-key.test.sh`: added **precedence** (branch key beats commit key) and long-prefix cases —
  the documented "branch name wins" rule was previously unverified. Now 10 cases.

### Changed
- `jira-context`: the acceptance-criteria lookup is now an **ordered, bounded source chain**
  (description → AC custom field → checklist-app → linked story), stopping at the first concrete
  source and recording `ac-source:` in the output — replacing the vague "soft fallback" prose so
  it degrades deterministically and a thin source is visible, not hidden.

## [2.6.0] - 2026-06-03

Pays down integration debt — the composed sub-skills now feed the hardened orchestrator
instead of lagging behind it.

### Changed
- `branch-review`: risk H/M/L is anchored to the shared impact×likelihood rubric (not a gut
  call); a confirmed **defect** now carries an ISTQB **severity** (blocker/major/minor); a
  high-risk correctness/security finding flags its component `hotspot:<area>`. Output format
  extended with `sev:` and `hotspot:` fields.
- `qa-research`: recommendations must now be **evidence-checkable** — each ships an observable
  `check:` signal and an `evidence:` type (`observed-data`/`api-response`/`log`/`static`), so it
  slots straight into the evidence-gate. A recommendation that can only be "confirmed" by reading
  code, or can't be made observable, is dropped rather than shipped as a vibe.
- `test-iteration` step 5 now consumes `branch-review`'s `hotspot:` flags when up-weighting risk,
  alongside the escaped-defects log and memory hotspots.

## [2.5.0] - 2026-06-03

Deepens test design with six sourced additions (cross-checked via Exa against OWASP,
Microsoft Globalization, ISTQB, SBTM, and defect-escape literature).

### Added
- **Domain checklist packs** (`references/domain-packs/`): reusable, sourced check sets for
  payments, auth-sessions, forms, file-upload, search, i18n-l10n — pulled in triage (step 5)
  when the diff touches that domain, folded into the tailored checklist (not run whole). Catch
  domain traps the generic negative set misses (webhook-retry double-charge, session not
  regenerated on login, magic-byte upload bypass, locale fallback, etc.).
- **Severity/Priority rubric** in the report template (ISTQB: severity = technical impact set
  by QA, priority = business urgency set by PO; independent axes) — mirrors the risk rubric.
- **Exploratory charter** (`references/exploratory-charter.md`): SBTM charter → SFDIPOT →
  FEW HICCUPPS → debrief, invoked by the step-1 exploratory gate so an AC-less run is
  structured, not ad-hoc (still capped at `⚠️ GO (exploratory)`).
- **Flaky-result protocol** (`references/flaky-protocol.md`): a new `flaky` bucket (distinct
  from pass/fail) for results that flip on the same build; flip-rate detection, bounded
  re-observation (a retried pass is telemetry, not health), quarantine with owner + ≤30-day
  expiry; a `flaky` critical-path result is a gap that blocks a clean GO.
- **Test-data preconditions** as a first-class checklist block (step 6): derive per-item
  account/flag/seed/fixture needs up front, since most `blocked` results are really unready data.
- **Escaped-defects loop** (lite, step 12 + `references/escaped-defects.md`): when a defect
  escapes a GO build, capture it with a root-cause "why not caught" category, add a regression
  check, and up-weight the component as a hotspot in future triage — the one step that makes the
  process smarter over time. Deliberately lightweight (log + memory note), measured by version.

## [2.4.0] - 2026-06-03

Evidence-gates the verdict — turns "objective verification" from a principle the model
can rationalize past into a gate it cannot pass without a raw observation. Motivated by a
real corner-cut: an AC marked covered on a green mocked unit test, with no observed path
to the actual data.

### Added
- **Evidence type on every result** (step 8): each checklist result is tagged
  `observed-data` / `api-response` / `log` / `code-read` / `unit:mocked` / `unit:integration`,
  with the raw line quoted (not paraphrased). New `Evidence` column in checklist results
  and the AC traceability matrix.
- **Evidence-gate (gate 1)**: a runtime-behaviour AC marked `pass` on `code-read` or
  `unit:mocked` alone is a **GAP**, not a pass — needs ≥1 `observed-data`/`api`/`log`.
- **Mock-aware coverage (gate 4)**: an AC covered only by mocked tests requires ≥1 real-data
  observation of the *same* behaviour (the mock↔reality match verified at least once) — a
  green mock proves the code agrees with itself, not that the feature works on real data.
- **"Can't write" ≠ "can't observe" (gate 2, step 8)**: an environment constraint excuses
  only the blocked write; a read-only observation must be attempted before citing it.
- **Pre-verdict evidence self-audit (gate 3, step 9)**: before any verdict, every AC and
  critical-path pass must quote the raw output that proves it; nothing to quote → GAP, and a
  clean ✅ GO is forbidden while any such row is empty. Scoped to AC + critical-path to stay
  practical. New self-audit table in the report template; new NO-GO trigger.
- `jira-context`: each AC is now tagged `runtime` or `static`, feeding the evidence-gate
  (only `runtime` AC require observed evidence).

### Changed
- New principle: "a ✅ needs a raw observation, not a slogan" — mechanical gates over
  motivational lines, because no instruction binds under "the report looks done" pressure
  unless it's unpassable without proof.
- `example-cycle.md` exercises the gate (AC2 `runtime` closed on the actual localStorage
  line, which is what caught the full-PAN bug a mocked test would miss).
- Grounded the design against sources (Exa): adopted established terms (test-oracle
  problem, structural-vs-behavioural gap, contract testing) and cited the independent
  "required-evidence-field survives deadline pressure" conclusion in step 9.

## [2.3.0] - 2026-06-03

Makes the checklist itself objectively verifiable — closes structural gaps where the
mechanism trusted a single unaudited pass.

### Added
- **Independent completeness review (step 6.5)**: before the user sees it, the checklist
  is audited by a fresh `general-purpose` subagent given only the inputs (diff, AC,
  code→item map, checklist, exit criteria) and asked *what is missing or unfounded* —
  objective verification, not self-grading. Max 2 rounds; self-review fallback if no
  subagent capability exists.
- **Symmetric (two-axis) orphan detection**: a new changed-code↔tests matrix mirrors the
  AC↔tests matrix, so a changed symbol/branch with no covering item is caught the same way
  an uncovered AC is. Triage (step 5) now builds a `changed-code → item` map.
- **Blast-radius analysis** in triage: `git grep` callers of each changed export and derive
  regression items from real call-sites (covers bugs in unchanged-but-dependent code).
- **Risk rubric** (impact × likelihood table) so H/M/L is anchored, not a gut call.

### Changed
- **Mandatory exit-criteria core (locked)**: 5 criteria (0 blocker/major, smoke pass,
  critical-path 100%, every explicit AC covered & passing, security closed/mitigated)
  can no longer be weakened or removed — by QA or by the user; only stricter additions
  are allowed. Report exit table tags each criterion `core`/`proj`.
- **AC-missing hard gate (step 1)**: when AC are absent and can't be supplied, the run is
  flagged `exploratory — requirements unverified` and the verdict is capped at
  `⚠️ GO (exploratory)` — never a clean `✅ GO`.
- **No silent skips of applicable checks (step 8)**: an applicable check that couldn't be
  run is `blocked` (a surfaced gap), never `not executed`; `N/A` requires a recorded
  reason. A blocked critical-path check now blocks a clean GO.
- `example-cycle.md` updated to exercise the new mechanism (6.5 review catching a missing
  logout branch, code-coverage matrix, locked core).

## [2.2.0] - 2026-06-03

### Added
- Checklist template: dedicated **UX/UI checks** (responsive, visual consistency,
  interaction states, user feedback, accessibility) and **Performance checks**
  (load/API time, CLS, behaviour under load) sections, the latter referencing the
  web CWV thresholds.
- `test-iteration` triage (step 5): explicit **code-derived check extraction** —
  enumerate conditional branches, flags/state, code-visible edge cases, persistence
  (localStorage/cookies/cache), and shared-component backward compatibility from the
  diff, treating the implementation as ground truth over the ticket prose.
- **Jira ↔ code reconciliation**: discrepancies between the ticket and the
  implementation are logged as risks and surfaced as an **Open questions for PO /
  discrepancies** block in the test report template.
- **Right-sizing / "Scope & tailoring"**: the checklist template and `test-iteration`
  step 6 now match test depth to the change — sections are selected by what the diff
  touches; skipped ones are marked `N/A — <reason>` instead of being silently dropped
  (Smoke and Regression are never skipped).
- **How-to-measure pointers** for the UX/UI and Performance checks (Lighthouse /
  PageSpeed, axe, DevTools Network, keyboard pass, `prefers-reduced-motion` emulation).
- **Re-test round tracking**: `Round` column in checklist results and
  `Found in round` / `Fix verified in round` + `Build verified against` on each defect,
  so fixes are re-tested against a new build, not the one that failed.
- **`test-iteration` step 11 (optional)**: post a concise QA summary back to the Jira
  ticket via the Atlassian MCP — outward-facing write, gated on explicit user confirmation.
- `references/example-cycle.md` — a compact, end-to-end worked example (tailored scope,
  code-derived checks, AC traceability, NO-GO → re-test → GO) showing the shape of good output.

## [2.1.0] - 2026-06-02

### Added
- `jira-context` skill: resolves the Jira key for a branch (deterministic
  `scripts/jira-key.sh`: branch → PR → commits) and pulls the ticket's summary,
  acceptance criteria, and bug repro into a structured context block. Atlassian
  MCP optional; degrades to manual paste.
- `scripts/jira-key.sh` + `scripts/tests/jira-key.test.sh` — read-only issue-key
  resolver (official format `[A-Z][A-Z]+-[0-9]+`) with self-contained tests.
- Traceability matrix (AC ↔ tests ↔ defects) with two-way orphan detection in the
  test report template.

### Changed
- `test-iteration` now derives what to test from Jira acceptance criteria (the diff
  is secondary), requires measurable/binary exit criteria with validation commands,
  and derives the verdict fail-closed against them (steps 1, 5, 6, 9).

## [2.0.0] - 2026-06-01

### Added
- `scripts/branch-diff.sh` — deterministic fetch/checkout/base-resolution/diff,
  read-only against history. Removes model guessing of git state and the base branch.
- `scripts/verify-deploy.sh` — confirms THIS branch's commit is the build deployed
  to staging before testing, so a verdict can't be based on the wrong build.
- `branch-review` skill — standalone code + security review of a branch's diff,
  deduplicated and risk-ranked.
- `qa-research` skill — standalone, sourced best-practices research turned into
  concrete checks.

### Changed
- **Decomposed the mega-skill.** `test-iteration` is now a thin orchestrator that
  composes `branch-review` and `qa-research` instead of inlining everything
  (single-responsibility; the sub-skills are reusable on their own).
- **Truly tool-agnostic.** Every fallback chain now ends on something available on
  a bare Claude Code install: review → `general-purpose` subagent; research →
  `WebSearch`. No more "double bottom" where the last fallback might also be absent.
- Deterministic git/deploy steps moved from model instructions to `scripts/`, with
  an inline git fallback when `${CLAUDE_PLUGIN_ROOT}` is unavailable (manual install).

### Migration
- Invoke as `/qa-skill:test-iteration`, `/qa-skill:branch-review`,
  `/qa-skill:qa-research`. `test-iteration` behaviour is unchanged for users;
  internals are now delegated. Major bump for the structural change.

## [1.1.0] - 2026-06-01

### Changed
- Workflow logic fixes for verdict reliability:
  - Exit criteria are now fixed and approved BEFORE testing (step 7-8) instead of
    being invented at report time — the verdict is measured against fixed thresholds.
  - Approval step now covers both the checklist AND the exit criteria.
  - Step 9 verifies entry criteria first — most importantly that **this branch's
    commit is actually deployed to staging** — before any testing, so the verdict
    can't be based on the wrong build.
  - Base branch is taken from `CLAUDE.md`, or confirmed with the user — no guessing.
  - Added an explicit triage step (dedup + risk-rank) between review/research and
    the checklist; research recommendations must become concrete checks.
  - Added a re-test loop (step 11): after NO-GO/deferrals, re-run only failed/blocked
    items plus regression and re-derive the verdict — true iteration.
  - Verdict is consistently three-state (GO / GO-with-deferrals / NO-GO) throughout.
- Report template: tool-agnostic section headings (no hardcoded "ruflo"/"Exa").
- Checklist template: added an exit-criteria block (approved with the checklist).

## [1.0.0] - 2026-06-01

### Added
- `test-iteration` skill: takes a git branch through a full pre-merge QA cycle
  (project context, code & security review, best-practices research, manual test
  checklist, staging run, and a go/no-go report).
- Reference templates: `manual-checklist-template.md` (entry criteria, risk-based
  scoring, traceability, negative checklist) and `test-report-template.md`
  (GO / GO-with-deferrals / NO-GO verdict, exit criteria, pass/fail/blocked/
  not-executed buckets, expanded bug report, sign-off).
- Plugin packaging: `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`
  for installation via `/plugin marketplace add` + `/plugin install`.
- Tool-dependency fallbacks (ruflo → built-in `/code-review` / `/security-review`,
  Exa → `context7` / `WebSearch`), so the skill degrades gracefully instead of failing.
- `LICENSE` (MIT), `.gitignore`, and this changelog.

### Notes
- All content is in English for public distribution.
- `install.sh` (bash symlink) is kept as a fallback for manual install on macOS/Linux;
  the plugin/marketplace flow is the recommended, cross-platform path.
