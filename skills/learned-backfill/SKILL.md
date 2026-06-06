---
name: learned-backfill
description: One-shot backfill of the learned-checks store from the project's existing QA reports. Mines past "Found bugs" across all reports, curates the recurring / GO-escaped ones into reusable checks, and (after you approve) seeds learned-checks.md so future runs start from accumulated experience instead of a blank slate. Use to "learn from old data" once, before relying on the going-forward loop.
argument-hint: "[test-docs-path]"
---

# Learned-checks backfill

Seeds the project's [learned-checks store](../test-iteration/references/learned-checks.md) from the
**history that already exists** — so the learning loop ([[learned-checks]]) doesn't have to start empty.
This is **in-context curation of past outcomes**, not model training: mechanical extraction → your
judgement on what generalises → append. Run it **once** per project; the going-forward loop (test-iteration
steps 5/12) continues it.

## 1. Resolve the corpus
Test-docs path = `$ARGUMENTS` if given, else read it from the project's `CLAUDE.md` (the same path
`test-iteration` stores reports in). If neither yields a path, **stop and ask** — don't guess.
**Done when:** you have a real directory of past reports.

## 2. Scan (mechanical — don't open every file by hand)
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" scan <test-docs-path>
```
This lists `<report-file>` ⇥ `<bug heading>` for every bug in every report's `## Found bugs` section.
`NONE` = no template-format reports found; fall back to reading the docs yourself for older formats.
**Done when:** you have the raw candidate list (or know there's nothing to mine).

## 3. Curate — keep only what generalises (this is the whole point)
A backfill is a **seed, not gospel**. From the candidates, keep the **high-signal** ones; drop one-offs:
- **Recurring** — the same component / failure mode appears across **≥2 reports** (group by the `[Feature]`
  tag and the bug text). A repeat is a standing weakness, not bad luck.
- **GO-escapes** — bugs that surfaced after a GO build (cross-reference `escaped-defects.md` if present);
  these are the most valuable, by definition the process missed them.
- **Money / state / auth / data-loss** components — weight these up even on a single occurrence.
For each kept candidate, write a **reusable check** — phrased as what to verify next time, not the bug
text — plus the component and the "why" (the report/escape that taught it). Skip cosmetic / one-off /
environment-specific findings.
**Done when:** a short, curated list of `component | check | why` rows (high-signal only — fewer is better).

## 4. Approve — PAUSE (user required)
Show the user the proposed rows (and what you dropped, in one line). The store is a **curated artifact** —
**wait for "ok" or edits before writing.** Don't append on your own.
**Done when:** the user approved (or trimmed) the list.

## 5. Append
For each approved row:
```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/learned-checks.sh" add <test-docs-path>/learned-checks.md "<component>" "<check>" "<why>"
```
Then show the final store (`learned-checks.sh list`) and the count added.
**Done when:** `learned-checks.md` holds the approved rows; report `added N from M reports scanned`.

> After this, nothing else to do — `test-iteration` step 5 (`match`) pulls these into every relevant
> future checklist, and step 12 keeps growing the store from new outcomes.
