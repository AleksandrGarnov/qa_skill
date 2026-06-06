# Pack — Payments

Pull when the change touches charge/capture/refund/payout, the transaction state machine, or gateway webhooks. Payment flows are **state machines**, and most suites test only `success` — the bugs live in retries, async webhooks, and refunds. Almost every item here is `runtime` → close it on an **observed ledger/state line**, never on a green mocked test.

## State machine
- [ ] Every transition is reachable and correct: `initiated → processing → authorized → captured → settled`, plus `failed / reversed / refunded / partially-refunded / disputed / expired` → state persists, no zombie `processing`
- [ ] Timeout while `processing` → resolves to a defined state (not stuck), can be safely re-initiated
- [ ] Partial settlement / split → unsettled portion is queued/returned, never silently dropped

## Idempotency & retries
- [ ] Same `Idempotency-Key` resubmitted after a client timeout → returns the original result, **no second charge** (observe: one ledger entry, not two)
- [ ] Idempotency-key collision (two *different* requests, same key) → surfaced as an error, not a silent wrong-charge
- [ ] **Processor-side** retry of a request you already processed → handled as a duplicate, not a new charge

## Webhooks (async — assume delayed, duplicated, out-of-order)
- [ ] Same event delivered twice (handler returns 5xx then gateway retries) → **idempotent on event-id**: one fulfilment, one inventory move, one email
- [ ] Refund webhook arrives **before** its payment webhook → queued/handled gracefully, not crashed
- [ ] Invalid webhook signature → rejected
- [ ] Webhook delivery within SLA after a state change (observe latency)

## Refunds
- [ ] Multiple partial refunds against one transaction → cumulative amount tracked, can't exceed the original
- [ ] Refund against an already fully-refunded transaction → fails with a clear error
- [ ] Refund preserves original transaction id, merchant reference, reason code

## Money & auth
- [ ] Currency-conversion rounding: fractional cents/paise accumulate correctly across transactions
- [ ] 3DS2 / SCA: both frictionless and challenge flows complete; declined challenge → no charge
- [ ] Declines covered: insufficient funds, expired card, AVS mismatch, CVV mismatch → correct state + message
- [ ] Reconciliation: gateway ledger == your internal ledger (0 discrepancy)

> Sources: DeviQA payment-gateway/transaction-accuracy testing; Vellix fintech payment edge cases; OlloPay integration checklist.
