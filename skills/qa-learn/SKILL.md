---
name: qa-learn
description: "Build the project's QA learning stores from the whole corpus of prior QA documents — not just the current run. Mines every past report (found bugs per component + severity), the escaped-defects log (per-component 'why not caught' categories), and verdict history; then curates the signal into reusable learned-checks AND a per-component failure-mode knowledge base that biases future technique selection and is enforced by the Learned-risk gate. In-context curation of real outcomes, no model. Run once to seed from history, and re-run periodically to keep the stores current. Trigger phrases: learn from previous runs, build the QA knowledge base, mine prior reports, backfill learned checks, train the QA skill on past documents — and Russian: «обучи скилл на прошлых прогонах», «построй базу знаний QA», «учись на старых отчётах», «полноценное обучение на прошлых доках»."
argument-hint: "[test-docs-path]"
---

# QA learning — distil prior documents into stores that shape future runs

Turn the **history that already exists** into knowledge the QA cycle uses automatically. This is **in-context curation of real outcomes**, not model training: a deterministic harvester extracts the signal, *you* judge what generalises, and it's written to two plain-markdown stores the cycle reads. Supersedes the old one-shot backfill — run it once to seed from history, re-run periodically as the corpus grows.

It writes two stores (both under the project's test-docs path, beside the reports):
- **`learned-checks.md`** — concrete reusable *checks* ([[learned-checks]]); `test-iteration` step 5 pulls the rows matching the changed components into every relevant checklist.
- **`qa-knowledge.md`** — per-component *failure-mode profiles*: the risk category that keeps recurring in a component and the technique a future run must apply. `test-iteration` step 1 recalls it, step 5 biases technique selection, and **`verify-learned.sh` fails the merge** if a changed component's known recurring risk isn't addressed.

## 1. Resolve the corpus
Test-docs path = `$ARGUMENTS` if given, else read it from the project's `CLAUDE.md` (where `test-iteration` stores reports). If neither yields a path, **stop and ask** — don't guess.
**Done when:** you have a real directory of past QA documents.

## 2. Harvest (mechanical — don't open every file by hand)
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/qa-harvest.sh" summary  <test-docs-path>   # per-component digest, ranked by frequency
"${CLAUDE_PLUGIN_ROOT}/scripts/qa-harvest.sh" bugs     <test-docs-path>   # every found bug: component + severity + title
"${CLAUDE_PLUGIN_ROOT}/scripts/qa-harvest.sh" escapes  <test-docs-path>   # escaped defects: component + category ("why not caught")
"${CLAUDE_PLUGIN_ROOT}/scripts/qa-harvest.sh" verdicts <test-docs-path>   # GO/NO-GO per report (seeds confidence)
```
The `summary` is your worklist: components ranked by how much they've hurt, with their recurring "why not caught" categories. Empty output = no template-format docs; fall back to reading older-format docs yourself.
**Done when:** you have the harvested signal (or know there's nothing to mine).

## 3. Curate — keep only what generalises (the whole point)
A learning pass is a **seed, not gospel.** From the harvest, keep **high-signal** patterns; drop one-offs.

**→ learned-checks (concrete checks):**
- **Recurring** — the same component + failure appears across **≥2 reports** → a standing weakness, not bad luck.
- **GO-escapes** — bugs that surfaced after a GO (from `escapes`) — the most valuable, the process missed them.
- **Money / state / auth / data-loss** components — weight up even on a single occurrence.
Phrase each as *what to verify next time* (not the bug text) + the component + the "why".

**→ qa-knowledge (failure-mode profiles):** for each component whose harvest shows a **recurring risk category** (e.g. `concurrency / in-the-window` seen on ≥2 escapes, or repeated null-render bugs), write one row: the **recurring risk**, and the **technique/check a future run must apply** to it (start the "required" with a technique family — `state-transition` / `boundary` / `decision-table` / `pairwise` — so step 5 and the gate can key on it). This is what makes future testing deeper on exactly the spots that burned before.

**Done when:** a short curated list for each store (high-signal only — fewer is better), each row traceable to the report/escape that taught it.

## 4. Approve — PAUSE (user required)
Show the proposed `learned-checks` rows and `qa-knowledge` rows (and, in one line, what you dropped). These stores **steer and gate** future runs — **wait for "ok" or edits before writing.** Don't append on your own.
**Done when:** the user approved (or trimmed) both lists.

## 5. Write
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" add <test-docs-path>/learned-checks.md "<component>" "<check>" "<why>"
"${CLAUDE_PLUGIN_ROOT}/scripts/qa-knowledge.sh"   add <test-docs-path>/qa-knowledge.md   "<component>" "<recurring-risk>" "<required technique/check>" "<freq>" "<learned-from>"
```
Optionally seed the confidence ledger from the verdict history (`confidence.sh record … go|escape`). Then show both stores (`list`) and the counts added.
**Done when:** `learned-checks.md` + `qa-knowledge.md` hold the approved rows; report `added N checks + M risk-profiles from K documents`.

## How it feeds runs (no further action — it's automatic from here)
- **Step 1 recall:** `test-iteration` reads `qa-knowledge.sh match <changed-components>` + the confidence streak.
- **Step 5 inject:** `learned-checks.sh match` folds concrete checks in; the knowledge profiles **bias technique selection** (a component with a recurring concurrency risk → mandatory state-transition/adversarial items) and populate the manifest's `## Learned risks` section.
- **Merge gate:** `verify-learned.sh` blocks the merge if a changed component's known recurring risk isn't addressed there.
- **Step 12** keeps both stores growing from each new outcome; re-run `qa-learn` periodically to re-rank as the corpus grows.
