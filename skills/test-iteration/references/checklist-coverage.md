# Reference — checklist coverage: right-sizing, lenses, risk, result buckets

The single checklist is the **manifest** ([checklist-manifest-template.md](checklist-manifest-template.md)) — every check is one row in its `## Items` table, journey-rooted and technique-tagged. This doc is the **drafting aid**: how to right-size the run, which coverage *lenses* to sweep so no area is forgotten, how to score risk, and how to bucket a result. The lenses are not separate tables — they are areas you make sure `## Items` covers.

## 1. Right-size the run (Scope & tailoring)

Depth must match the change. A one-line CSS tweak doesn't earn a concurrency pass; a payment change earns all of it. Select coverage by what the **diff actually touches** (the `scale:` line from `branch-diff.sh` + the `changed-surfaces.sh` list) and the risk.

- **Cover a lens** when the diff touches its concern (UI changed → UX/UI; endpoint/query → Performance + negative; auth/payment/PII → security + full negative).
- **A skipped lens is a recorded decision, not a silent gap** — note it (e.g. "Performance — N/A: copy-only, no runtime path").
- **Smoke + Regression are never skipped** — even a copy change can break a build or an adjacent view.
- **Pull a domain pack** when the change touches a known domain ([domain-packs/](domain-packs/)): payments, auth-sessions, forms, file-upload, search, i18n-l10n. Fold in the relevant items; drop the rest as `N/A`.
- More blast-radius → more feature-specific items on top of the standard sweep.

| Change shape | Typically cover | Typically N/A |
|--------------|-----------------|---------------|
| Copy / CSS-only | Smoke, UX/UI (visual), Regression | Performance (runtime), negative-API, security |
| Pure backend / API | Smoke, Functional, negative, Performance (API), Regression | UX/UI |
| Full feature (UI + API) | All lenses | — |
| Config / infra flag | Smoke, Functional (both flag states), Regression | UX/UI, negative-input |

## 2. Coverage lenses (sweep each applicable one into `## Items`)

Each lens is a set of questions; every check it yields becomes a journey-rooted row. Order the dangerous ones **first**.

- **Smoke (critical path)** — the critical-path actions work at all. Never skipped.
- **Adversarial / failure-mode (run FIRST)** — from the step-4.5 pass: concurrency/in-the-window, stale snapshot/cache as truth, negative/boundary/zero, compensation/retry mid-run, out-of-order/duplicate/partial-failure. **Mandatory for any money/state change** — none = coverage gap = NO-GO.
- **Functional** — one check per changed branch/flag/state and per acceptance criterion.
- **Risks from code review / security review** — each `branch-review` finding (and `hotspot:`) → a check; highest risk first.
- **Edge / negative** — ~80% of bugs live here. Standard set per input/endpoint: null/empty; special chars `' " < > & ; %`; unicode/emoji/RTL; wrong type; BVA min−1/min/max/max+1; injection via devtools/direct API (bypass UI); double-submit; network failure (offline/timeout/drop mid-request). Then feature-specific rows. (Pick values with [test-design-techniques.md](test-design-techniques.md).)
- **UX/UI** (any surface a user sees) — responsive at 320/375/768/1024/1440; visual consistency vs design system; hover/focus/active/disabled states; loading/empty/success/error feedback; accessibility.
  - *How to measure:* responsive → DevTools device toolbar; a11y → axe / Lighthouse a11y + a manual keyboard pass (Tab/Shift-Tab/Enter/Esc); contrast → DevTools contrast checker; motion → emulate `prefers-reduced-motion: reduce`.
- **Performance** (if a runtime path changed) — page/view load, API time on changed endpoints, no layout shift, behaviour under load/concurrency. Record the **measured number**, not "feels fast". Web targets: LCP < 2.5s, INP < 200ms, CLS < 0.1, FCP < 1.5s.
  - *How to measure:* CWV → Lighthouse/PageSpeed; INP → DevTools Performance; API time → DevTools Network or `curl -w "%{time_total}\n" -o /dev/null -s <url>`; load → `k6`/`ab` only where warranted.
- **Regression** — adjacent functionality that could break; seed it from `blast-radius.sh` (callers of the changed code).

## 3. Risk rubric (so H/M/L isn't a gut call)

Risk = **impact × likelihood**. Anchor each axis, then combine (High on either axis with Medium+ on the other → H).

| | High | Medium | Low |
|---|------|--------|-----|
| **Impact** | money, auth, security, PII, data loss/corruption, blocks the core flow | wrong-but-recoverable, degraded UX, workaround exists | cosmetic, copy, non-blocking edge |
| **Likelihood** | main path, common input, no workaround, touches changed core logic | secondary path, specific-but-realistic input, partial mitigation | rare/contrived input, hard-to-hit timing, far from the change |

## 4. Result buckets (at execution, step 8/9)

Bucket each item **pass / fail / blocked / flaky / N/A (reason) / not executed**:

- **blocked** — an applicable check you *couldn't* run (a gap), after a documented real attempt — not `not executed`.
- **flaky** — flips pass/fail on the same build (a gap — see [flaky-protocol.md](flaky-protocol.md)), not a `pass`.
- **N/A** — out of scope for this change, with a reason.
- Never let a real check silently evaporate; `verify-coverage.sh` rejects any approved item that has no terminal bucket.
