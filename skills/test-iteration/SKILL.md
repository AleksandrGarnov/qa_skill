---
name: test-iteration
description: Runs a git branch through a full pre-merge QA cycle for Claude Code — project + Jira acceptance-criteria context, branch review, best-practices research, a right-sized test checklist, execution on the staging environment, and an evidence-gated go/no-go verdict (a clean GO is blocked until every acceptance criterion is backed by a raw observation, not a code-read or a mocked test). Use when a feature or branch needs real QA before merging.
argument-hint: "[git-branch]"
---

# Feature Test Iteration

**Branch:** `$ARGUMENTS` (if not provided, stop and ask for the branch).

Runs a git branch through a full pre-merge QA cycle and produces a fail-closed verdict (✅ GO / ⚠️ GO with deferrals / ⛔ NO-GO). Delegates review to `branch-review` and research to `qa-research`; uses bundled scripts for the deterministic git/deploy/report steps.

## Principles

- **Do everything yourself, API-first — through the product's real interfaces.** git, review, research, then **trigger the user's action through the real entry point**, preferring the API (script the call as a client); drive the UI by hand when the flow is UI-only. `tinker`/`repl`/`cli`/DB on **non-prod** are **supporting** — preconditions and reading state — **never the flow-driver**: reach for them only when the behaviour genuinely can't be triggered or *verified* via the API, and never to reconstruct the *whole flow* (an internal-service call is a proxy for the user, and can't close a user-facing AC). If an API call can prove the claim, a REPL read doesn't substitute for it. **One hard boundary: never put a *file* on the server** (no `scp`/`docker cp`/deployed script/probe, not even read-only) — run the logic as a direct command. Turn to the user only at step 7, for a visual check, or for access you lack.
- **Never test against production.** All testing runs on staging/non-prod; the production DB is off-limits — no writes, no reads, no test data, ever. Treat every access/credential/URL you're handed as non-prod; a request that seems to require editing prod is a misread — stop and confirm. A behaviour only visible in prod is a `blocked` gap, not a reason to touch prod.
- **Test to FALSIFY, not confirm — dangerous conditions and user journeys first.** Find how the change *loses/corrupts* data; don't re-confirm the dev's happy path (their green unit tests already do, on clean data). Lead with "how does this lose/corrupt the user's data?" and the dangerous conditions (stale cache, a concurrent action *in the window* between two steps, negative/boundary, compensation/retry mid-run, out-of-order/duplicate/partial-failure) **before** clean inputs. Organize checks by **user journey**, not by code concern — a checklist of "filters / type-mapping / clauses" tested the code, not the feature.
- **Know the expected answer independently — don't let the code be its own oracle.** An observation only tests something if you know what the result *should* be from a source that isn't the implementation. For any **computed / money / aggregated / state-transition** AC, derive the expected value **independently and before the run** (hand calc, spec formula, known invariant, reference impl, trusted historical) and record its source; the pass is "observation == independently-derived expected", not "a number came back and looks plausible". When the answer can't be pre-computed (search relevance, ML, complex transforms, non-deterministic order), assert a **metamorphic invariant** instead of an exact value. Full method + examples: [test-oracle.md](references/test-oracle.md).
- **Coverage is what you executed and observed — nothing else counts.** A pass needs a **quoted raw observation of that item's own claim** (`observed-data`/`api`/`log`). *Not* a pass: reasoning ("surely it self-heals", "B is just A"); a **proxy** (a mechanism observation under a scenario item); a green **mock** (`unit:mocked` proves the code agrees with itself, not that it works on real data); or validating only against **existing/historical** data — that tests the *consuming* half, not whether the user's action *produces* the right state across every store (the producing leg is `blocked` until run live). No assumed equivalence between flows; the sweep is "done" only when every enumerated flow is exhausted by execution. Unrun work is `blocked`/`not executed` and **surfaced** — never hidden, substituted, or self-downgraded. **Surfacing is not a resolution:** an approved check is *executed*, or it's `blocked` only after a documented real attempt — you never offer the user a "leave it uncovered, you decide" choice; if you lack access, ask for it to *finish* the check, not for permission to ship the gap. A `blocked`/unrun **critical-path or AC** item is a ⛔ NO-GO — never downgraded to a deferral (deferral is for a *defect* with mitigation + owner + fix-date, never a way to skip a check).
- **Gates over judgment.** The checklist is independently reviewed before anyone trusts it (6.5); exit criteria — including a non-overridable mandatory core — are locked before testing (6–7); the verdict is fail-closed and a **script** (`verify-report.sh`) blocks it if the report is incomplete. A discipline you can't pass without proof survives "the report looks done" pressure; a paragraph you're merely asked to honor does not.
- **The verifier is the weakest link — verify it too.** The independent subagents this skill leans on (6.5 review, 8.5 re-execution, 4.5 adversarial) are LLMs prone to silent omission, non-determinism, and over-correction. So **gate the verifier on a known-correct probe** (it must catch a planted gap / reproduce a known outcome before its verdict counts), **surface disagreement instead of averaging it**, and **filter claimed breaks through an actual red test run**. A second model is corroboration, not proof — only a runnable black-box check is proof. Why + how: [verifier-reliability.md](references/verifier-reliability.md).
- **Read the task's discussion before analysing it.** Before forming bug theories or designing checks, read the **Jira comments + PR review comments** — the dev's rationale and reviewers' findings often confirm/refute a theory before a run is spent. Applies to ad-hoc work too, not only step 1.
- **Don't read secrets.** Never read `.env`/secret files; if a step needs a variable, ask the user.

