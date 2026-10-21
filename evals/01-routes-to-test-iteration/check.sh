# Checks for 01-routes-to-test-iteration. Env: EVALS_DIR, WORKDIR, TRANSCRIPT, SCENARIO_DIR, MODEL.
source "$EVALS_DIR/lib.sh"
assert_skill_invoked "test-iteration activated on a pre-merge QA request" '(^|:)test-iteration$'
assert_source_unchanged "no source file modified"
eval_finish
