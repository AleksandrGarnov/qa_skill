# Pack — Background jobs, queues & scheduled tasks

Pull when the diff adds or changes a **queued job, event listener/consumer, scheduled (cron) task, or anything dispatched "later"** — including side effects moved off the request path (emails, webhooks out, charges, exports, sync to a third party). Most queues deliver **at least once**: a job can run twice, run late, run out of order, or run against a record that changed (or vanished) since it was dispatched. The request returned `200`; the bug is in what happens after.

**Test method.** Trigger the job through the **real entry point** (the user action / API call that dispatches it) on staging, then **observe the durable effect** — the record, the ledger line, the email in the staging inbox/mail catcher, the outbound webhook in its receiver — after the worker has run. Reading job state (failed-jobs table, Horizon/queue dashboard, worker logs) on non-prod is a supporting read. Forcing a worker failure or a redelivery on a shared staging is a server-side action: ask the user first, or use the product's own replay/retry control if it has one.

## Delivery & idempotency
- [ ] **Runs twice → one effect.** Re-dispatch / replay the same job (or retry it from the failed-jobs UI) → one email, one charge, one record, one outbound webhook — not two (observe the effect, not the job count). Techniques: [concurrency-techniques.md](../concurrency-techniques.md) → retry/redelivery
- [ ] **Two workers, same job, same moment** (a burst of the dispatching action, or a job slower than its visibility/lease timeout) → still one effect; the job's own duration fits inside the queue's timeout/`retry_after`
- [ ] Dedup keys / unique jobs, if used, really collapse duplicates (dispatch the same logical work twice → one run)

## Dispatch timing & data
- [ ] **Dispatched after commit.** A job dispatched inside a DB transaction doesn't run before the commit (→ "record not found" / reads stale state) and doesn't run at all if the transaction rolls back (`afterCommit` or equivalent)
- [ ] Job payload carries **ids, not stale snapshots** — the job acts on the record's state at run time; if the record was changed or deleted between dispatch and run, the job handles it (skips, re-reads, or fails cleanly — not a crash loop)
- [ ] Jobs serialized by the **previous build** (already in the queue at deploy time) still run on the new code, or the change says why not

## Failure, retry & dead letters
- [ ] **Transient failure → bounded retries with backoff**, then success (dependency briefly unavailable → the job completes later; attempts counted)
- [ ] **Permanent failure → stops and lands in failed jobs / DLQ** after the max attempts with the error and payload recorded — no infinite retry, no silent drop
- [ ] A **poison payload** (malformed / references a missing record) fails fast and doesn't block the rest of the queue
- [ ] A **partially applied** job (failed after its first side effect) doesn't repeat that side effect on retry — the classic double email / double charge
- [ ] Failed-job **replay** is safe: replaying from the failed list goes through the same idempotency protection

## Ordering & scheduling
- [ ] Jobs that depend on order (`created` before `updated`, `payment` before `refund`) handle the reverse order per the documented behaviour — queued, ignored, or reconciled, never a wrong final state
- [ ] **Scheduled tasks:** run once per schedule even with multiple app servers (`onOneServer` / lock), don't overlap a still-running previous run (`withoutOverlapping`), and use the intended timezone; the task appears in the scheduler listing on staging
- [ ] Long-running / batch jobs: progress survives a worker restart (chunked, resumable), and a timeout leaves no half-written batch

## Observability
- [ ] A failing job leaves enough to act on — logged error with the job id / record id, visible in the failed list or monitoring; the user-facing state reflects the failure (not "processing" forever)

> Sources: AWS SQS (at-least-once delivery, visibility timeout, redrive/`maxReceiveCount` to a DLQ); Microsoft background-jobs guidance (duplicate and out-of-order delivery, permanent-vs-transient failure → dead-letter) as summarised in Ideabat, *Background Jobs & Queues: Retries, Idempotency & DLQ* (2026); MinimumCD, *Event Consumer* testing pattern (duplicate, out-of-order, poison, mid-batch failure); QAPractices, *Background Job Queue Test Cases* (retry, idempotency on retry, max retries, DLQ, timeout, dedup, poison); Laravel queue docs (`afterCommit`, `retry_after` vs job timeout, unique jobs) and scheduler (`onOneServer`, `withoutOverlapping`).
