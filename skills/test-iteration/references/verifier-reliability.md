# Reference — trusting the verifier (LLM-as-judge is the weakest link)

This skill leans on LLM subagents to *verify*: the independent completeness review (6.5), the independent re-execution of the critical path (8.5), the adversarial break-it pass (4.5), and the review passes. That is deliberate — a blind second context catches what the executor rationalizes. But an LLM judge has documented, specific failure modes, and a single-shot verdict from one hides them. Treat the verifier's output as evidence to be checked, not a truth to be trusted.

## The three failure modes that matter here

1. **Silent omission.** A model asked "what's missing / is this complete?" over-rejects on invented problems but **under-reports real gaps**, and an omission is **6–7× harder to catch in review** than an over-inclusion. This hits 6.5 (completeness) and 4.5 (did we miss an attack?) hardest: the review can look thorough and still have quietly skipped a whole class.
2. **Non-determinism.** The same judge returns **different verdicts on the identical input across runs**, even at temperature 0 (batch/MoE/floating-point effects); borderline items flip pass/fail. On current models temperature is deprecated, so "pin the knobs" no longer applies. A single run reports noise as signal.
3. **Over-correction / hallucination.** Prompted to explain and propose fixes, a judge shifts toward **rejecting correct behavior** (high false-negative) and can **assert behavior the system never showed** (hallucination — the most-reported risk in the literature). This hits 4.5 (a claimed "break" that never happened) and the review passes (a "bug" in correct code).

## The mitigations — apply them, don't just name the risk

### A. Gate the verifier on a known-correct probe (the one mitigation that consistently works)
Before trusting a verifier's verdict, confirm it can tell right from wrong on a case whose answer you already know. A verifier that fails the probe is not trustworthy on the real item — re-run or escalate, don't accept its verdict.

- **8.5 independent re-execution:** include, among the items the blind subagent re-runs, **one control with a known outcome** — a known-good case that must come back green and/or a known-bad (or a deliberately broken input) that must come back red. If the blind run can't reproduce the known result, its re-execution of the *real* items is not corroboration — investigate the harness, don't record `agree`.
- **6.5 completeness review:** hand the reviewer a checklist with **one planted, known gap** (an AC you deliberately left uncovered, a changed symbol with no item). If the review doesn't surface the planted gap, it's not sensitive enough to trust on the real gaps — strengthen the prompt / re-run before believing "nothing missing".
- Record the probe result in the report (`probe: known-good reproduced ✓ / known-bad caught ✓`) so "the verifier was itself verified" is visible, not assumed.

### B. Don't trust a single-shot verdict on a borderline call — surface disagreement
- For a **critical-path** verdict that is borderline, or where the blind re-run (8.5) *disagrees* with the executor, do **not** average or silently pick one. A disagreement is the **most valuable signal** — record it as a GAP and investigate which run is right.
- Where a judgment is genuinely close, take **more than one independent sample** and go with the majority (self-consistency), and **report the disagreement rate** rather than a lone verdict. Two of three independent skeptics refuting is a real signal; a lone "looks fine" is not.

### C. Counter over-correction with execution, not more prose
- A **claimed break (4.5) is only real if a reproducing test actually ran and went red.** A "break" the subagent asserts but can't reproduce is a hallucination — **discard it**, don't file it. (This is why 4.5 requires a reproducing test per landed attack: it's the execution-based filter against over-reporting.)
- A **review finding must name `file:line` + a concrete failure scenario** (inputs → wrong output). A finding that can't state how it fails is speculative — mark it so, don't let it block on the reviewer's confidence alone.
- Prefer the **hard oracle** wherever it exists: a runnable black-box acceptance test (green/red by code) supersedes any LLM verdict for that flow. LLM verification is corroboration; an executable check is proof. See [test-oracle.md](test-oracle.md).

## The bottom line

Two LLMs (executor + verifier) can share a blind spot, so independent re-execution is **strong corroboration, not a guarantee**. The guardrails above — probe-gate the verifier, surface disagreement instead of averaging it, and filter claims through execution — are what keep "a second model looked at it" from being false confidence.

> Sources: Barr, Harman, McMinn, Shahamiri, Yoo, *The Oracle Problem in Software Testing: A Survey* (IEEE TSE 2015); *Judging Is Not Enumerating: Silent Omissions in LLM-Authored Acceptable Sets* (2026) — omission dominates and gating on a known-correct probe cuts false-rejection from 58–92% to ≤5%; *Necessary but Not Sufficient: Temperature Control and Reproducibility in LLM-as-Judge* (2026) — run epochs >1 and report variance, the only mitigation surviving temperature deprecation; *Are LLMs Reliable Code Reviewers?* (2026) — richer prompts trade false acceptance for over-correction.
