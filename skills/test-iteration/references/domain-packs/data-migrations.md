# Pack — Schema & data migrations

Pull when the diff adds or changes a **migration**, a schema/model definition, a backfill/data-fix command, or code that reads a column/table another migration touches. Migration bugs rarely show on a fresh staging DB: they live in the **overlap window** (old code and new schema running at the same time during a rolling deploy), in **existing rows** the new code didn't create, and in **table size**. Happy path = "migrate ran, page loads" — that's the item this pack exists to go beyond.

**How each item is verified** (the skill's boundaries apply — non-prod only, no files on the server):
- `[live]` — observed through the product on staging (API/UI), on data that **pre-dates** the migration as well as fresh data.
- `[read]` — a supporting read: the migration file, `migrate --pretend` / the SQL plan on a **local** DB, `migrate:status`, a read-only query on non-prod.
- `[needs-OK]` — mutates a shared environment (running a rollback / re-running a migration on staging). Ask the user explicitly before doing it; without a yes it's `blocked`, never assumed.

## Compatibility across the deploy window
- [ ] `[read]` **Old code vs new schema:** nothing the *currently deployed* code reads or writes is dropped, renamed, retyped, or made NOT NULL in the same release — a rename/drop/type change is split into expand → (deploy) → contract, not done in one step
- [ ] `[live]` **Old rows through new code:** records created *before* the migration (seed one on the base build, or pick existing non-prod rows) read, update, list, and export correctly — nulls/defaults in the new column don't 500, hide, or mis-total them
- [ ] `[live]` **New rows through old paths:** anything still on the old code path (another service, a queued job serialized before deploy, a cached payload, a mobile client) tolerates rows written in the new shape
- [ ] `[read]` A new **NOT NULL / unique / foreign key** constraint is consistent with existing data — the migration either backfills first or would fail on real rows (check for violating rows on non-prod with a read-only count)

## Backfill & data fixes
- [ ] `[live]` After the backfill: **row counts and null counts** match expectation (`count(*) where new_col is null` = 0, or = the documented remainder) and the API shows the backfilled values
- [ ] `[read]` Backfill is **batched** (no single `UPDATE` over the whole table) and **re-runnable** — running it twice doesn't double-apply (amounts, counters, appended text)
- [ ] `[live]` New code handles a **partially backfilled** table (some rows done, some not) — the window between deploy and backfill completion is real

## Locks, size, and duration
- [ ] `[read]` Index creation on a large/hot table is online (`CONCURRENTLY` / online DDL / the framework's equivalent); no table rewrite (type change, volatile default) on a table that's big in production
- [ ] `[read]` Migration duration on **production-sized** data is known or estimated (staging timing × row-count ratio) — "2 s on staging" on 10k rows is not evidence for 200M rows; if unknown, say so in the report as a risk

## Rollback & re-run
- [ ] `[read]` A `down()` / reverse migration exists and actually reverses this change (not empty, not a different change); a destructive step is called out as irreversible with a backup/restore note
- [ ] `[needs-OK]` Rollback on staging → the **previous** build still works against the rolled-back schema, and data written by the new build in between survives (or the loss is documented)
- [ ] `[read]` Migration is **idempotent on re-run** / guarded (`if not exists`), and its filename/ordering doesn't collide with another branch's migration

## Deploy hygiene
- [ ] `[read]` Migrations run in the deploy pipeline before the code that needs them (or the code tolerates both states); `migrate:status` on staging shows nothing pending after deploy
- [ ] `[live]` Caches/serialized models that embed the old shape are invalidated or tolerate it (see [performance](performance.md) → Caching)

> Sources: expand/contract (parallel change) and mixed-version compatibility — Bytebase, *Database Blue-Green Deployment* (2026); technicalqa.com, *Database Migration Testing for Expand-Contract Releases* (2026) — old app × expanded schema, partial backfill, rollback after expand; qatronic.com, *Zero-Downtime Schema Migration Testing Guide* (2026) — production-sized duration, lock behaviour under load, the four overlap-window scenarios; Harbor Software, *Database Migrations in Production* (2023) — CONCURRENTLY, batched backfill, tested rollback; Infraveil, *Zero-downtime database migrations*.
