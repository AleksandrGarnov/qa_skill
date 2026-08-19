#!/usr/bin/env bash
# Canonical QA bundle paths + active run-state validation.
# Keeps per-run markdown and JSON sidecars co-located under one stable bundle dir.
set -uo pipefail

cmd="${1:-}"
[ -n "$cmd" ] || { echo "usage: qa-bundle.sh init|paths|state ..." >&2; exit 2; }

slugify() {
  printf '%s' "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g'
}

json_escape() {
  python3 - <<'PY' "$1"
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

print_paths() {
  local docs_dir="$1" task_id="$2" run_id="$3"
  local docs_abs task_slug run_slug bundle_dir manifest_md manifest_json report_md report_json artifacts_json gates_dir artifacts_dir

  docs_abs="$(cd "$docs_dir" 2>/dev/null && pwd)" || return 1
  task_slug="$(slugify "$task_id")"
  run_slug="$(slugify "$run_id")"
  bundle_dir="$docs_abs/runs/$task_slug/$run_slug"
  manifest_md="$bundle_dir/manifest.md"
  manifest_json="$bundle_dir/manifest.json"
  report_md="$bundle_dir/report.md"
  report_json="$bundle_dir/report.json"
  artifacts_json="$bundle_dir/artifacts.json"
  gates_dir="$bundle_dir/gates"
  artifacts_dir="$bundle_dir/artifacts"

  printf 'BUNDLE-DIR: %s\n' "$bundle_dir"
  printf 'MANIFEST-MD: %s\n' "$manifest_md"
  printf 'MANIFEST-JSON: %s\n' "$manifest_json"
  printf 'REPORT-MD: %s\n' "$report_md"
  printf 'REPORT-JSON: %s\n' "$report_json"
  printf 'ARTIFACTS-JSON: %s\n' "$artifacts_json"
  printf 'GATES-DIR: %s\n' "$gates_dir"
  printf 'ARTIFACTS-DIR: %s\n' "$artifacts_dir"
}

case "$cmd" in
  init)
    docs_dir="${2:-}"
    task_id="${3:-}"
    run_id="${4:-}"
    [ -n "$docs_dir" ] && [ -n "$task_id" ] && [ -n "$run_id" ] || {
      echo "usage: qa-bundle.sh init <docs-dir> <task-id> <run-id>" >&2
      exit 2
    }
    mkdir -p "$docs_dir" || exit 1
    paths="$(print_paths "$docs_dir" "$task_id" "$run_id")" || exit 1
    bundle_dir="$(printf '%s\n' "$paths" | sed -n 's/^BUNDLE-DIR: //p')"
    artifacts_json="$(printf '%s\n' "$paths" | sed -n 's/^ARTIFACTS-JSON: //p')"
    gates_dir="$(printf '%s\n' "$paths" | sed -n 's/^GATES-DIR: //p')"
    artifacts_dir="$(printf '%s\n' "$paths" | sed -n 's/^ARTIFACTS-DIR: //p')"
    mkdir -p "$bundle_dir" "$gates_dir" "$artifacts_dir" "$artifacts_dir/logs" "$artifacts_dir/api" "$artifacts_dir/screenshots" "$artifacts_dir/notes" || exit 1
    if [ ! -f "$artifacts_json" ]; then
      printf '{\n  "artifacts": []\n}\n' > "$artifacts_json"
    fi
    printf '%s\n' "$paths"
    ;;
  paths)
    docs_dir="${2:-}"
    task_id="${3:-}"
    run_id="${4:-}"
    [ -n "$docs_dir" ] && [ -n "$task_id" ] && [ -n "$run_id" ] || {
      echo "usage: qa-bundle.sh paths <docs-dir> <task-id> <run-id>" >&2
      exit 2
    }
    print_paths "$docs_dir" "$task_id" "$run_id"
    ;;
  state)
    subcmd="${2:-}"
    case "$subcmd" in
      validate)
        state_file="${3:-}"
        [ -n "$state_file" ] || { echo "usage: qa-bundle.sh state validate <qa-run.json>" >&2; exit 2; }
        [ -f "$state_file" ] || { echo "STATE-MISSING: $state_file" >&2; exit 1; }
        python3 - <<'PY' "$state_file"
import json, sys
from pathlib import Path

state = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
required = {
    'schemaVersion', 'runId', 'status', 'branch', 'bundleDir',
    'manifest', 'manifestMd', 'manifestJson',
    'report', 'reportMd', 'reportJson',
    'artifactsIndexJson', 'currentRound', 'gates'
}
missing = sorted(k for k in required if not state.get(k))
if missing:
    print('STATE-FAIL: missing required field(s): ' + ', '.join(missing))
    raise SystemExit(1)

gates = state.get('gates') or {}
missing_gates = [k for k in ('context', 'coverage', 'report', 'evidence') if not gates.get(k)]
if missing_gates:
    print('STATE-FAIL: missing gate status(es): ' + ', '.join(missing_gates))
    raise SystemExit(1)

print('STATE-OK: active run-state is complete')
PY
        ;;
      *)
        echo "usage: qa-bundle.sh state validate <qa-run.json>" >&2
        exit 2
        ;;
    esac
    ;;
  *)
    echo "unknown command: $cmd (use init|paths|state)" >&2
    exit 2
    ;;
esac
