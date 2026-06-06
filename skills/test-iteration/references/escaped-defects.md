# Escaped-defects loop (lite)

The only way the QA process gets *smarter over time* instead of staying static: when a defect reaches staging/prod **after a GO** — i.e. QA missed it — capture it, learn from it, and feed the lesson back into the next run's risk-ranking. Keep this lightweight (a log + a memory note), not an analytics platform.

## When
A bug surfaces in staging/prod that this QA cycle should have caught (user report, monitoring alert, or post-release finding) on a build that was given GO / GO-with-deferrals.

## Capture (one short record per escape)
```
escape: <PAY-XXX-ESC-NN>
component/area: <where it lives — the hotspot key>
severity: <blocker/major/minor>     discovered-by: <user | monitoring | internal>
why not caught: <missing edge case | no real-data observation | thin regression | no AC | mocked-only>
```
The **"why not caught"** field is the whole point — it names the structural gap, not just the bug.

## Act
1. **Add a regression check** for the exact escape so it can't recur silently (and, if automatable, it's a candidate for the autotest bridge).
2. **Fix the process, not just the symptom**: if "why not caught" repeats across escapes, that category is a standing weakness — strengthen the relevant step (e.g. recurring "mocked-only" escapes → lean harder on the evidence-gate; recurring "thin regression" → wider blast-radius in step 5).
3. **Weight the hotspot**: record the component as a known hotspot. Next time the diff touches it, raise its baseline risk in triage (step 5) and test it deeper.

## Measure (optional, by version not by time)
Escaped-defect rate = production defects ÷ total defects found (incl. pre-release). Mature teams run <5%. Track **per release/version**, not per calendar period — time-based mixes versions and blurs the signal. The goal is detection shifting earlier, not a prettier number.

> Lite by design: a markdown log in the project plus a hotspot note (the skill's memory) is enough. Don't build infrastructure before the pain is real.

> Sources: Defect/Bug Escape Rate guides (em-tools, Opsera, Count, Value-Stream-Thinking — "measure by version", root-cause every critical escape, regression-test each one).
