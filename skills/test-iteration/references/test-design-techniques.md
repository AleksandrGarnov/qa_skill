# Reference — test-design techniques: choosing inputs, combinations, and sequences

"Coverage is what you executed" is only honest if you also chose *which* inputs, *which* combinations, and *which* sequences to run on purpose. "I tested a few" is neither coverage nor a defensible skip. Test-design techniques cut a huge input space down to a small, **justified** set — and each one leaves a coverage claim you can defend at the step-6.5 review.

ISTQB groups them into three families; this plugin uses all three:

- **Black-box (specification-based)** — derive tests from the *specified behaviour*, not the code: equivalence partitioning, boundary value analysis, decision tables, state transition testing, use-case testing. (Pairwise/combinatorial is the combination-selection layer on top.)
- **Experience-based** — error guessing, exploratory, checklist-based. Complementary: they catch what the systematic techniques miss.
- **White-box (structure-based)** — statement/branch coverage. Out of scope for this manual black-box workflow (the dev's unit tests own it); named here only so you don't mistake a green unit suite for black-box coverage.

**Pick the technique from the *shape of the change*, not habit** (the selection guide is at the bottom). Then **record which technique produced each checklist item** — the manifest's `## Items` table has a **`Technique`** column and `verify-coverage.sh` fails closed if any item leaves it blank or names something outside the technique vocabulary. The gate is *structural* (a technique is declared); whether it's the *right* technique for that feature is a semantic judgement made at the step-6.5 review.

---

## 1. Equivalence partitioning (EP) — pick representative values

Divide each input's domain into **classes where every value is treated the same**, then test **one representative per class** (plus each invalid class). Testing a second value from the same class adds cost, not coverage.

- Age field `0–120`: classes `<0` (invalid), `0–17`, `18–64`, `65+`, `>120` (invalid) → 5 representatives, not 121 values.
- Coupon: `valid & unused`, `valid & used`, `expired`, `malformed`, `none` → one each.
- Do this **per parameter first** — it shrinks the value set that everything downstream multiplies.

**Coverage claim:** "one representative per class, all valid + invalid classes for {fields}."

## 2. Boundary value analysis (BVA) — test the edges of each class

Most bugs live at boundaries. BVA only applies to **ordered** classes. For each, test **min−1 / min / max / max+1** (2-value BVA is min & max; 3-value adds the just-outside neighbours and is more rigorous — it catches `==` written for `<=`).

- Quantity `1–99`: test `0, 1, 99, 100`.
- A 30-day window: test day `0`, `1`, `30`, `31`; the timestamp at `23:59:59` vs `00:00:00`.
- Off-by-one, `>=` vs `>`, inclusive/exclusive ranges, empty vs one vs many — all surface here.

**Coverage claim:** "min−1/min/max/max+1 per ordered field {fields}."

## 3. Decision table — cover combinations of conditions / business rules

When the outcome depends on a **combination of conditions** (business rules, eligibility, pricing tiers, permission logic), a decision table makes the combinations explicit so none is overlooked. **Conditions** are the top rows, **actions** the bottom rows; each **column is a rule** = one unique combination of conditions with its expected actions.

Worked example — discount eligibility:

```
Conditions          R1  R2  R3  R4
  Member?            Y   Y   N   N
  Cart >= $100?      Y   N   Y   N
Actions
  Apply 10% off      X   -   -   -
  Free shipping      X   -   X   -
```

Rules that keep it honest:
- **A full table has a column for every combination** of condition values (`2^n` for n boolean conditions). **Collapse** it: delete **infeasible** combinations (`N/A`) and **merge** columns where a condition doesn't affect the outcome (mark it `—`, "don't care"). Note *why* each is dropped — a silently missing rule is a gap.
- **Coverage = feasible rules exercised ÷ total feasible rules.** The minimum standard is **≥1 test per feasible rule** (every remaining column gets a test). Aim for 100% of feasible columns.
- Conditions/actions can be boolean (`Y/N`), or **extended-entry** (ranges, discrete values, EP classes) — feed EP/BVA representatives in as the condition values.
- The table also **surfaces gaps and contradictions in the requirements** — two rules with the same conditions but different actions is a spec bug to raise, not a value to guess.

**Coverage claim:** "decision table over {conditions}, N feasible rules, 1 test/rule; dropped M infeasible + merged K don't-cares (listed)."
**Technique tag:** `decision-table`.

## 4. State transition — cover states, transitions, and invalid events

When the feature is a **state machine** — order status, payment lifecycle, session/auth state, subscription, document workflow, feature-flag rollout — bugs hide in the *transitions* and in *events fired from the wrong state*, not in any single state. Model states + events + guards + actions (`event [guard] / action`), then choose a coverage criterion:

- **All-states** — every state is visited at least once. *Weakest*; achievable without exercising every transition.
- **Valid transitions (0-switch)** — every **valid** transition is exercised once. **The default, most widely used** criterion. Guarantees all-states.
- **All transitions** — every valid transition **plus every invalid event attempted from each state** (the empty cells of the state table). **Test one invalid transition per test case** to avoid fault-masking (one defect hiding another). Minimum bar for **mission/safety-critical** flows — and for money/state changes here.
- **N-switch** — all valid sequences of **N+1** transitions (e.g. 1-switch = pairs of transitions), for order-dependent bugs.

Worked example — payment: `created → authorized → captured → refunded`. Valid-transitions coverage runs each arrow once. All-transitions **also** attempts the illegal ones — `capture` on a `refunded` payment, `refund` on a `created` one, double-`capture` — each of which must be rejected cleanly (no double charge, no negative balance). Those invalid attempts are exactly the adversarial "out-of-order / duplicate" items from step 1.

**Coverage claim:** "state-transition, {criterion} e.g. all-transitions; V valid + I invalid transitions, each exercised/attempted; one invalid per test."
**Technique tag:** `state-transition`.

## 5. Use-case / scenario — cover the flows a real actor walks

Derive tests from **use-case scenarios**: the **basic (main) flow**, each **alternative flow**, and each **exception flow**. This is the technique behind this plugin's journey-first checklist — but name it explicitly so alternatives and exceptions aren't quietly dropped in favour of only the happy path.

- Basic flow: actor completes the goal on the expected path.
- Alternative flows: valid variations (guest vs member checkout, saved vs new card).
- Exception flows: preconditions unmet, external step fails, actor abandons mid-flow — the failure legs that carry the real risk.

**Coverage claim:** "use-case {name}: basic + A alternative + E exception flows, each traced to a journey."
**Technique tag:** `use-case`.

## 6. Combination selection — pairwise / t-way (over the values EP/BVA chose)

Empirically, **most interaction defects are triggered by a single parameter or a pair** — so covering **all 2-way combinations (t=2, "pairwise")** finds the large majority at a fraction of the exhaustive cost. Apply whenever the change has **≥3 interacting parameters / config axes / flags**. Feed the EP/BVA representatives in as the values.

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

**Coverage claim:** "pairwise over {P,C,Cur,Dev,Login}, N cases, all 2-way pairs; `auth×role×flag` at t=3; excluded impossible pairs per constraints."
**Technique tag:** `pairwise`.

## 7. Error guessing (experience-based) — target the likely mistakes

Systematic techniques cover the *specified* space; error guessing targets the mistakes a developer likely made and the inputs users actually send. Enumerate them deliberately — don't call it "poke around". Sources: the **step-4.5 adversarial pass**, prior escaped defects, [learned-checks.md](learned-checks.md), and known fault patterns (division by zero, null/empty, huge/tiny/negative, off-by-one, encoding/locale, timezone/DST, concurrent double-submit, resource exhaustion). Each guess that fits the change becomes a concrete checklist item.

> A **classification tree** is the modelling aid for §1/§6: draw each parameter as a branch, its EP/BVA classes as leaves, then pick combinations across leaves. Same discipline, visual form — record it as `classification-tree` if that's how you derived the set.

**Coverage claim:** "error-guessing from {adversarial pass / escaped defects / fault patterns}, listed."
**Technique tag:** `error-guessing` (or `classification-tree`).

---

## How this plugs into the QA cycle

Apply in **triage (step 5)**, choosing per the change shape:

| The change… | Technique | Tag |
|-------------|-----------|-----|
| has a valued input (field, param, amount) | EP + BVA | `equivalence`, `boundary` |
| outcome depends on a **combination of conditions / business rules** | decision table | `decision-table` |
| moves through **statuses / a lifecycle / a state machine** | state transition (≥ valid-transitions; all-transitions for money/state) | `state-transition` |
| is a user flow with alternative & exception paths | use-case / scenario | `use-case` |
| has **≥3 interacting parameters / flags** | pairwise (t=3 on risky trios) | `pairwise` |
| risk from likely mistakes / past escapes | error guessing / classification tree | `error-guessing`, `classification-tree` |
| trivial single-value smoke/regression, no design needed | — (justify) | `n/a — <reason>` |

Then, in every `## Items` row of the manifest:
1. Derive the item with the fitting technique (they **compose**: EP picks values, BVA adds edges, decision-table/state-transition/use-case pick combinations/sequences, pairwise trims the product).
2. Put the concrete case in the row and **tag its `Technique`**.
3. **Record the coverage claim** honestly (the per-technique lines above). A silent "tested the main combinations" is a coverage gap the step-6.5 review flags — and a blank/unknown `Technique` is blocked by `verify-coverage.sh` before the run can be finalized.

> Composition, not competition. A change with one input needs only EP+BVA; multi-condition rules need a decision table; stateful flows need transition coverage; multi-parameter configs need pairwise. Most non-trivial changes use several.

> Sources: ISTQB Foundation (CTFL) syllabus §4.2 black-box techniques (equivalence partitioning, boundary value analysis, decision table testing, state transition testing, use case testing) & §4.4 experience-based (error guessing, exploratory); ISTQB Glossary; ISO/IEC/IEEE 29119-4 (test design techniques & coverage measures); Kuhn/Kacker/Lei (NIST) — combinatorial testing empirical studies; Microsoft PICT.
