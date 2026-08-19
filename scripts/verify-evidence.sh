#!/usr/bin/env bash
# Structured evidence gate for manifest/report JSON sidecars.
# Checks runtime AC evidence, critical-path corroboration, raw quotes, and artifact refs.
set -uo pipefail

manifest_json="${1:?usage: verify-evidence.sh <manifest.json> <report.json> <artifacts.json>}"
report_json="${2:?usage: verify-evidence.sh <manifest.json> <report.json> <artifacts.json>}"
artifacts_json="${3:?usage: verify-evidence.sh <manifest.json> <report.json> <artifacts.json>}"

[ -f "$manifest_json" ] || { echo "MANIFEST-JSON-MISSING: $manifest_json"; exit 1; }
[ -f "$report_json" ] || { echo "REPORT-JSON-MISSING: $report_json"; exit 1; }
[ -f "$artifacts_json" ] || { echo "ARTIFACTS-JSON-MISSING: $artifacts_json"; exit 1; }

python3 - <<'PY' "$manifest_json" "$report_json" "$artifacts_json"
import json
import sys
from pathlib import Path

manifest = json.loads(Path(sys.argv[1]).read_text(encoding='utf-8'))
report = json.loads(Path(sys.argv[2]).read_text(encoding='utf-8'))
artifacts = json.loads(Path(sys.argv[3]).read_text(encoding='utf-8'))

violations = []

def fail(msg: str) -> None:
    violations.append(msg)

artifact_ids = {a.get('id') for a in artifacts.get('artifacts', []) if a.get('id')}
results_by_item = {}
for row in report.get('results', []):
    item_id = str(row.get('itemId', '')).strip()
    if item_id:
      results_by_item.setdefault(item_id, []).append(row)

items = {str(item.get('id')): item for item in manifest.get('items', []) if item.get('id') is not None}
ac_defs = {str(ac.get('id')): ac for ac in manifest.get('acceptanceCriteria', []) if ac.get('id') is not None}
reexec_by_item = {}
for row in report.get('independentReexecution', []):
    item_id = str(row.get('itemId', '')).strip()
    if item_id:
        reexec_by_item.setdefault(item_id, []).append(row)

runtime_evidence = {'observed-data', 'api-response', 'log'}

for item_id, rows in results_by_item.items():
    for row in rows:
        if row.get('result') == 'pass' and row.get('evidenceType') in runtime_evidence and not str(row.get('rawQuote', '')).strip():
            fail(f"item {item_id} passes on runtime evidence but has no raw quote")
        for ref in row.get('artifactRefs', []) or []:
            if ref not in artifact_ids:
                fail(f"item {item_id} references missing artifact '{ref}'")

for row in report.get('independentReexecution', []):
    item_id = str(row.get('itemId', '')).strip() or '?'
    for ref in row.get('artifactRefs', []) or []:
        if ref not in artifact_ids:
            fail(f"independent re-execution for item {item_id} references missing artifact '{ref}'")

for ac_row in report.get('acMatrix', []):
    ac_id = str(ac_row.get('acId', '')).strip()
    if not ac_id:
        continue
    ac = ac_defs.get(ac_id, {})
    kind = str(ac.get('kind', '')).strip().lower()
    status = str(ac_row.get('status', '')).strip().lower()
    covering = [str(x) for x in (ac_row.get('coveringItemIds') or [])]
    if kind != 'runtime' or status != 'pass':
        continue

    evidence_rows = []
    for item_id in covering:
        evidence_rows.extend(results_by_item.get(item_id, []))

    if not evidence_rows:
        fail(f"runtime AC {ac_id} passes but has no covering item results")
        continue

    runtime_rows = [row for row in evidence_rows if row.get('result') == 'pass' and row.get('evidenceType') in runtime_evidence]
    if not runtime_rows:
        fail(f"runtime AC {ac_id} passes without observed/api/log evidence")
        continue

    if not any(str(row.get('rawQuote', '')).strip() for row in runtime_rows):
        fail(f"runtime AC {ac_id} passes without a raw quote on runtime evidence")

for item_id, item in items.items():
    if not item.get('criticalPath'):
        continue
    rows = [row for row in results_by_item.get(item_id, []) if row.get('result') == 'pass']
    if not rows:
        continue
    if any(row.get('acceptanceTestEquivalent') for row in rows):
        continue
    corroborated = False
    for row in reexec_by_item.get(item_id, []):
        status = str(row.get('status', '')).strip().lower()
        if status in {'agree', 'corroborated', 'pass'}:
            corroborated = True
            break
    if not corroborated:
        fail(f"critical-path item {item_id} passes without independent corroboration")

if violations:
    for msg in violations:
        print(f"FAIL: {msg}")
    print('---')
    print(f"{len(violations)} evidence violation(s) — structured evidence gate is red")
    raise SystemExit(1)

print('EVIDENCE-OK: runtime ACs have real evidence, critical path corroborated, artifact refs valid')
PY
