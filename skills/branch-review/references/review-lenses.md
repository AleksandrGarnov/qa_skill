# Review lenses

Checklists handed to a `general-purpose` reviewer subagent (branch-review step 2). Pick the lenses the
diff actually touches — **applicability first**: a lens with no matching code is marked `n/a`, never forced
into a finding. A lens line is a place to look, not a finding; a finding still needs `file:line`, a trigger,
and the evidence step 3 asks for.

## Always (code pass)

**Silent failure** — an error turned into something that looks like success.
- Empty `catch`/`except: pass`/`rescue` with no body; `.catch(() => {})`; Go `_ = err` / empty `if err != nil {}`.
- Log-and-continue: the error is logged, then execution proceeds as if the operation succeeded.
- Returning `null` / `[]` / `0` / `false` from a catch, so the caller can't tell "empty" from "failed".
- `??` / `||` / `dict.get(k, default)` / `switch` default that masks an unknown variant or a real failure.
- Fallback to another provider / tier / cached value with no signal to the caller (silent downgrade).
- Retry that exhausts attempts and returns normally; timeout or rollback path that isn't observable.
- Resource left open on the error path (no `finally` / `with` / `defer`); cause dropped when re-wrapping.
- OK when the code says why (a comment in or above the catch) or the contract defines the neutral value.

**Tests in the diff** (changed or added test files — review them as executable code).
- An assertion that passes on a wrong result (asserts the mock, asserts truthiness of a non-empty error object, snapshot of a broken state).
- Async assertion without `await`/`return` (`expect(p).resolves…`, un-awaited `assertThrows`) — it can't fail.
- Changed behaviour with no negative / boundary case; a helper test standing in for the real entry point.
- Missing coverage is a **coverage gap**, not a defect — unless it masks a separately shown defect.

**Boundary sweep** — only when caller-controlled or variable-size input drives the change.
- Input with no upper bound reaching a whole-buffer copy, a parse/decode that expands (zip, base64, JSON depth), or an unbounded loop.
- Regex on user input with nested quantifiers (catastrophic backtracking / ReDoS).
- URL- or route-driven behaviour: compare direct load with client-side navigation; vary path, query, hash, locale and trailing slash **one at a time**; check that dependent state/metadata refreshes on a query-only change.
- Pagination / cursor that may never terminate or re-reads the same page; an early `return` that skips a required side effect.

## By stack (only for the stacks in the diff)

- **TypeScript** — `as T` / `!` are compile-time only: untrusted query/body/header cast to a closed union or enum with no runtime validator on that route is a contract bypass. Narrowing of `null`/`undefined` and discriminated unions; exhaustive `switch`; async rejection and cancellation propagate.
- **React** — hook dependency lists and stale closures; effect cleanup and async races (response for an old id lands after the id changed); state reset when the resource identity changes; controlled vs uncontrolled props; accessibility of changed interactive elements.
- **Ruby** — nil/false truthiness; bang methods that return `nil` when nothing changed (`gsub!`, `uniq!`); `rescue`/`ensure` scope; identify the real ORM from the repo (ActiveRecord: query composition, eager loading, callback/transaction order; Sequel: dataset materialization). Sidekiq: argument serialization, retry idempotency.
- **Python** — `None` vs falsy (`0`, `""`, `[]`); mutable default arguments; `asyncio` cancellation/timeout and cleanup; broad `except Exception` hiding a different error; model validation/serialization at the boundary.
- **Mobile (React Native / native)** — app lifecycle (background/resume), deep links and navigation state, permission denial paths, native-module/bridge contracts, iOS/Android divergence. JS/unit evidence doesn't prove device behaviour — say so.

## Security pass

Authentication, authorization (object-level: can user A reach B's record by id?), input validation,
secrets and sensitive data in logs/responses, webhooks (signature, replay), payments, dependency changes.
A security finding on a fallback that swallows an auth/permission error belongs to both lenses — report it once.
