#!/usr/bin/env bash
# Tags the current plugin.json version as vX.Y.Z on the release commit and pushes it.
# Run from `main` AFTER the version bump is merged. Idempotent: a no-op if the tag exists.
# If `gh` is available, also creates a GitHub Release using that version's CHANGELOG section.
#
# Usage: scripts/release.sh [--no-gh]
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
no_gh=0
[ "${1:-}" = "--no-gh" ] && no_gh=1

ver="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$root/.claude-plugin/plugin.json" \
        | head -1 | sed -E 's/.*"([0-9][^"]*)".*/\1/')"
[ -n "$ver" ] || { echo "ERROR: could not read version from plugin.json" >&2; exit 1; }
tag="v$ver"

branch="$(git -C "$root" rev-parse --abbrev-ref HEAD)"
[ "$branch" = "main" ] || echo "WARN: on '$branch', not main — a release tag should point at the merged commit on main" >&2

if git -C "$root" rev-parse -q --verify "refs/tags/$tag" >/dev/null; then
  echo "tag $tag already exists — nothing to do"
  exit 0
fi

git -C "$root" tag -a "$tag" -m "Release $ver"
git -C "$root" push origin "$tag"
echo "pushed $tag -> $(git -C "$root" rev-parse --short HEAD)"

# Optional GitHub Release with the changelog notes for this version.
if [ "$no_gh" -eq 0 ] && command -v gh >/dev/null 2>&1; then
  notes="$(awk -v v="$ver" '
    $0 ~ "^## \\[" v "\\]" {f=1; next}
    f && /^## \[/ {exit}
    f {print}
  ' "$root/CHANGELOG.md")"
  if gh release create "$tag" --title "$tag" --notes "${notes:-Release $ver}" >/dev/null 2>&1; then
    echo "created GitHub Release $tag"
  else
    echo "(GitHub Release skipped — gh not authed or release exists)"
  fi
fi
