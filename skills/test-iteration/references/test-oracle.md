# Reference — the test oracle: knowing the right answer independently

A **test oracle** is the source that tells you what the *correct* output is, so you can compare it to what the system actually did. Observing a raw value proves nothing unless you have an oracle to judge it against. The **oracle problem** is that for many real outputs the correct answer isn't obvious to compute — and the lazy escape is to let the implementation be its own oracle ("expected = whatever the code returned"). That's a green check that only proves the code agrees with itself: the same failure as a self-testing mock, one level up.

This skill already refuses code-read and mocked evidence for runtime ACs. The oracle rule closes the matching hole on the **expected** side: a real observation, checked against an expected value that *also* came from the implementation, is still not a test.

## Rule

For every check — and **mandatorily** for any **computed / money / aggregated / state-transition / reconciliation** AC — the expected result must be derived **independently of the implementation under test, and before the run**, with its source recorded. If the correct answer genuinely can't be pre-computed, substitute a **metamorphic / property invariant**. An item with neither is a GAP, not a `pass`.

## Independent oracle sources (best first)

1. **Specification / formula** — the AC, business rule, or spec states the exact expected value or the formula to compute it. Compute it yourself; don't ask the code.
2. **Hand calculation** — for a bounded case, work the number out by hand (a $100 order, 8% tax, a 10% coupon → $97.20 expected, derived on paper, then observed).
3. **Known invariant** — a truth that must hold regardless of internals (double-entry: debits == credits; a balance never goes negative for a non-overdraft account; row counts before == after for a pure move).
4. **Reference implementation / trusted tool** — a second, independent way to get the answer (a spreadsheet, a `jq`/SQL aggregate computed directly from source rows, a well-trusted library, a prior system being replaced).
5. **Trusted historical / golden value** — a value known-correct from before the change (a reconciled figure, a snapshot approved by the PO), used as a regression baseline.

> Ranking down this list is fine; **stepping off it onto "what the code returned" is not.** If the only way you can state the expected is to run the code, you don't yet have a test — you have a change detector.

## Metamorphic / property invariants (when the exact answer is unknowable)

Some outputs can't be pre-computed: search relevance, ranking, ML inference, a complex transform, floating-point aggregates, non-deterministic ordering. Don't fall back to "looks reasonable" — assert a **relation that must hold** between inputs and outputs, or across two runs:

- **Conservation** — sum of parts equals the whole (line items sum to the invoice total; splitting a payout doesn't change the total paid).
- **Idempotence** — applying the operation twice equals applying it once (retrying a charge, re-running a sync, re-saving a form).
- **Inverse / round-trip** — undo restores the input (encode→decode, serialize→deserialize, create→delete leaves no trace, import an export).
- **Monotonicity / ordering** — a "more relevant"/"larger" input never ranks below a "less relevant"/"smaller" one; adding a matching term never drops the true match out of results.
- **Permutation invariance** — reordering inputs that shouldn't matter doesn't change the result (order of independent events, set membership).
- **Consistency across equivalent paths** — the UI total, the API total, and the DB aggregate agree; two flows that must produce the same state do.
- **Bounds** — the output stays within a provable range (a percentage in [0,100]; a discounted price ≤ list price and ≥ 0).

A metamorphic check is a real `pass`: it's an observation against an independent rule. Prefer it over an exact value whenever the exact value would have to come from the code.

## How to record it

In the manifest / checklist, each item carries its **expected + source**:

| ID | Journey | What to run | Expected | Expected source |
|----|---------|-------------|----------|-----------------|
| 3 | J1 | `POST /orders {items:[…], coupon:SAVE10}` → read `total` | `97.20` | hand calc: 100 − 10% + 8% tax (spec §4.2) |
| 7 | J2 | reconcile ledger for account A after 3 postings | debits == credits | invariant (double-entry) |
| 9 | J1 | search "red shoes", inspect ranking | exact-title match ranks above description-only match | metamorphic: relevance monotonicity |

At execution (step 8) the bucket is `pass` only when the raw output **matches that expected / the invariant holds** — recorded in the report's Actual column against the Expected, not against plausibility. At step 9 the self-audit names, for each critical/AC pass, the independent expected it was checked against.

> Sources: Barr, Harman, McMinn, Shahamiri, Yoo — *The Oracle Problem in Software Testing: A Survey* (IEEE TSE, 2015); ISTQB Glossary (*test oracle*); Chen et al. — *Metamorphic Testing: A Review of Challenges and Opportunities* (ACM CSUR, 2018); property-based testing (QuickCheck lineage).
