# Concurrency & retry techniques — making a race actually land

Step 4.5 lists "concurrent action in the window between two steps", "duplicate / out-of-order", and "retry mid-run" as attacks. Naming the attack is the easy part: a race sent as two sequential requests almost never lands, and an attack that didn't land proves nothing about the window. This reference is the **how** — black-box, through the real API on staging, so a suspected race either becomes a reproducing red test or a documented not-landed hardening check.

## When to reach for it
Any change on a **check-then-act** path: a single-use or limited allowance (coupon, balance, seat, invite, OTP, free tier), a create/charge/transfer/refund, an idempotency-keyed write, a state transition two actors can trigger, a webhook/queue consumer that can be redelivered. For a money/state change at least one technique below is expected in the `### Adversarial` block; "not applicable" needs the reason (no shared record, nothing to double-spend).

## Ground rules (they follow from the skill's principles — not new policy)
- **Staging only, fresh subject per attack** — a new user/wallet/coupon each run ([test-data-management.md](test-data-management.md)), so a landed race on attempt 3 isn't contaminated by attempts 1–2.
- **Through the real entry point.** Parallel *client* requests against the API. Never patch, slow down, or instrument the server to force an interleaving — no deployed probe, no injected delay; that's the "never put a file on the server" boundary.
- **Assert on the resulting state, never on status codes.** A race usually returns `200` to every request while the record underneath is wrong (two redemptions, two ledger lines). Read the state back after the burst — via the API, or a non-prod read for the producing leg — and quote it.
- **Bounded bursts.** 20–30 requests per burst is enough to absorb server-side jitter; more is load testing, not race testing. Rate-limit probes on a shared staging are announced, not fired blind.
- **Credentials from the environment** (`$TOKEN`), never inlined in the script or quoted in the report.

## 0. Benchmark sequentially first
Send the same N requests **one after another** and record the state. This is the contrast that separates a real race from a business-logic bug: sequential → limit holds; parallel → limit breaks = race. Sequential already breaks it → it's a plain logic defect, file it as such.

## 1. Parallel burst — limit overrun / double spend
Fire N identical requests released together at one record, then read the state.
```bash
# burst: N parallel identical requests, status distribution only (no body/token in output)
N=20
seq "$N" | xargs -P "$N" -I{} curl -s -o /dev/null -w '%{http_code}\n' \
  -X POST "$STAGE/api/coupons/redeem" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"code":"'"$FRESH_CODE"'"}' | sort | uniq -c
# state: how many redemptions actually landed?
curl -s "$STAGE/api/coupons/$FRESH_CODE" -H "Authorization: Bearer $TOKEN"
```
Start at **N=2** (a missing unique constraint or idempotency check usually fails immediately), then raise to **20–30** for a narrow read-then-write window. Where the server speaks HTTP/2, multiplexing the burst over one connection (`curl --http2 --parallel --parallel-immediate`, `httpx`/`asyncio.gather`, k6) tightens arrival far more than separate connections — network jitter is what hides narrow windows. Expected = exactly one effect (one redemption, one debit, balance never below zero).

## 2. Multi-endpoint / state-transition race
Two *different* operations on the same record, in parallel: `confirm` + `cancel`, `capture` + `refund`, `accept-invite ×N` on a single-seat invite, `status A→B` + `A→C`, withdraw from two sessions of the same user. Expected = the record ends in exactly one legal state of the state machine ([test-design-techniques.md](test-design-techniques.md) state-transition), with side effects consistent with that state — not "cancelled but also shipped".

## 3. Idempotency key — four replays, four different correct answers
For any write documented as idempotent (`Idempotency-Key` header or equivalent), the key reused four ways is four separate contracts; a suite that only checks the first has one test wearing four names:

| Replay | Expected (IETF `Idempotency-Key` draft semantics; follow the API's own docs where they differ) |
|---|---|
| same key, same body, **after** the first completed | the original response replayed; **one** durable effect |
| same key, **different** body | rejected (draft: `422`) — the dangerous wrong answer is `2xx` with the *original* amount |
| same key, same body, **while the first is in flight** (burst of 2–16) | one effect; losers get `409` (draft) or wait and receive the replay |
| documented-idempotent op, **no** key | rejected (draft: `400`) if the API requires it |

Count the durable effect (ledger lines, created records, emails/webhooks emitted), not the response ids.

## 4. Retry after an ambiguous timeout
The duplicate that reaches production is rarely the sequential double-submit — it's the client that gave up just before the server committed, then retried. Reproduce the ambiguity from the client side: call with a timeout shorter than the server's processing (`curl --max-time 1` on a slow write), confirm server-side that the write landed anyway, then **retry the same request** exactly as the client would. Expected = one effect. For webhooks/queues: re-deliver the **same event id** (gateway sandbox "resend", or replaying the captured payload to the staging endpoint with a valid signature) — one fulfilment, one stock move, one email.

## 5. Rate limits are races too
A limit is check-then-act: fire one burst inside a single window at login / OTP / password-reset / payment and count how many succeed versus the documented limit. More successes than the limit = finding (OWASP API4/API6), independent of whether `429` ever appears.

## Repeat, record the rate, and decide
- Run each burst **3–5 times** on fresh subjects. Races are probabilistic.
- **Landed even once → `fail`, not `flaky`.** The wrong state was observed; record the rate (`landed 2/5 bursts, N=20`) and say plainly the repro is not deterministic. ([flaky-protocol.md](flaky-protocol.md) is for checks whose *own* outcome is unreliable — an intermittent race is a real defect with an observed rate.)
- **Never landed → a not-landed hardening item** in `### Adversarial`, recording the technique, N, burst count, and what was observed instead. That record is what makes "couldn't break it" credible — and keeps the check alive for the next build.
- **Report fields:** *How run* = the exact burst script (token via env); *Actual* = state before → after plus the status distribution (`201×1, 409×19` / `200×20, redemptions=3`). Repro steps for a landed race are the script, not clicks — a race is rarely reproducible by hand, and the bug block says so.

> Sources: PortSwigger Web Security Academy, *Race conditions* (limit overrun, multi-endpoint, benchmark-then-parallel methodology); James Kettle, *Smashing the state machine* (2023) and *The single-packet attack* (20–30 requests to absorb server-side jitter; HTTP/2 to remove network jitter); IETF HTTPAPI *The Idempotency-Key HTTP Header Field* draft (400 / 409 / 422 semantics); OWASP API Security Top 10 2023 (API4 Unrestricted Resource Consumption, API6 Unrestricted Access to Sensitive Business Flows); practitioner idempotency-testing guides (automationtester.in, *Test API Idempotency Under Retries and Timeouts*, 2026; technicalqa.com, 2026) — "count the durable effect, not the response".
