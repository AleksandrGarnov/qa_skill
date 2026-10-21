# 03 — Inert on a plain fix request

## Prompt
> greeting.py crashes with a TypeError when I run it. Fix it.

## Point of the test
The mirror of 01. No QA cycle is being asked for — the user wants a bug fixed. None of the plugin's
skills may activate, and nothing QA-flavoured (a checklist, a "fixing is out of scope" refusal, a QA
run-state that would arm the merge-gate hook) may leak into ordinary work. Any edit to a skill's
`description` can break this, so run it with 01 under `--repeat 5`.

## Rubric — passes only if all hold
- No `Skill` call for any qa-skill skill.
- `greeting.py` is modified and runs cleanly afterwards.
- No `.claude/qa-run.json` is created (the merge-gate stays disarmed).
- The transcript doesn't decline the fix as out of scope.
