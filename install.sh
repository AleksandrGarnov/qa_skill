#!/usr/bin/env bash
# Symlinks all skills from ./skills into ~/.claude/skills (globally, into every project).
# Safe to re-run; a git pull updates the skills automatically.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/skills" && pwd)"
DEST="$HOME/.claude/skills"
mkdir -p "$DEST"

for skill in "$SRC"/*/; do
  name="$(basename "$skill")"
  target="$DEST/$name"
  rm -rf "$target"
  ln -s "$skill" "$target"
  echo "linked: $name -> $target"
done

echo "Done. Restart Claude Code."
