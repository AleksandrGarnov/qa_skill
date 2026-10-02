---
name: qa-interview
description: "Interrogates the author / product owner / dev about a feature BEFORE the test checklist is built, to extract the intent that the ticket, code, and research can't give — the exact oracle (what 'correct' means), the business rules, the valid/invalid states, the real boundaries, the worst-case failure, what's out of scope, and what 'done' means. Each answer feeds a specific part of the QA manifest so the checklist is built from intent, not guesses, and testing goes deep. Composed by test-iteration before step 5; also runs standalone to produce a test charter. Trigger phrases include: pre-test interview, clarify the feature before testing, deepen test coverage, what should I ask before testing — and Russian: «вопросы по фиче перед тестами», «уточни фичу перед тестированием», «интервью перед тестами», «что спросить до тестирования», «углубить тестирование»."
argument-hint: "[git-branch]"
---

# QA pre-test interview

Interrogate the person who knows the feature until you can **test it deeply** — until you know, for every risky part, *what the correct result is and where that answer comes from*. The ticket says WHAT was asked; the code says WHAT was built; this interview extracts the **intent and the oracle** that live only in someone's head. Without them a checklist is guesses, and guesses test the happy path.

The interviewee is usually not thinking like a tester. Your job: pull the product logic, rules, edges, and definition of "correct" out of them, and carry every technical call yourself. **Run the whole session in the user's language.**

**Position:** `test-iteration` runs this at **step 4.7** — after context + the adversarial break-it pass (steps 1–4.5), before input/oracle/technique design (step 5). Standalone, it produces a test charter you can hand to any run.

## Step 0 — Recon before the first question

**Never open with questions.** Build enough context that every question could only come from someone who read the diff and the ticket.

- **Reuse what the caller already gathered** when invoked by test-iteration: the diff + changed surfaces, the Jira ACs (`jira-context`), the code/security review (`branch-review`), the research (`qa-research`), and the **landed attacks from the step-4.5 adversarial pass**. Don't re-fetch.
- **Standalone?** Run `branch-diff.sh <branch>` + `changed-surfaces.sh <branch>` and read the ticket yourself first.

Recon ends with three internal lists:
1. **Settled** — answered by ticket/code/spec/convention. **Never ask these.**
2. **Constraints** — facts that belong *inside* the questions you do ask.
3. **Open** — the genuine unknowns about intent. Your first frontier.

Open the session with a one-paragraph recap in plain words: how the changed part behaves today, what you understood the change to be, and what you're treating as already specified — so a wrong premise dies before six questions build on it.

## What you ask vs. what you decide — two gates

Ask only when a decision passes **both**:

- **Gate 1 — fork test.** Is there a genuine unknown about intent that the ticket/code/spec does *not* already answer? If docs or code answer it, settle it, don't ask.
- **Gate 2 — testability-consequence test.** Does the answer change **what we verify** or **what "correct" means** — the expected value, an allowed/forbidden transition, a boundary, a priority, the go/no-go bar? If the answer wouldn't change a single checklist item, it isn't a question.

Everything technical (how to provision data, which API to script, repl vs UI, test structure) is **yours** — decide it silently and log it in the ledger. Never dress a technical trade-off up as a product question.

## The QA question bank — each answer feeds a specific gate

Push relentlessly on these — they are exactly the knowledge the ticket/code can't supply, and each one deepens a different part of the checklist:

| Ask (phrase it in consequences) | The answer becomes | Deepens |
|---|---|---|
| "For input X, what's the *exact* expected result — and where does that number come from (spec/formula/hand-calc)?" | the item's **Expected source** | the oracle gate — kills "the code is its own oracle" at the root |
| "When condition A **and** B both hold, what should happen? And A-not-B? B-not-A? neither?" | **decision-table** rules + a numeric claim | technique-coverage |
| "What states/statuses can this move through? Which transitions are *forbidden*, and what should happen if one is attempted?" | **state-transition** items (valid + invalid) | technique-coverage |
| "What are the valid ranges/limits? Is 0 valid? Is empty/null *different* from 0? What's the max?" | **boundary** classes | technique-coverage; catches null≠0-class bugs |
| "What's the worst thing if this goes wrong — money lost, data corrupted? What concurrent action could collide in the window?" | **adversarial** items, run first | failure-modes-first |
| "What is explicitly **out of scope** / must NOT change?" | regression focus + reasoned `N/A` on changed surfaces | Test-Gap map |
| "What must be true for you to ship this? What single thing would make you reject it?" | **exit criteria**, locked before testing | the verdict |
| "Which part, if broken, hurts the most?" | risk ranking (H/M/L) | prioritization |

## Rounds

Work in **rounds** on the frontier (decisions whose prerequisites are settled). Ask in one round, **numbered, ≤5**, each with your recommended default so a bare "ok" is a full answer. Phrase in consequences, anchored in a recon fact; give 2–3 concrete options, never an open "how would you like it?".

```
❓ **Q1 — <title>**: <body, anchored in what recon found; concrete options with their consequence>
➡️ <your recommended answer>
---
❓ **Q2 — <title>**: …
➡️ <your recommended answer>
```

Wait for answers; recompute the frontier; ask the next round. **Facts are your job** — dispatch a sub-agent, never ask the user for something you can look up. **Decisions are theirs.** A vague answer on substance = that branch is *unsettled*; keep drilling. "You decide" = a decision; take it, log it, never re-ask.

## Ambiguity score — when to stop (adapted from spec-phase)

After each round, rate understanding across five QA dimensions — **oracle clarity · rule completeness · edge coverage · scope boundary · done-criteria** — each `low / medium / high`. Stop when **all five are at least medium** (you can write a defensible expected value and failure list for every risky part), or when the questions still open no longer change any checklist item. Don't grind past the point of diminishing returns — a non-expert answers five sharp questions well and twelve badly.

## Output — fold the answers into the manifest (the whole point)

This interview doesn't produce a standalone document inside a run — it **writes into the frozen manifest** test-iteration is about to build:

- Oracle answers → each item's **`Expected source`** (now a real spec/formula, not "what the code returns").
- Rules / states / boundaries → concrete **items tagged** `decision-table` / `state-transition` / `boundary`, with their **numeric `## Technique coverage`** claims.
- Worst-case / concurrency answers → **adversarial items**, ordered first.
- Out-of-scope answers → reasoned `N/A` rows in **`## Changed-surface coverage`** and the **Regression** focus.
- "Done" / "would reject" answers → **exit criteria** (measurable, locked).
- Record every Q→A in a **`### Clarifications`** block under the manifest's `## Context`, so the reasoning is on the record.

**A critical question left unanswered blocks GO.** If the verdict depends on an answer you couldn't get — the oracle for a money/state item, an allowed-vs-forbidden transition, the done-criteria — do **not** guess it. Write it into the report's **Open questions for PO** block **and** add a `blocked` **critical** checklist item ("needs PO answer: <question>"). The existing gates then make a clean GO impossible (a blocked critical item is NO-GO) — the ambiguity can't be silently shipped over.

## Ledger

Record every technical call you made instead of asking — what you chose and the one-line consequence a non-engineer would care about — so the next step doesn't reopen a closed question. Don't interrupt the rounds with it; present it at the end.

## Done when

All five ambiguity dimensions are ≥ medium (or remaining opens change nothing); every answer folded into the manifest (oracle / items / techniques / exit criteria); unresolved critical questions parked as `blocked` critical items + PO questions; the ledger presented. Hand back to test-iteration step 5 — the checklist is now built from intent, not guesses.
