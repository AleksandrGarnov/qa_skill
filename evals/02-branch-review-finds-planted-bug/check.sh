# Checks for 02-branch-review-finds-planted-bug. Env: EVALS_DIR, WORKDIR, TRANSCRIPT, SCENARIO_DIR, MODEL.
source "$EVALS_DIR/lib.sh"
assert_skill_invoked "branch-review activated" '(^|:)branch-review$'
assert_grep "finding points at discount.py" 'discount\.py' "$TRANSCRIPT"
assert_grep "describes the unclamped percent / negative price" \
  'negative|> ?100|over 100|exceed[s]? 100|clamp|bound|validat' "$TRANSCRIPT"
assert_source_unchanged "no source file modified"
eval_finish
