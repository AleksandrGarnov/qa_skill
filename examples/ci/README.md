# CI enforcement example

The plugin's [merge-gate hook](../../hooks/hooks.json) (`finalize-gate.sh`) enforces the QA gates on a
**local** `git merge` / `git push` / `gh pr merge`. That's enough when a developer merges from their
machine, but it does **not** cover:

- merges via the **GitHub merge button** or a CI job (the local hook never fires),
- a merge command **outside the hook's regex**, or issued through a **non-Bash** tool,
- a deleted/absent local run-state.

[`qa-gate.yml`](qa-gate.yml) is a **template** that re-runs the same gate scripts in CI as a required
status check, so a red-gate branch can't be merged regardless of how the merge is triggered. It's the
real answer to "the local hook can be bypassed" — enforcement moves to the branch-protection layer that
the agent doesn't control.

## Setup

1. **Vendor the gate scripts** into your repo (copy `scripts/` from this plugin), or check the plugin
   out in a step before the gate runs. Point `GATES` at that path.
2. **Make the run bundle visible to CI** — commit the `.claude/qa-run.json` run-state and the
   manifest/report (md + json) it references, or adapt the paths to wherever your bundle lives.
3. **Require the check**: Settings → Branches → branch protection → require the `qa-gate` job.

A branch with **no active QA run** passes the job untouched — exactly like the local hook is a no-op
outside a QA run. The gate only bites once `test-iteration` has frozen a manifest for the branch.

> **Validation status:** the `jqr` state-parsing and gate-invocation logic has been run locally against a
> real bundle (a green manifest+report yields `fail=0`; a red gate yields `fail=1`). It has **not** been
> exercised on a live GitHub Actions runner — treat the `.yml` as a validated-logic template and smoke-test
> it in your own pipeline before relying on it as a required check.
