# Evals — does the skill prose still make the model behave?

> **Maintainer assets, not plugin behaviour.** No skill references `evals/`, nothing here runs during a
> user's QA run, and deleting the folder changes nothing for users.

`scripts/tests/` proves the deterministic gate **scripts** are correct. It proves nothing about the
**prose** in `skills/*/SKILL.md` — and that prose is where routing, "fix nothing", and "don't hijack a
plain fix request" live. A wording edit can silently break any of them. These evals catch that.

## Two layers

### 1. Structural — free, every push (CI runs it)

```bash
bash evals/check-structure.sh      # prints STRUCTURE-OK or the violations; exit 1 on any
```

- every relative `.md` link inside `skills/` resolves;
- no **orphan** reference: every file under `skills/*/references/` is mentioned by a skill, script, or
  the README (a reference nothing points at is guidance the model is never sent to);
- every eval scenario is fully wired.

### 2. Behavioral — spends tokens, run by hand

```bash
evals/run.sh                     # all scenarios (~$0.75 total on Sonnet)
evals/run.sh --only 02           # one scenario
evals/run.sh --repeat 5          # N runs each; passes only at N/N
evals/run.sh --model opus --budget 2.00 --keep
```

Each scenario copies `fixture/` to a temp dir, runs its optional `setup.sh` (e.g. builds a git history
behind a local bare `origin`, because `branch-diff.sh` diffs against `origin/<base>`), snapshots file
hashes, runs **one headless session** with this plugin loaded (`claude --print --plugin-dir`,
permissions bypassed inside the throwaway copy, spend capped by `--max-budget-usd`), then runs
`check.sh`. Assertions are mechanical:

- **Skill activation from the event stream** (`assert_skill_invoked` / `refute_skill_invoked`) — "the
  skill never loaded" and "it loaded, then misbehaved" are different bugs; only the tool calls tell
  them apart.
- **File hashes** (`assert_source_unchanged` / `assert_file_changed`) — what the run actually did to
  the tree, not what it says it did.

The session also loads your user-level settings and any other installed plugins — deliberately: routing
has to win in the environment it ships into (e.g. alongside another QA plugin), not in a clean room.

**When to run:** after any edit to a skill's `description` (the trigger surface) or to a rule the
scenarios guard — and then with `--repeat 5`, because activation is a stochastic model decision and one
green run is not evidence. Run 01 and 03 together: they are the two sides of one invariant.

## Scenarios

| # | Guards |
|---|--------|
| 01-routes-to-test-iteration | a Russian "test this branch before merge" request activates `test-iteration`; no source edit |
| 02-branch-review-finds-planted-bug | `branch-review` reports a planted money defect (unclamped discount → negative price) at `discount.py`; no source edit |
| 03-inert-on-plain-fix | a plain "fix this crash" activates **no** qa-skill skill, the fix lands, no QA run-state arms the merge-gate |

## Adding a scenario

`evals/NN-name/` with `SCENARIO.md` (human rubric), `prompt.txt`, `check.sh` (sources `lib.sh`, ends with
`eval_finish`), a non-empty `fixture/`, and optionally `setup.sh`. The structural check and the runner
pick it up automatically.
