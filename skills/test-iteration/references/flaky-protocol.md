# Flaky-result protocol

A check that passes on one run and fails on the next **without the build changing** is not a `pass` and not a `fail` — recording it as either corrupts the verdict. Treat flakiness as its own bucket and its own class of bug ("a flaky test is a test that lies"). This applies to both automated checks and manual staging observations (staging timing, shared data, async UI).

## 1. Detect — by flip, not by one retry
If a result flips between pass/fail across runs of the **same build**, it's flaky. Don't infer health from "it passed on retry #2" — a retried pass is **flake telemetry to investigate**, not evidence the behaviour works.

## 2. Bucket it `flaky` (distinct from pass/fail)
Record the result as `flaky` with the raw outputs of both the passing and failing observation. A `flaky` result on the **critical path is a coverage gap** (you don't actually know the behaviour) → it blocks a clean GO until resolved, exactly like `blocked`.

## 3. Re-observe a bounded number of times
Re-run 1–2 times to characterise the flip; never auto-retry until green and call it done. Never auto-suppress a check that was **previously stable** — a newly-flaky stable check is more likely a real intermittent bug (race, timeout, shared state) than test noise.

## 4. Quarantine (if it's a standing automated test, not this run's finding)
Move it out of the blocking gate but **keep it running** for signal. Quarantine needs guardrails or it becomes a graveyard (Fowler's old rule: small list, short life):
- a **named owner** (a person, not "the team"),
- a **hard expiry** (≤30 days), after which it's fixed or deleted,
- non-blocking but visible.

## 5. Root-cause, don't mask
Most flakiness is a few patterns: hardcoded waits, shared/leaking state, missing wait-for-condition, network without retry, over-specific assertions, time/timezone (`setTestNow` vs real clock). Fix the cause; record it. An intermittent failure can be a **real production race** — investigate before dismissing.

> Sources: Datadog Flaky Tests Management (quarantine/attempt-to-fix/root-cause); Wopee.io & Gaffer flaky-test guides (flip-rate detection, owner+expiry); Martin Fowler, *Eradicating Non-Determinism in Tests*; Bitrise.
