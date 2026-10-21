#!/usr/bin/env bash
# evals/run.sh — behavioral evals for the qa-skill skills. MAINTAINER ONLY; spends tokens.
#
# The shell suites (scripts/tests/) prove the gate SCRIPTS are correct. Nothing proves the skill
# PROSE still makes the model behave — routing, "fix nothing", "don't hijack a plain fix request".
# These scenarios do: each runs one headless session with the plugin loaded against a throwaway
# fixture, then asserts mechanically on the result (Skill calls in the event stream, file hashes).
#
# Usage:
#   evals/run.sh                    # all scenarios, default model
#   evals/run.sh --only 02          # scenarios whose folder starts with "02"
#   evals/run.sh --repeat 5         # run each N times; a scenario passes only at N/N
#   evals/run.sh --model <id>       # pick the model (or EVAL_MODEL=...)
#   evals/run.sh --budget 1.50      # USD cap per run (or EVAL_BUDGET=...), default 1.00
#   evals/run.sh --keep             # keep each run's temp workdir for inspection
#
# Why --repeat: skill activation is a stochastic model decision. A trigger that fires 70% of the time
# passes one run most of the time, so one green run is not evidence. Gate any edit to a skill's
# `description` on --repeat 5, and run 01 (must activate) together with 03 (must stay inert) — making
# one fire more eagerly is exactly what breaks the other.
#
# Scenario contract (evals/NN-name/): SCENARIO.md (human rubric) + prompt.txt + check.sh
# + fixture/ (non-empty), and an optional setup.sh run inside the workdir before the snapshot
# (e.g. to build a git history the prompt refers to).
set -uo pipefail

export EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PLUGIN_DIR="$(cd "$EVALS_DIR/.." && pwd)"
source "$EVALS_DIR/lib.sh"

export MODEL="${EVAL_MODEL:-sonnet}"
export BUDGET="${EVAL_BUDGET:-1.00}"
KEEP="${EVAL_KEEP:-0}"
ONLY=""
REPEAT="${EVAL_REPEAT:-1}"

while [ $# -gt 0 ]; do
  case "$1" in
    --model)  MODEL="$2";  shift 2;;
    --budget) BUDGET="$2"; shift 2;;
    --only)   ONLY="$2";   shift 2;;
    --repeat) REPEAT="$2"; shift 2;;
    --keep)   KEEP=1;      shift;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) echo "unknown arg: $1 (try --help)"; exit 2;;
  esac
done
export MODEL BUDGET

command -v claude  >/dev/null 2>&1 || { echo "✗ 'claude' CLI not on PATH"; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "✗ python3 not on PATH"; exit 2; }

echo "qa-skill behavioral evals  (model: $MODEL · budget/run: \$$BUDGET · repeat: $REPEAT)"
echo

total=0; failed=0
for dir in "$EVALS_DIR"/[0-9]*/; do
  name="$(basename "$dir")"
  [ -n "$ONLY" ] && [[ "$name" != "$ONLY"* ]] && continue
  total=$((total + 1))
  echo "▶ $name"

  passes=0
  for run in $(seq 1 "$REPEAT"); do
    [ "$REPEAT" -gt 1 ] && echo "  · run $run/$REPEAT"
    work="$(mktemp -d)"
    cp -R "$dir/fixture/." "$work/"
    if [ -f "$dir/setup.sh" ] && ! ( cd "$work" && bash "$dir/setup.sh" ) >/dev/null 2>&1; then
      echo "    ✗ setup.sh failed — run counted as FAIL"
      [ "$KEEP" = 1 ] || rm -rf "$work"
      continue
    fi
    snapshot_source "$work"
    export WORKDIR="$work" TRANSCRIPT="$work/.eval-transcript.txt" SCENARIO_DIR="$dir"
    run_scenario "$work" "$(cat "$dir/prompt.txt")"
    if bash "$dir/check.sh"; then passes=$((passes + 1)); fi
    if [ "$KEEP" = 1 ]; then echo "  (workdir kept: $work)"; else rm -rf "$work"; fi
  done

  # A flaky invariant is a broken invariant: every repetition must pass.
  if [ "$passes" -eq "$REPEAT" ]; then echo "  → PASS ($passes/$REPEAT)"
  else echo "  → FAIL ($passes/$REPEAT)"; failed=$((failed + 1)); fi
  echo
done

echo "================  $((total - failed))/$total scenarios passed  ================"
[ "$failed" -eq 0 ]
