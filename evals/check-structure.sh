#!/usr/bin/env bash
# evals/check-structure.sh — FREE structural checks for the plugin. No model calls, no tokens.
#
# Safe to run on every push (CI runs it). Catches the things that ship a silently-degraded skill:
#   - a markdown link inside skills/ that points at a .md file which doesn't exist,
#   - an orphan reference: a file under skills/*/references/ that nothing (skill, script, README)
#     mentions — guidance the model can never be pointed at,
#   - an eval scenario that isn't fully wired (SCENARIO.md + prompt.txt + check.sh + non-empty fixture/).
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fail=0
ok()  { printf '  \033[32m✓\033[0m %s\n' "$*"; }
bad() { printf '  \033[31m✗\033[0m %s\n' "$*"; fail=1; }

echo "▶ markdown links inside skills/ resolve"
broken="$(python3 -I - "$ROOT" <<'PY'
import os, re, sys
root = sys.argv[1]
link = re.compile(r'\]\(([^)#\s]+\.md)(?:#[^)]*)?\)')
for d, _, files in os.walk(os.path.join(root, "skills")):
    for f in files:
        if not f.endswith(".md"):
            continue
        path = os.path.join(d, f)
        for target in link.findall(open(path, encoding="utf-8").read()):
            if "://" in target:
                continue
            if not os.path.exists(os.path.normpath(os.path.join(d, target))):
                print(f"{os.path.relpath(path, root)} -> {target}")
PY
)"
if [ -z "$broken" ]; then ok "all relative .md links resolve"
else while IFS= read -r l; do bad "broken link: $l"; done <<< "$broken"; fi

echo "▶ no orphan reference files"
while IFS= read -r f; do
  base="$(basename "$f")"
  if grep -rlF --include='*.md' --include='*.sh' "$base" "$ROOT/skills" "$ROOT/scripts" "$ROOT/README.md" \
       | grep -vxF "$f" | grep -q .; then
    ok "${f#"$ROOT"/} is referenced"
  else
    bad "${f#"$ROOT"/} is an orphan — no skill, script, or README mentions it"
  fi
done < <(find "$ROOT/skills" -path '*/references/*' -name '*.md' | LC_ALL=C sort)

echo "▶ eval scenarios are fully wired"
for dir in "$ROOT"/evals/[0-9]*/; do
  [ -d "$dir" ] || continue
  name="$(basename "$dir")"
  missing=""
  for f in SCENARIO.md prompt.txt check.sh; do [ -f "$dir/$f" ] || missing="$missing $f"; done
  [ -n "$(find "$dir/fixture" -type f 2>/dev/null | head -1)" ] || missing="$missing fixture/"
  if [ -z "$missing" ]; then ok "$name"; else bad "$name: missing$missing"; fi
done

echo
if [ "$fail" -eq 0 ]; then echo "STRUCTURE-OK"; else echo "STRUCTURE-FAILED"; fi
exit "$fail"
