# Worked example — a full QA cycle, tailored

A compact, end-to-end illustration of `test-iteration` on a small change. It is **not** a template to copy verbatim — it shows the *shape* of good output: tailored scope, code-derived checks, AC traceability, an honest verdict, and a clean re-test round. Use the real templates ([manual-checklist-template.md](manual-checklist-template.md), [test-report-template.md](test-report-template.md)) for actual runs.

**Scenario:** branch `feature/PAY-412-remember-card`. A "Remember card" checkbox is added to the payment form; when ticked, the masked card number is saved so the field is pre-filled next time.

---

## Step 1 — Requirement context (from `jira-context`)

```
ticket: PAY-412  (source: branch)
type: Story
summary: Add "Remember card" checkbox to the payment form
priority: Medium   components: payments-web   links: —
acceptance criteria:
  AC1: A "Remember card" checkbox is shown under the card-number field   [explicit] [static]
  AC2: When ticked and a payment succeeds, the masked card is remembered  [explicit] [runtime]
  AC3: On the next visit the card field is pre-filled from the saved value [explicit] [runtime]
  AC4: When unticked, nothing is remembered and any saved value is cleared [inferred — confirm with PO] [runtime]
flags: AC4 inferred — confirm with PO
```

## Step 5 — Triage, with code-derived checks

Diff touches: `PaymentForm.tsx` (new checkbox + `rememberCard` state), `cardStorage.ts` (new `saveCard`/`loadCard`/`clearCard` on `localStorage`).

Code-derived checks beyond the AC text:
- **Branch:** `rememberCard === true` → save path; `=== false` → clear path (covers AC4's "clear").
- **Persistence:** what `saveCard` writes, what `loadCard` reads, when `clearCard` runs (logout? unticking?).
- **Discrepancy ⚠️:** `cardStorage.ts` saves the **full PAN**, not the masked value the AC describes — storing card data in `localStorage` is a security risk. → logged as risk + **question for PO**.

## Step 6 — Tailored checklist (excerpt) + exit criteria

Scope (template's *Scope & tailoring*): UI + persistence change, low runtime cost — run Smoke, Functional, UX/UI, Edge/negative (storage), Security (PAN storage), Regression; `Performance — N/A: localStorage only, no runtime path`.

**User journey (the spine) — one actor here, the cardholder:**

| # | Actor | Journey | Produces | How verified | Expected | Trace |
|---|-------|---------|----------|--------------|----------|-------|
| J1 | cardholder | tick "Remember card" → pay → return next visit | `localStorage.savedCard` | DevTools → pay → reload | card field pre-filled from the saved **masked** value | AC1–AC3 |

**Checks (table; each traces to J1):**

| # | What to check | How to run | Expected | Risk | Trace |
|---|---------------|-----------|----------|------|-------|
| 1 | Smoke: form loads, payment completes | open form, pay | success | M | AC1 |
| 2 | Checkbox visible under card field | open form | shown | L | AC1 |
| 3 | Tick + successful payment → remembered | pay with box ticked | `savedCard` written | M | AC2 |
| 4 | Next visit → field pre-filled | reload | field pre-filled | M | AC3 |
| 5 | Unticked → nothing saved AND prior value cleared | untick, pay | `savedCard` absent | M | AC4 |
| 6 | Security: only the masked value persisted, never full PAN/CVV | DevTools → Application → localStorage | masked only | H | AC2 |
| 7 | UX: checkbox hover/focus/disabled states, keyboard-reachable | keyboard + pointer | distinct, reachable | L | AC1 |
| 8 | Regression: payment without ticking behaves as before | pay, box unticked | unchanged | M | AC2 |

Exit criteria — **mandatory core (locked):** `open blocker/major == 0` · `smoke: all pass` · `critical-path coverage == 100%` · `every explicit AC: covered & passing` · `security findings: closed or mitigated`. **Project addition:** `nothing but the masked value is persisted`.

## Step 6.5 — Independent completeness review

A fresh `general-purpose` subagent — given only the diff, AC, the `changed-code → item` map, and the checklist — reports back: *"`clearCard` runs on logout too, but no item covers the logout path; AC4 only checks unticking."* Real gap → add an item: "Log out with a saved card → storage cleared · Trace → AC4". The author would not have caught their own omission; the objective second context did.

## Step 7 — Approval

User approves checklist + exit criteria (the locked core can't be weakened), and answers the AC4 question: "yes, unticking must clear it." AC4 becomes explicit.

## Step 9 — Report (round R1, excerpt)

**Verdict:** ⛔ NO-GO — security exit criterion failed (full PAN persisted).

| AC | Covering items | Evidence | Status (R1) | Defects |
|----|----------------|----------|-------------|---------|
| AC1 | Smoke, Functional #1 | observed (rendered) | pass | — |
| AC2 | Functional #2, Security | observed-data (localStorage line) | **fail** | PAY-412-BUG-01 |
| AC3 | Functional #3 | observed-data (field pre-filled) | pass | — |
| AC4 | Functional #4, logout item | observed-data (key absent after clear) | pass | — |

> Evidence-gate in action: AC2 is `runtime`, so a green unit test wouldn't close it — the `pass`/`fail` call rests on the **actual localStorage line** observed in DevTools. That raw observation is exactly what caught the full-PAN bug a `unit:mocked` test would have missed.

Code coverage matrix (changed-code ↔ tests) — both axes audited:

| Changed code | Covering items | Status |
|--------------|----------------|--------|
| `saveCard` (rememberCard === true) | Functional #2, Security | fail |
| `clearCard` (untick / logout) | Functional #4, logout item | pass |
| `loadCard` (next visit) | Functional #3 | pass |

**Orphan check:** AC → all covered; code → all covered (the logout branch was the gap the 6.5 review caught); no unfounded tests.

**Open questions for PO / discrepancies:** AC says "masked card"; code persisted full PAN → resolved as a defect, not just a question.

```
### PAY-412-BUG-01 — [Payments] Full card number stored in localStorage
- Severity: blocker   Priority: high
- Found in round: R1   •   Fix verified in round: open
- Actual: localStorage key "savedCard" holds the full 16-digit PAN in clear text.
- Expected: only the masked value (e.g. **** **** **** 4242) is persisted.
```

## Step 10 — Re-test (round R2)

Dev ships a fix; build bumped to `a1b2c3d`. Re-run only the failed item + security + a regression pass.

| AC | Status (R2) | Defects |
|----|-------------|---------|
| AC2 | pass | PAY-412-BUG-01 (Fix verified in round: R2, build a1b2c3d) |

**Verdict:** ✅ GO — all exit criteria met on build `a1b2c3d`.

## Step 11 — Close the loop (optional)

With the user's "yes", post to PAY-412:
> QA: ✅ GO on build a1b2c3d. 9/9 executed, 9 pass. PAY-412-BUG-01 (PAN in localStorage) fixed & verified R2. Full report: <link>.
