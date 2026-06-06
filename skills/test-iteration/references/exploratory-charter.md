# Exploratory charter (for `exploratory` runs)

Use when the step-1 AC-missing gate fired (`exploratory — requirements unverified`). With no acceptance criteria to trace against, scripted checks alone under-cover — but "just poke around" is not accountable. Session-Based Test Management (SBTM) makes exploration **structured and reportable** without prescribing exact steps. Structured exploratory sessions find materially more high-severity bugs per hour than ad-hoc poking.

## 1. Write a charter (before the session)
One short line:

```
Explore: <area / feature>
With:    <tools, data, accounts, env>
To discover: <risks / questions you most want answered>
```

Keep it focused; time-box the session to **60–90 minutes**.

## 2. Decide WHAT to cover — SFDIPOT (James Bach, Heuristic Test Strategy Model)
Walk the product dimensions and note what each surfaces:

- **S**tructure — what the system is made of (components, files)
- **F**unction — what it does
- **D**ata — inputs, outputs, states; boundary/odd/large/unicode values
- **I**nterfaces — APIs, integrations, UI surfaces
- **P**latform — OS/browser/device/env it depends on
- **O**perations — how real users use it (workflows, sequences)
- **T**ime — timing, ordering, expiry, concurrency, race conditions

## 3. Recognize PROBLEMS — FEW HICCUPPS (consistency oracles, Michael Bolton)
A behaviour is suspicious if it's inconsistent with any of: **F**amiliar (known bugs), **E**xplainable, **W**orld; **H**istory, **I**mage, **C**omparable products, **C**laims, **U**ser expectations, **P**roduct (internal consistency), **P**urpose, **S**tandards.

## 4. Run tours (optional lenses)
Approach the same area through different mindsets — e.g. the *Money* tour (anything revenue-related), *Bad Neighborhood* (where bugs already clustered), *Historical* (old features near the change).

## 5. Document in real time, then debrief
Capture timestamps, screenshots, repro steps, and **raw evidence** as you go (the evidence-gate still applies — an observed bug needs the actual output). Debrief: what was learned, coverage vs the charter, what to test next. Feed findings back into the checklist and the report's open-questions block.

> Note: an exploratory run is still capped at `⚠️ GO (exploratory)` — it widens coverage, it does not manufacture a requirement basis.

> Sources: Bach & Bach, Session-Based Test Management (Rapid Software Testing); James Bach's SFDIPOT / Heuristic Test Strategy Model; Michael Bolton's HICCUPPS oracles; Hendrickson, *Explore It!*.
