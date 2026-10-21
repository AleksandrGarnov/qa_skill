# 01 — A pre-merge QA request routes to `test-iteration`

## Prompt
> Протестируй ветку feature/LM-1-discount перед мержем в main.

## Point of the test
The plugin's central entry point is `test-iteration`. A plain "test this branch before merge" request —
in Russian, the way the team actually asks — must activate it. If another installed QA plugin (or no
skill at all) catches this phrasing instead, the whole gated cycle silently never runs. This is the
"must activate" side of the activation invariant; 03 is the "must stay inert" side — run them together.

## Rubric — passes only if all hold
- A `Skill` call for `test-iteration` appears in the event stream (activation proven by the tool call,
  not inferred from artifacts).
- No source file in the fixture is modified (QA never edits the code under test).

The run is budget-capped and will usually stop mid-cycle (there is no staging here) — that's expected;
this scenario only checks routing and the no-edit invariant.
