# Pack — Performance & resource bounds

Pull when the change touches a **list / search / export endpoint**, a new query or join, a loop over related records, a cache, a background job over a collection, or anything that takes **user-sized input** (bulk ids, cart lines, CSV rows). A performance bug is still a bug — it just hides on a 10-row staging table and fires on production volume. Only file what a user or the infrastructure bill would actually feel; an unmeasurable micro-inefficiency is noise, not a finding.

**Test method — count, don't time.** Wall-clock on a shared staging is noisy, so prefer a **count that doesn't flake**:
1. **Rows returned / page size** — read straight off the API response.
2. **Query or call count**, where the framework already exposes it on non-prod (a debug toolbar / Telescope / query log you can *read*) — a supporting read, never a probe you deploy.
3. **Input doubling** — run the same request on a fresh subject seeded with **n** and **2n** related records / input items (via the API). Work that grows ~2× is linear; ~4× is quadratic; growth on a *fixed page size* is an N+1.
4. Wall-clock only as a last resort: median of ≥5 runs, a generous bound, and the note "environment-sensitive".

## Data access & pagination
- [ ] **N+1:** a fixed page (say 20 rows) for a subject with 1 vs 50 related records each → query count flat (or, black-box, latency not ~proportional to the related count)
- [ ] **Page size is capped server-side:** `limit=100000` / `per_page=10000` / `page_size=-1` → capped or rejected, never the whole table (observe the returned count) — OWASP API4
- [ ] Pagination params **reach the query**: page 2 ≠ page 1, `total` stable across pages, a default page size applies when none is sent
- [ ] A **deep page** (`page=last`, large offset) on realistic volume stays in bound (OFFSET scans every prior row)
- [ ] **Export / report** over a large set streams or runs as an async job with a bounded size — it doesn't time out the request or load everything into memory

## Input size & accidental complexity
- [ ] **Doubling user-sized input** (bulk ids, cart lines, CSV rows, nested items) → work grows ~2×, not ~4× (a linear scan inside a loop, re-sorting per item)
- [ ] Oversized body / huge array / deeply nested JSON → rejected fast (`413`/`422`), not a hang, a `500`, or a worker timeout
- [ ] **Bulk endpoints cap the batch** (max ids per request) and say so in the error

## Caching
- [ ] **Invalidated on write:** update, then read through every surface that caches it → fresh value, no stale-cache-as-truth
- [ ] **Cache key includes everything that varies the response** (user / tenant / locale / currency / role) → no cross-user bleed (see [authorization-tenancy](authorization-tenancy.md))
- [ ] Cache is bounded (TTL / eviction) — usually a code-read plus the observed TTL header; an unbounded cache is a slow memory leak

## Downstream calls & timeouts
- [ ] A **slow or hanging third party** (sandbox delay, unreachable host on staging) → the request times out and degrades with a defined error; it doesn't hold the worker
- [ ] Independent downstream calls in one handler aren't serialized (latency ≈ n × RTT) — observe the call count vs the total time
- [ ] Retries have a cap and backoff — no retry storm on a failing dependency

## Frontend (when the change renders data)
- [ ] The changed screen doesn't fire a **request waterfall or duplicate fetch on mount** (network panel: count the calls for one view)
- [ ] A long list with realistic volume stays responsive (paginated or virtualized), no multi-second freeze

> Severity = reach × growth: an O(n²) on a path capped at n=10 is minor; an N+1 on every load of a core screen is major even though each query is fast. If the fix trades memory for speed, say so — that trade-off is the team's call.

> Sources: OWASP **API Security Top 10 2023 — API4 Unrestricted Resource Consumption** (cap pagination/page size, payload size, batch size); OWASP API Security Testing Framework guidelines (burst/limit probes, scope load on shared infra); `qa-bug-hunter` performance-bug-patterns (MIT — "confirm by counting, not timing", input-doubling for complexity).
