#!/usr/bin/env bash
# Removes the symlinks that install.sh created in ~/.claude/skills.
# Safe: only removes a skill entry when it is a SYMLINK pointing back into THIS repo's ./skills —
# a real directory or a symlink to somewhere else (a differently-sourced skill of the same name)
# is left untouched.
set -euo pipefail

SRC="$(cd "$(dirname "$0")/skills" && pwd)"
DEST="$HOME/.claude/skills"

removed=0
for skill in "$SRC"/*/; do
  name="$(basename "$skill")"
  target="$DEST/$name"
  [ -L "$target" ] || { [ -e "$target" ] && echo "skip (not our symlink): $target"; continue; }
  # resolve the link target and compare against this repo's skill dir
  link="$(readlink "$target")"
  case "$link" in
    "$skill"|"${skill%/}") rm -f "$target"; echo "unlinked: $name"; removed=$((removed+1));;
    *) echo "skip (symlink points elsewhere): $target -> $link";;
  esac
done

echo "Done. Removed $removed symlink(s). Restart Claude Code."
