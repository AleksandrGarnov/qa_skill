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

## 2. Run two passes (in parallel) — tool-agnostic with fallbacks

Pick the first available tool in each chain. **Discover by capability, don't assume a specific plugin is installed** — if the project ships a dedicated reviewer/security plugin, prefer it; otherwise fall through. The last option in each chain works on a bare Claude Code install, so this never silently no-ops.

- **Code review:** an installed specialized code-review skill/plugin, if any → built-in `/code-review` → **a `general-purpose` subagent** prompted to review the diff (always available).
- **Security review:** an installed specialized security-audit skill/plugin, if any → built-in `/security-review` → **a `general-purpose` subagent** prompted to audit the diff for vulnerabilities (always available).

Whatever tool runs, **record which one you used and which tier it came from** (specialized / built-in / subagent) — so a report can't imply a specialized pass ran when only the bare-install fallback did.

**Verification bar:** flag only what affects correctness / requirements / security, each tied to `file:line`. Style nitpicks are optional — don't bloat the output. No overengineering.

**Subagent prompt (when falling back to `general-purpose`):** pass it (a) the changed-files list and diff from step 1, (b) its role (code reviewer OR security auditor — one role per agent), (c) the output format below, (d) the rule "report only correctness/security-relevant findings with `file:line`; if nothing material, say so".

**Done when:** both passes have returned (or are explicitly noted as unavailable).

## 3. Consolidate

Merge the two passes, **deduplicate** overlapping findings, and **risk-rank** each (risk = likelihood × impact, H/M/L). Anchor the axes so H/M/L isn't a gut call (same rubric `test-iteration` uses): **impact** High = money/auth/security/PII/data-loss/core-flow-down; **likelihood** High = on the main path / common input / no workaround / touches changed core logic.

For a finding that is a **concrete defect** (not just a potential risk), also tag a **severity** (ISTQB technical impact — set here by the reviewer): `blocker` (crash/data-loss/core down, no workaround) · `major` (feature broken or awkward workaround) · `minor` (cosmetic/recoverable). Priority (business urgency) is the PO's call, not set here.

**Feed hotspots.** When a high-risk correctness/security finding lands in a component, tag it `hotspot:<area>` — a component that surfaces real findings is where the next bug hides, and a QA cycle (`test-iteration` step 5) up-weights flagged areas.

Output format — one ranked list:

```
[H] sec  | path/api.ts:88  | <vulnerability> | <impact> | sev:major | hotspot:auth
[M] code | path/file.ts:42 | <issue> | <why it matters> | sev:minor
```

(`sev:` only for confirmed defects; omit for speculative risks. `hotspot:` only for high-risk findings.)

**Done when:** you return a single deduplicated, risk-ranked list — each defect carrying a severity, high-risk areas flagged as hotspots — noting which tools produced it (and any pass that was unavailable).