## Steps

> **Open the reference before the step that needs it — a link you didn't `Read` is guidance you didn't get.** These steps deliberately keep the *method* in `references/*.md` and only the imperative here; that only works if you actually load them. `Read` the file at the **start** of the relevant step, not by name alone:
> - **[test-oracle.md](references/test-oracle.md)** → before step 5's oracle definition and step 8's pass/fail call.
> - **[test-design-techniques.md](references/test-design-techniques.md)** → before step 5's input & combination design.
> - **[verifier-reliability.md](references/verifier-reliability.md)** → before spawning the 4.5 / 6.5 / 8.5 subagents.
> - **[test-data-management.md](references/test-data-management.md)** → before writing step 6 preconditions/teardown and provisioning in step 8.
> - the matching **[domain pack](references/domain-packs/)** → when the diff touches its domain (step 5).
> - the templates ([manual-checklist](references/manual-checklist-template.md) · [checklist-manifest](references/checklist-manifest-template.md) · [test-report](references/test-report-template.md)) → when you build each artifact.

### 1. Context + prior-test history
Read `CLAUDE.md`: stack, **base branch**, **staging target** (+ any version/commit endpoint), the **test-docs path**, and how testing is done here (adapt if it differs — e.g. CI-only). Invoke **`jira-context`** for the ticket's summary, AC (tagged explicit/inferred and runtime/static), repro, status, and **discussion** comments. The AC — not the diff — are the primary source of what to verify.

**AC-missing gate:** if AC are missing and the user can't supply them, flag the run `exploratory — requirements unverified`, cap the verdict at `⚠️ GO (exploratory)` (never a clean GO), and run a structured exploratory pass ([exploratory-charter.md](references/exploratory-charter.md)).

