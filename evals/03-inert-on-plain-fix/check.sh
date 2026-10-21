# Checks for 03-inert-on-plain-fix. Env: EVALS_DIR, WORKDIR, TRANSCRIPT, SCENARIO_DIR, MODEL.
source "$EVALS_DIR/lib.sh"
refute_skill_invoked "no qa-skill skill activated on a plain fix request" "$QA_SKILLS_RE"
assert_file_changed "greeting.py was modified (fix applied)" "greeting.py"
if ( cd "$WORKDIR" && python3 -I greeting.py ) >/dev/null 2>&1; then ok "greeting.py runs cleanly"
else bad "greeting.py still crashes"; fi
if [ ! -e "$WORKDIR/.claude/qa-run.json" ]; then ok "no QA run-state created (merge-gate disarmed)"
else bad ".claude/qa-run.json was created on a plain fix request"; fi
refute_grep "fix not declined as out of scope" 'out of scope|won.?t (fix|modify)|not (allowed|permitted) to (fix|modify)' "$TRANSCRIPT"
eval_finish
