# Reference — test-design techniques: choosing inputs and combinations

"Coverage is what you executed" is only honest if you also chose *which* inputs and *which* combinations to run on purpose. A feature with a handful of parameters explodes into hundreds of combinations; "I tested a few" is neither coverage nor a defensible skip. These three techniques compose to cut the space to a small, justified set — use them together, in this order.

## 1. Equivalence partitioning (EP) — pick representative values

Divide each input's domain into **classes where every value is treated the same**, then test **one representative per class** (plus each invalid class). Testing a second value from the same class adds cost, not coverage.

- Age field `0–120`: classes `<0` (invalid), `0–17`, `18–64`, `65+`, `>120` (invalid) → 5 representatives, not 121 values.
- Coupon: `valid & unused`, `valid & used`, `expired`, `malformed`, `none` → one each.
- Do this **per parameter first** — it shrinks the value set that everything downstream multiplies.

## 2. Boundary value analysis (BVA) — test the edges of each class

Most bugs live at boundaries. For each ordered class, test **min−1 / min / max / max+1** (2-value BVA is min & max; 3-value adds the just-outside neighbours).

- Quantity `1–99`: test `0, 1, 99, 100`.
- A 30-day window: test day `0`, `1`, `30`, `31`; the timestamp at `23:59:59` vs `00:00:00`.
- Off-by-one, `>=` vs `>`, inclusive/exclusive ranges, empty vs one vs many — all surface here.

## 3. Pairwise / combinatorial — cover interactions without the full product

Empirically, **most interaction defects are triggered by a single parameter or a pair** — so covering **all 2-way combinations (t=2, "pairwise")** finds the large majority of them at a fraction of the exhaustive cost. Feed the EP/BVA representatives in as the values.

Worked example — 5 parameters, exhaustive = `4×4×4×3×2 = 384`:

```
# checkout.txt  (a PICT-style model)
Payment:   Card, PayPal, UPI, Wallet
Country:   US, UK, IN, DE
Currency:  USD, GBP, INR, EUR
Device:    Desktop, Mobile, Tablet
LoggedIn:  Yes, No
```

Pairwise (t=2) covers every two-way pair in **~16–20 tests** instead of 384 — every `(Payment,Country)`, `(Country,Currency)`, `(Device,LoggedIn)`, … pair appears at least once. Generate with a tool (Microsoft **PICT** `pict checkout.txt`, ACTS, or Hexawise) or by hand for tiny models.

Rules that keep it honest:
- **Model the constraints.** Invalid pairs must be excluded, not tested: `IF [Country]="US" THEN [Currency]="USD";`. Otherwise the suite wastes cases on impossible combinations.
- **Include representative invalid values** — a pairwise tool only covers the values you list; list negative/boundary representatives (from EP/BVA) deliberately, constrained so they're tested on purpose, not mixed randomly.
- **Raise the strength for high-risk subsets.** Pairwise misses defects needing **3+** parameters to coincide. For a known-risky trio — e.g. `auth-state × role × feature-flag` — use **t=3** on that subset (still far below exhaustive). Variable-strength: high everywhere it matters, t=2 elsewhere.
- **Pin determinism.** PICT's default output varies by seed — pin a seed or commit the generated case list so test IDs are stable run-over-run.

## How this plugs into the QA cycle

Apply in **triage (step 5)** whenever the changed feature has **≥3 parameters / configuration axes / flags** that interact:

1. EP each parameter → representative values (+ invalid classes).
2. BVA each ordered parameter → add its edge values.
3. Pairwise-combine the representatives → the minimal combination set; t=3 on any high-risk trio.
4. Put the resulting rows in the checklist as concrete items, and **record the coverage claim honestly**: "pairwise over {P,C,Cur,Dev,Login}, 18 cases, all 2-way pairs covered; `auth×role×flag` at t=3; excluded impossible pairs per constraints." A silent "tested the main combos" is a coverage gap the step-6.5 review flags.

> Composition, not competition: **EP picks which values, BVA adds the edges, pairwise picks which combinations.** A change with one input needs only EP+BVA; multi-parameter configs, permissions matrices, and feature-flag interactions are where pairwise earns its keep.

> Sources: ISTQB Foundation syllabus & Glossary (equivalence partitioning, boundary value analysis, combinatorial testing); ISO/IEC/IEEE 29119-4 (test design techniques); Kuhn/Kacker/Lei (NIST) — combinatorial testing empirical studies; Microsoft PICT.