**Prior-test gate — run it, don't recall it.** Gather the task's history from three sources:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/prior-tests.sh" <test-docs-path> <KEY> [branch]   # PRIOR-DOCS / NONE / DOCS-PATH-MISSING
```
plus the **Jira discussion** and **PR comments** (`gh pr view <PR> --comments`, skim bots). A status like *Awaiting / Returned testing* = a re-test: prior findings become **priority re-checks** (re-verified **live** on the current build; "fixed but not re-verified" = open), their components become hotspots, and you diff tested-commit↔HEAD. Continue that history (step 10), don't restart.
**Confidence check (presence advice — never auto-acts).** Read this task class's track record to inform how much human presence step 7 needs:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/confidence.sh" suggest <test-docs-path>/qa-confidence.md "<changed-component>"
```
`READY-FOR-PRESENCE-REDUCTION` = a long streak of clean GOs that never escaped → **offer** the user a lower-presence/auto-approve run at step 7 (the merge-gate still enforces the gates). `KEEP-PRESENCE` = manual approval as usual. This only *surfaces an option*; lowering presence is always the user's explicit opt-in.
**Done when:** you know stack/base/staging, the AC/repro (or that they're missing), whether this is fresh or a re-test — `prior-tests.sh` run, discussion + PR comments read — and you've read the component's confidence streak.

### 2. Branch + diff (deterministic)
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/branch-diff.sh" "$ARGUMENTS" [base]
```
Fallback to inline git if no plugin root. Use the base from `CLAUDE.md`; if `base: UNKNOWN` and CLAUDE.md is silent, **ask — don't guess**. Note the **head commit** (needed at step 8).
**Done when:** head commit, confirmed base, changed-files list.

### 3-4. Review + research (in parallel)
Invoke **`branch-review`** (deduplicated, risk-ranked code + security findings, each defect with an ISTQB severity and high-risk areas tagged `hotspot:`) and **`qa-research`** (sourced, **evidence-checkable** best-practice checks). Both degrade gracefully on a bare install.

### 4.5. Adversarial break-it pass (subagent — sole goal: prove the service breaks)
Spawn a **fresh `general-purpose` subagent** whose single objective is to **break the running service on staging** — not to confirm it works. Give it only the diff, the AC, the changed-files list, and the staging target (**not** your happy-path expectations, so it stays adversarial). Its brief: attack the whole service the change touches — data loss/corruption, concurrent action *in the window* between two steps, stale-cache-as-truth, negative/boundary/zero, compensation/retry mid-run, out-of-order/duplicate/partial-failure, auth/tenant-isolation bypass, resource exhaustion — and for **every attack that lands, reproduce it as a runnable black-box test** against staging (green/red by code, not judgement), on a **freshly-created subject** (new user/data per attack), never production. **API-first: any attack reachable through the API is scripted and observed through the API; Tinker/REPL or the browser/UI only when the break genuinely can't be exercised or verified via the API** — and even then it drives the real entry point, never a file on the server. **Fix nothing** — a landed attack is a finding to *record*, not to repair (repair is the dev's job on the next build). It returns, per attack: scenario · exact repro from a clean start · the reproducing test · observed break — plus the attacks it *couldn't* land.

**Every returned attack scenario feeds the checklist** (folded into step 5.1's failure-modes and carried into the manifest's `### Adversarial` block, step 6): a **landed** break enters as a high-priority FAIL-candidate item **with its reproducing test attached**; a **not-landed** attack enters as a hardening/regression check so it can't silently start working later. None is dropped or self-triaged away.
**Filter over-reporting through execution** ([verifier-reliability.md](references/verifier-reliability.md)): an adversarial prompt over-reports — a claimed break the subagent **can't reproduce with a test that actually goes red is a hallucination; discard it**, don't file it. Only a red reproducing run makes a break a finding.
**Done when:** the adversarial subagent has run; every landed attack has a **reproducing test that actually went red** and is recorded (unfixed); unreproducible claims were discarded; and all scenarios (landed + not-landed) are queued for the checklist.

### 5. Triage → drive the checklist
Build the candidate checks in this order, then consolidate:
1. **Failure modes first (adversarial).** "How does this lose/corrupt data?" → stale snapshot used as truth, concurrent-action-in-the-window, negative/boundary/zero, compensation/retry mid-run, out-of-order/duplicate/partial-failure, the "optimization that swapped truth for a stale value" trap. Each → a high-priority check, **before** happy-path items. For a money/state change this list is **mandatory** (none = coverage gap = NO-GO). Source it from the **step-4.5 adversarial pass** (every landed break is a mandatory item, carrying its reproducing test), the **discussion**, **Exa** (`qa-research`), and the code — not memory.
2. **Every flow / entry point.** Read the codebase for *all* operations that reach the changed code (don't assume a fixed set). Each is covered by **running it live**, or proven to share the exact code path of one already run (with evidence) — never assumed. Carry the flow list into the report.
3. **User journeys (the spine).** Name the user(s) — often layered (the actor who creates the data **and** the downstream consumer of the output). Each journey end-to-end: *actor → action → what it produces across every store → run the feature → observable outcome*. Technical/code-branch checks fold in **under** the journey they validate. A **live** journey (you perform the action) ≠ validating against existing data (covers only the consuming half). Perform it on a **freshly-created subject** (register a new user / create new data per scenario), **not a reused fixture** — an old test account carries accumulated state and hidden coupling, and skips the real creation path; a fresh one isolates the action's effect and exercises produce-then-consume cleanly.
4. **Code-derived checks.** One per changed branch (`if/else`/switch incl. default), flag/state, code-visible edge case (falsy, race, async ordering), and persistence path (save/restore/clear); shared-component call-sites.
5. **Input & combination design (don't drown in the parameter space).** For each input, pick values by **equivalence partitioning** (one representative per class + each invalid class) and **boundary value analysis** (min−1/min/max/max+1) — not arbitrary values, not every value. When the change has **≥3 interacting parameters / config axes / flags**, don't test "a few combos" or attempt the full product — generate a **pairwise (t=2)** set over the representatives (t=3 for a known-risky trio like `auth-state × role × feature-flag`), exclude impossible combinations with constraints, and **record the coverage claim** ("pairwise over {…}, N cases, all 2-way pairs; excluded impossible pairs"). See [test-design-techniques.md](references/test-design-techniques.md). A silent "tested the main combinations" is a coverage gap.
6. **Domain packs + hotspots + blast radius + learned checks.** Pull the matching [domain pack](references/domain-packs/); up-weight hotspots (escaped-defects log / memory / `branch-review` `hotspot:` tags); for each changed export, `git grep` its callers → regression checks. **Pull the project's learned checks** — distilled from past real outcomes — for the changed components, and fold every matching one in (this is how the system gets smarter run-over-run, not a blank slate each time):
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" match <test-docs-path>/learned-checks.md <changed-component-keywords…>
```
A matching learned check that you *don't* fold in is a coverage gap the step-6.5 review flags.
7. **Define the oracle per check — expected result, sourced independently.** For every item — above all a **computed / money / aggregated / state-transition** one — write down the *expected* value **and where it came from**, and make that source **anything but the implementation under test**: a hand calc, the spec's formula, a known invariant, a reference implementation, a trusted historical figure. An item whose only "expected" is "whatever the code returns" tests nothing — it's a mock one level up. When the right answer genuinely can't be pre-computed (search relevance, ML output, a complex transform, non-deterministic order), attach a **metamorphic / property invariant** instead of an exact value (sum-of-parts == whole, idempotent replay, reverse-restores-input, reorder-changes-output-predictably). See [test-oracle.md](references/test-oracle.md). Carry the expected + its source into the manifest so approval and step-9 can check the observation *against it*, not against plausibility.
8. **Reconcile + map.** Anchor each AC to ≥1 check (an AC with none is a gap); log Jira↔code discrepancies as PO questions; keep a `changed-code → item` map for step 9's code-orphan check.
**Done when:** one risk-ranked list — AC-anchored, journey-organized, with failure-modes/flows/code/packs folded in, each check carrying an **independently-sourced expected (or a metamorphic invariant)**, blast-radius callers as regression items, and the `changed-code → item` map built.

### 6. Checklist + exit criteria
Build it as **tables** ([manual-checklist-template.md](references/manual-checklist-template.md)) — one row per check, columns **# · what to check · how to run (exact command/UI steps/API call) · expected · risk · trace (AC)**. A vague item ("check it reconciles") is skippable/proxyable; a prescribed one ("run `<cmd>`, expect `<X>`, read `<field>` == `<Y>`") can only be done or `blocked`. **Right-size** (template's Scope & tailoring): skip a section only as a recorded `N/A — <reason>`; Smoke + Regression are never skipped. Derive **per-item test-data preconditions *and teardown*** up front ([test-data-management.md](references/test-data-management.md)) — most `blocked` results are unready data; provision a **fresh, isolated subject per scenario** (synthetic/newly-created, never a raw production copy — masked non-prod subset only if production-shape is needed), and plan cleanup in the same row so created data doesn't rot staging into false positives for the next run.

Write **exit criteria** — measurable/binary, with a validation command where machine-checkable. **Mandatory core (non-overridable — neither you nor the user weakens it):** `0 open blocker/major` · `smoke all pass` · `critical-path coverage 100%` · `every explicit AC covered & passing — a runtime/user-facing AC closed on a live observation (observed-data/api/log), never on code-read/unit:mocked or repl alone` · `security findings closed/mitigated`. Add stricter project lines on top. Green unit/repl/code checks are *supporting* — they never by themselves grant GO for a user-facing change.
Also emit the checklist as a **frozen manifest** ([checklist-manifest-template.md](references/checklist-manifest-template.md)). It opens with a **`## Context` block you fill by running the tools** (the system's non-skippable input guidelines), then **journeys first** (named actor → action → observable outcome), then **items each carrying a stable ID and a journey ref**:
- **`### Discussion`** — paste the *fetched* `gh pr view <PR> --comments` + the Jira ticket discussion (guideline 1: read the comments — real content, not "I read them").
- **`### Prior tests`** — the `prior-tests.sh` result, `FRESH` or `RE-TEST of <doc>@<commit>`; on RE-TEST the items are built on the old runs (guideline 4).
- **`### Research (Exa)`** — the Exa findings turned into checks (guideline 2: always research; the journey-rooting enforces "user-flow first, code-branches under it").
- **`### Adversarial`** — the step-4.5 break-it pass: each attack scenario dispositioned into an item (landed → FAIL-candidate item + reproducing test; not-landed → hardening/regression check), so "prove-it-breaks" is a non-skippable input, not an optional afterthought.

Then gate the manifest **before showing it for approval**:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-context.sh"  <manifest.md>                # must print CONTEXT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-coverage.sh" <manifest.md> <report.md>    # journey-rooting (report may be a stub here)
```
`verify-context.sh` fails closed if the Discussion / Prior-tests / Research / Adversarial blocks are empty — so the front-loaded steps (read comments, prior runs, Exa, the break-it pass) **cannot be skipped**; the merge-gate hook re-checks it at merge.
**Done when:** a journey-rooted manifest with a filled `## Context` (CONTEXT-OK) + items (ID + journey ref) + exit criteria including the mandatory core.

### 6.5. Independent completeness review
Have a **fresh `general-purpose` subagent** — given only the inputs (diff, AC, the `changed-code → item` map, the matching **learned checks** (step 5), the checklist, the exit criteria), **not** your reasoning — report **what's missing or unfounded**: an uncovered AC, an uncovered changed symbol, an item with no AC/code basis, **a `qa-research` finding that became neither a checklist item nor a recorded reject**, **a matching learned check that wasn't folded into the checklist**, an `N/A` whose reason doesn't hold, **a computed/money/state item whose `Expected source` is not *genuinely* independent of the implementation** — this is the review's job, not the gate's: `verify-coverage` only trips blatant phrasings (`= system output`), so the reviewer must judge whether each source is *real and independent* (a `spec §4` that cites no actual spec, a "hand calc" with no arithmetic shown, or an "invariant" that just restates the code are all failures) — **and has no metamorphic invariant standing in for it**, an exit criterion weaker than the core. Fold the real findings back; re-run once if material; cap at 2 rounds. No subagent → do a cold self-review in a separate, explicit pass and say so.
**Probe the reviewer** (silent omission is hard to catch — [verifier-reliability.md](references/verifier-reliability.md)): hand it a checklist with **one planted, known gap** (an uncovered AC / a changed symbol with no item). If the review doesn't surface it, it isn't sensitive enough to trust — strengthen the prompt and re-run before believing "nothing missing". Record the probe was caught.
**Done when:** the reviewer caught the planted probe; the checklist passed an independent (or explicit self-) completeness review; gaps closed or recorded.

### 7. Approval — PAUSE (user required)
Show the user the **manifest** (journeys + items) + exit criteria (post-6.5) and **wait for "ok" or edits before testing**. They approve scope and thresholds but **cannot weaken the mandatory core**. Don't proceed without explicit confirmation. On "ok" the manifest is **frozen** — it's the contract; the step-9 report must account for every item ID in it.

On freeze, **create the canonical QA bundle + record the run-state** so the merge-gate hook can enforce the gates without depending on you remembering to run them:
```bash
bundle="$("${CLAUDE_PLUGIN_ROOT}/scripts/qa-bundle.sh" init "<test-docs-path>" "<task-id-or-branch>" "<run-id>")"
manifest_md="$(printf '%s\n' "$bundle" | sed -n 's/^MANIFEST-MD: //p')"
manifest_json="$(printf '%s\n' "$bundle" | sed -n 's/^MANIFEST-JSON: //p')"
report_md="$(printf '%s\n' "$bundle" | sed -n 's/^REPORT-MD: //p')"
report_json="$(printf '%s\n' "$bundle" | sed -n 's/^REPORT-JSON: //p')"
artifacts_json="$(printf '%s\n' "$bundle" | sed -n 's/^ARTIFACTS-JSON: //p')"
bundle_dir="$(printf '%s\n' "$bundle" | sed -n 's/^BUNDLE-DIR: //p')"

mkdir -p "${CLAUDE_PROJECT_DIR:-.}/.claude"
printf '{"schemaVersion":1,"runId":"%s","status":"approved","branch":"%s","bundleDir":"%s","manifest":"%s","manifestMd":"%s","manifestJson":"%s","report":"%s","reportMd":"%s","reportJson":"%s","artifactsIndexJson":"%s","currentRound":"R1","gates":{"context":"pending","coverage":"pending","report":"pending","evidence":"pending"}}\n' \
  "<run-id>" "$ARGUMENTS" "$bundle_dir" "$manifest_md" "$manifest_md" "$manifest_json" "$report_md" "$report_md" "$report_json" "$artifacts_json" \
  > "${CLAUDE_PROJECT_DIR:-.}/.claude/qa-run.json"
```
Write the frozen manifest to **both** `manifest.md` and the adjacent `manifest.json` sidecar. The markdown stays the approval/report surface for humans; the JSON sidecar is the canonical machine-readable contract for automation. Keep the item IDs and journey refs identical across both.

The bundled **PreToolUse hook** (`hooks/hooks.json` → `finalize-gate.sh`) reads this file and **blocks a `git merge`/`git push`/`gh pr merge` with exit 2** unless `CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK` all pass — so a skipped checklist item or ungathered context physically cannot reach a merge, regardless of what the agent does. If `manifestJson` / `reportJson` are declared in the run-state, they must exist on disk too. (If this project merges via PR/CI rather than locally, point the hook's matcher at that action instead — see the hook comment.)

### 8. Run on staging — a full execution record per item
**Entry criteria (don't start until they hold):** the target is non-prod; staging is reachable; **THIS branch's commit is deployed** —
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-deploy.sh" <version-url> <head-commit-from-step-2>
```
(or confirm the build another way — a wrong build invalidates the verdict); test data/accounts/flags ready.

Run each item by hand — **trigger via the real entry point** (UI / API as a client); `repl`/`cli`/DB queries are for **setup and reading state**, not for driving the flow. **Never upload a file to the server.** For **every item** record a 4-part **execution record** in the markdown report **and** in `report.json` using the same item ID:
- **how run** — the *verbatim* command/steps actually used (not "checked the balance");
- **raw output** — the actual response/log/value, quoted;
- **evidence type** — `observed-data`/`api-response`/`log`/`code-read`/`unit:mocked`/`unit:integration`;
- **bucket** — pass / fail / blocked / flaky / N/A (reason) / not executed.

Structured sidecar requirement (`report.json`): each result row must carry at least `itemId`, `result`, `evidenceType`, `round`, and either a non-empty `rawQuote` or an `artifactRef` into the bundle. This is what the structured evidence gate validates.

Rules:
- Empty "how run" = `blocked`/`not executed`, never pass. A "how run" that doesn't match the prescribed action is a **proxy** — the item is not covered.
- **No silent skips or self-scope-cuts.** Every approved item is the contract — run it, or mark `blocked` (with reason) and surface it; you don't get to decide an item is "unnecessary". A `pass` needs evidence for *that item's own claim* (a mechanism observation ≠ a scenario pass).
- **Hard-to-reproduce / env-limited ≠ skip.** First try to make it runnable — a safe setup (`Queue::fake()`/`Event::fake()`, deterministic state injection, two processes / two real users), a historical period that has the data, a different account/read-replica. If the obvious entry point is missing (e.g. no debug endpoint), try the **other real channels** (admin UI, API as a client, a second account) and, if still stuck, **ask the user for the access to finish it** — `blocked` is the last resort, only after a documented attempt, and "couldn't reproduce the real flow" never becomes a `pass` via `repl` (it stays `blocked`). ("Can't write" ≠ "can't read": attempt the read-only observation first — on non-prod only.)
- **`flaky`** (flips on the same build) is a gap, not pass/fail — re-observe 1–2×; a retried pass is telemetry, not health. Flaky on the critical path blocks a clean GO.
- **Check against the oracle, not plausibility.** The bucket is `pass` only if the raw output **equals the item's independently-derived expected** (step-5 oracle) — or, for an oracle-hard item, its **metamorphic invariant held**. "A value came back and looks reasonable" is not a pass; a computed/money/state item whose expected was never derived independently is a GAP, not a `pass`.
- **Provision fresh, isolated; tear down after** ([test-data-management.md](references/test-data-management.md)). Create the subject/data for each scenario through the real entry point (synthetic/new, never a raw production copy), so runs can't pollute each other; after the check, **remove what you created** (API delete / rollback / snapshot reset) or record why it's safe to leave — created data left behind becomes the next run's false positive.
**Done when:** every item has a full execution record checked against its independent expected/invariant; nothing was silently dropped, proxied, or self-downgraded; and no cited constraint went without a real attempt first.

### 8.5. Independent re-execution of the critical path (unbiased corroboration)
For **critical-path / money-state items only**, spawn a **fresh `general-purpose` subagent** — given only the frozen manifest's commands for those items + the staging target, **not** your run's results, evidence, or reasoning — and have it **re-execute** them and return the **raw outputs**. Then cross-check: each critical `pass` must be **corroborated by the independent run's raw output** (the two observations agree). A mismatch, or any critical `pass` the independent run **can't reproduce**, is a **GAP** that blocks a clean GO — investigate the discrepancy first (the gap between "verification says PASS" and "re-run says otherwise" is the most valuable signal, never ignore it). Record it in the report's *Independent re-execution* table **and** persist it in `report.json` under the same item ID, with either `status=agree` / `status=GAP` or `acceptanceTestEquivalent=true` where a real black-box acceptance test supersedes the second run. Scope to the critical path so it stays practical.

**Probe-gate the blind run, don't average disagreement** ([verifier-reliability.md](references/verifier-reliability.md)): (1) include **one control with a known outcome** among the re-run commands — if the blind run can't reproduce it, its harness is untrustworthy and its `agree` doesn't count (fix + re-run); (2) on a borderline **disagreement** with the executor, don't pick one or average — take one more independent sample, go with the majority, and **record the disagreement rate**. Persist `probe:` and any `disagreement` in `report.json` so "the verifier was itself verified" is visible.
> This is **unbiased verification applied to execution, not review** (the executor doesn't self-certify; a blind second context does). It is **strong corroboration, not a hard guarantee** — both are LLMs and can share a blind spot. The only hard guarantee is a **runnable black-box acceptance test** for the flow (executes against staging, green/red by code, not judgement); where such a test exists, it supersedes this step for that flow.
**Done when:** the blind re-run reproduced its known-outcome probe; every critical-path `pass` is corroborated by it (outputs agree), or the discrepancy is surfaced as a GAP with its disagreement recorded.

### 9. Report + fail-closed verdict
Write the report ([test-report-template.md](references/test-report-template.md)). It **leads with a coverage ledger** (`approved N · executed X · blocked Y · not-run Z`) — never a "clean/objective" narrative over an incomplete run. Every bug carries **exact, copy-pasteable repro steps from a clean start** (literal commands, not a mechanism summary).

Run **two-axis orphan detection**: **AC ↔ tests** and **changed-code ↔ tests** (from the step-5 map) — surface any uncovered AC, uncovered changed symbol, or unfounded/drift item. **Evidence-gate the AC matrix:** a runtime-behaviour AC on `code-read`/`unit:mocked` evidence alone is a **GAP** (needs ≥1 `observed-data`/`api`/`log`); an AC covered only by mocked tests needs ≥1 real-data corroboration of the same behaviour (the mock↔reality match — a contract test). Encode the same AC matrix in `report.json` with stable `acId` + `coveringItemIds`, because `verify-evidence.sh` reads the sidecar rather than prose. Fill the **Open questions for PO** block from step-5 Jira↔code discrepancies.

**Pre-verdict self-audit:** for every AC-pass and critical-path item, quote the raw output that proves **its own claim** **and name the independently-derived expected it was checked against** (or the metamorphic invariant that held) — nothing to quote, or nothing independent to check it against, ⇒ GAP. Then run the **mechanical gates**:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-context.sh"  <manifest.md>               # must print CONTEXT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-report.sh"   <report.md>                 # must print REPORT-OK
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-coverage.sh" <manifest.md> <report.md>   # must print COVERAGE-OK
```
`verify-report.sh` fails on: an incomplete execution record, an unfilled `Prior-test basis` line, a bug with no exact repro, or a **clean ✅ GO that still has a `not executed` row**. `verify-coverage.sh` fails (set-diff against the frozen manifest) on: **any approved item with no result row OR marked `not executed`** (a skip — every approved item is non-skippable, guideline 3), **any item not rooted in a defined journey** (guideline 2), or **any item whose `Expected source` is empty or names the implementation itself** (the oracle rule — the code can't be its own oracle) — making "the report quietly dropped/skipped checks" and "the checklist was built from code, not journeys" mechanically impossible. When `manifest.json` + `report.json` + `artifacts.json` exist, also run `verify-evidence.sh` so runtime AC, raw quotes, corroboration, and artifact refs are enforced structurally rather than only by prose.

Write the report into **both** `report.md` and the adjacent `report.json` sidecar, then update the active run-state (`.claude/qa-run.json`, step 7) so the **merge-gate hook** enforces these three gates at the irreversible action. The markdown is the human-readable audit artifact; the JSON sidecar carries the same item IDs / AC matrix / verdict data in machine-readable form for later gates. You run the shell gates here for early feedback, **but the binding enforcement is the hook, not this step** — even if this step were skipped, the hook blocks the merge until all three are green.

**Verdict — fail-closed:** GO only if `CONTEXT-OK` **and** `REPORT-OK` **and** `COVERAGE-OK` **and** every critical-path `pass` is corroborated by the step-8.5 independent re-run (or guaranteed by a green acceptance test) **and** every exit criterion (core + project) is met against the fixed thresholds, not a fresh judgement at report time. Any open blocker/major, critical-path coverage <100%, a blocked/unrun critical item, an AC passing on sub-gate evidence, or a red regression → not a clean GO. `exploratory` caps at ⚠️ GO (exploratory); "GO with deferrals" only with mitigation + owner + fix-date per deferred item.

**On a clean ✅ GO**, record it to the confidence ledger — one row per changed component — so the trust streak that step 1 reads grows run-over-run (a clean GO is the positive signal; an escape later resets it at step 12):
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/confidence.sh" record <test-docs-path>/qa-confidence.md "<component>" go "<adw/run id>"
```
Record GO **only** for a clean GO — never for `GO with deferrals`, `exploratory`, or NO-GO (those aren't the reliability signal).
**Done when:** ledger + both orphan axes + Evidence column + self-audit + `CONTEXT-OK` + `REPORT-OK` + `COVERAGE-OK`; verdict justified against the fixed criteria; a clean GO recorded to the confidence ledger.

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

Also **record the escape to the confidence ledger** — it resets that component's clean-GO streak, so the presence advice at step 1 honestly reflects that this task class just slipped:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/confidence.sh" record <test-docs-path>/qa-confidence.md "<component>" escape "<run id>"
```
