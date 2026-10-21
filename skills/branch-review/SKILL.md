---
name: branch-review
description: Reviews a git branch against its base — code review plus a separate security pass — and returns risk-ranked findings. Works on a bare Claude Code install (no plugins required). Use when you need a focused review of a branch's changes, standalone or as part of a QA cycle.
argument-hint: "[git-branch] [base-branch]"
---

# Branch Review

Reviews the changes on `$ARGUMENTS` (branch, optional base) and returns deduplicated, risk-ranked **code** and **security** findings. Standalone, and also used by `test-iteration`.

## 1. Get the diff (deterministic)

Run the bundled script — do not hand-roll git commands or guess the base:

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/branch-diff.sh" <branch> [base]
```

If `base` is omitted the script auto-detects it (origin/HEAD → develop → main). If it prints `base: UNKNOWN`, read `CLAUDE.md` for the project's base branch or ask the user — do not guess. If `${CLAUDE_PLUGIN_ROOT}` is unset (manual install) or the script is missing, run the equivalent git commands inline (`git fetch`; `git checkout <branch>`; `git diff --name-only origin/<base>...HEAD`).
**Done when:** you have the head commit, the resolved base, and the list of changed files.

## 1.5. Cheap signals first (local, read-only)

Before anyone reads the diff, let the project's **own** deterministic tools do the cheap pass — a type error, a lint error on a changed line, or a red test is high-signal and costs a fraction of a model read. Detect them from the repo (`package.json` scripts, `composer.json`, `pyproject.toml`/`setup.cfg`, `Makefile`, the CI config) — never introduce a tool the project doesn't use, and **never install dependencies** to make one run.

- **Linter / type-checker / static analyzer** — always safe (they don't execute application code). Scope to the changed files where the tool allows it.
- **The project's test suite** — **only when its database/service config is provably local and isolated** (e.g. `phpunit.xml` / `.env.testing` on SQLite `:memory:` or a local test DB, a test container). A suite can migrate, seed, or truncate whatever database it is pointed at; if you can't confirm the target is isolated, **don't run it** — record `tests: skipped — DB target not confirmed isolated`. Never against staging/shared/production, never on a server.
- **Raw output to a file, digest into context.** Write each tool's output to `"${TMPDIR:-/tmp}/qa-signals/<tool>.txt"` and read only a digest — the count plus the offenders **in the changed files** (`grep -F -f <changed-files> … | sort | uniq -c | sort -rn | head`). A full `tsc`/`phpstan`/test dump is thousands of tokens of mostly noise outside the diff.
- **Triage a red test before it becomes a finding** (re-run it once; check whether it touches the changed files or their callers): **flaky** (flips on re-run → note it, per the flaky protocol) · **known-failing** (fails on the base branch too / unrelated to the diff → environment context, not a finding) · **in-scope regression** (deterministic and in the changed code's reach → a `confirmed` finding, `source:signal`).
- A tool that's missing, needs network, or needs a service you don't have → `signals: unavailable — <reason>`, and continue. Signals sharpen the review; their absence never blocks it.

**Done when:** each available tool ran (or is recorded skipped/unavailable with a reason) and its in-diff offenders are listed for step 3.

## 2. Run two passes (in parallel) — tool-agnostic with fallbacks

Pick the first available tool in each chain. **Discover by capability, don't assume a specific plugin is installed** — if the project ships a dedicated reviewer/security plugin, prefer it; otherwise fall through. The last option in each chain works on a bare Claude Code install, so this never silently no-ops.

- **Code review:** an installed specialized code-review skill/plugin, if any → built-in `/code-review` → **a `general-purpose` subagent** prompted to review the diff (always available).
- **Security review:** an installed specialized security-audit skill/plugin, if any → built-in `/security-review` → **a `general-purpose` subagent** prompted to audit the diff for vulnerabilities (always available).

Whatever tool runs, **record which one you used and which tier it came from** (specialized / built-in / subagent) — so a report can't imply a specialized pass ran when only the bare-install fallback did.

**Verification bar:** flag only what affects correctness / requirements / security, each tied to `file:line`. Style nitpicks are optional — don't bloat the output. No overengineering.

**Subagent prompt (when falling back to `general-purpose`):** pass it (a) the changed-files list and diff from step 1, (b) its role (code reviewer OR security auditor — one role per agent), (c) the output format below, (d) the rule "report only correctness/security-relevant findings with `file:line`; if nothing material, say so".

**Done when:** both passes have returned (or are explicitly noted as unavailable).

## 3. Consolidate

Merge the two passes **and the step-1.5 signals**, **deduplicate** overlapping findings, and **risk-rank** each (risk = likelihood × impact, H/M/L). Anchor the axes so H/M/L isn't a gut call (same rubric `test-iteration` uses): **impact** High = money/auth/security/PII/data-loss/core-flow-down; **likelihood** High = on the main path / common input / no workaround / touches changed core logic.

For a finding that is a **concrete defect** (not just a potential risk), also tag a **severity** (ISTQB technical impact — set here by the reviewer): `blocker` (crash/data-loss/core down, no workaround) · `major` (feature broken or awkward workaround) · `minor` (cosmetic/recoverable). Priority (business urgency) is the PO's call, not set here.

**Confirmed vs suspected — never blur the two.** A finding is **`confirmed`** only when something actually produced the wrong behaviour — an in-scope red test or a tool error from step 1.5, or a repro that ran and failed as predicted. Everything inferred from reading the diff is **`suspected`**, however confident the reviewer sounds (an LLM reviewer over-reports — see `test-iteration`'s verifier-reliability reference). A `suspected` finding must still name `file:line` and a concrete failure scenario (input → wrong output); one that can't is speculation — drop it to a note.

**Optional confirmation tier.** If an installed skill can turn a code-level suspicion into a failing repro **without editing the code** (e.g. `qa-bug-hunter`, which writes repro tests only under its own gitignored `qa-bug-hunt/` folder), offer it the `[H]` suspected findings — passing their `file:line` and scenario as the target, so it doesn't re-scan the repo. A finding whose repro fails becomes `confirmed` with the repro path; one whose repro **passes** is downgraded and says so (the code may be right) — never silently dropped. No such skill installed → findings stay `suspected`, and `test-iteration` turns them into runtime checklist items, where staging decides.

**Feed hotspots.** When a high-risk correctness/security finding lands in a component, tag it `hotspot:<area>` — a component that surfaces real findings is where the next bug hides, and a QA cycle (`test-iteration` step 5) up-weights flagged areas.

Output format — one ranked list:

```
[H] sec  | path/api.ts:88  | <vulnerability> | <impact> | confirmed (repro: <path>) | sev:major | hotspot:auth
[M] code | path/file.ts:42 | <issue> | <why it matters> | confirmed (source:signal phpstan) | sev:minor
[M] code | path/calc.ts:17 | <issue> | <input → wrong output> | suspected
```

(Every line carries `confirmed (<what proved it>)` or `suspected`. `sev:` only for confirmed defects; omit for suspected risks. `hotspot:` only for high-risk findings.)

Also report the **signals line**: which tools ran, what was skipped/unavailable and why, and any known-failing/flaky tests set aside as environment context.

**Done when:** you return a single deduplicated, risk-ranked list — every finding labelled `confirmed` (with what proved it) or `suspected`, each confirmed defect carrying a severity, high-risk areas flagged as hotspots — noting which tools produced it (and any pass that was unavailable).
