#!/usr/bin/env bash
# Enumerate the behaviour-carrying SURFACES changed on a branch — the input to the Test-Gap gate.
#
# A "surface" is a changed non-noise file, at the finest granularity git can name it: where a hunk
# carries a function/method/class context, the surface is "<file>::<context>"; otherwise it is the
# bare "<file>". The QA manifest must then map EVERY surface to >=1 checklist item (or an explicit
# N/A) — so a large diff cannot be "covered" by a handful of items (verify-gap.sh enforces this).
#
# Deterministic: surfaces come from git's own diff + hunk-context output, not a bespoke language
# parser — so the list is stable run-over-run (no flaky gate). Pure-noise changes are filtered out,
# because only *behaviour* must be tested (Test-Gap Analysis excludes docs/tests/generated/locks):
#   - docs/assets/lockfiles/generated/vendored paths
#   - test & fixture files (they are test code, not the surface under test)
#
# Migrations are NOT noise: a schema change is behaviour, so each migration file is a surface.
# Runtime/infra changes add ONE synthetic surface, "@runtime::cold-start": when the diff touches what
# the app boots from — migrations, Dockerfile/compose, dependency manifests or lockfiles, framework
# config/, deploy/k8s/helm/infra manifests, .env examples, web/process-server config — a page-level
# check of the feature isn't enough; the freshly deployed build must boot, migrate, and serve its first
# request. verify-gap.sh then requires that surface to be mapped to a cold-start smoke item (or a
# reasoned N/A) like any other — no new gate, the existing Test-Gap one enforces it.
#
# Usage:
#   changed-surfaces.sh <branch> [base]        # resolve base like branch-diff.sh, diff, enumerate
#   changed-surfaces.sh --diff <unified-diff>   # parse a saved `git diff` (used by the self-tests)
# Output: one surface per line ("<file>" or "<file>::<context>"), sorted & de-duplicated.
set -euo pipefail

usage() {
  echo "usage: changed-surfaces.sh <branch> [base] | changed-surfaces.sh --diff <unified-diff-file>" >&2
  exit 2
}

emit_diff() {
  if [ "${1:-}" = "--diff" ]; then
    [ -n "${2:-}" ] && [ -f "$2" ] || usage
    cat "$2"
    return
  fi
  local branch="${1:-}" base="${2:-}"
  [ -n "$branch" ] || usage
  git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: not inside a git repository" >&2; exit 1; }
  git fetch --quiet --all --prune 2>/dev/null || true
  if [ -z "$base" ]; then
    for cand in \
      "$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')" \
      develop main master; do
      [ -n "$cand" ] || continue
      [ "$cand" = "$branch" ] && continue
      if git show-ref --verify --quiet "refs/remotes/origin/$cand"; then base="$cand"; break; fi
    done
  fi
  [ -n "$base" ] || { echo "ERROR: base branch UNKNOWN — pass it explicitly" >&2; exit 1; }
  git diff "origin/$base...$branch"
}

emit_diff "$@" | awk '
  function runtime(p) {
    return (p ~ /(^|\/)(migrations?|db\/migrate)\//) ||
           (p ~ /(^|\/)(Dockerfile[^\/]*|\.dockerignore|Procfile|crontab|php\.ini)$/) ||
           (p ~ /(^|\/)(docker-)?compose[^\/]*\.ya?ml$/) ||
           (p ~ /(^|\/)(package\.json|composer\.json|requirements[^\/]*\.txt|pyproject\.toml|Pipfile|go\.mod|Gemfile|Cargo\.toml|pom\.xml|build\.gradle(\.kts)?)$/) ||
           (p ~ /(^|\/)(package-lock\.json|yarn\.lock|composer\.lock|pnpm-lock\.yaml|Gemfile\.lock|go\.sum|poetry\.lock|Pipfile\.lock|Cargo\.lock)$/) ||
           (p ~ /(^|\/)(config|k8s|kubernetes|helm|charts|deploy|deployment|infra|\.docker|docker)\//) ||
           (p ~ /(^|\/)\.env(\.[^\/]+)?\.example$/) ||
           (p ~ /(^|\/)(nginx|apache2?|httpd|supervisord?)[^\/]*\.conf$/)
  }
  # migration files are behaviour even though their extension/dir would otherwise look like noise
  function isMigration(p) { return (p ~ /(^|\/)(migrations?|db\/migrate)\//) && (p !~ /\.(md|txt)$/) }
  /^diff --git / {
    hp=$0; sub(/^diff --git a\/[^ ]* b\//,"",hp); gsub(/\r/,"",hp)
    if (runtime(hp)) coldstart=1
    next
  }
  function noise(p) {
    if (isMigration(p)) return 0
    return (p ~ /(^|\/)(node_modules|vendor|dist|build|out|target|\.git|coverage|__pycache__)\//) ||
           (p ~ /\.(md|markdown|txt|rst|adoc|lock|map|snap|min\.js|min\.css|png|jpe?g|gif|svg|ico|pdf|woff2?|ttf|eot|csv|yml|yaml|json|toml|ini|cfg|env)$/) ||
           (p ~ /(^|\/)(package-lock\.json|yarn\.lock|composer\.lock|pnpm-lock\.yaml|Gemfile\.lock|go\.sum|poetry\.lock)$/) ||
           (p ~ /(\.test\.|\.spec\.|_test\.|_spec\.|Test\.php$|\.stories\.)/) ||
           (p ~ /(^|\/)(tests?|__tests__|__mocks__|spec|specs|e2e|cypress|fixtures?|snapshots?)\//)
  }
  /^\+\+\+ / {
    path=$0; sub(/^\+\+\+ /,"",path); gsub(/\r/,"",path); sub(/^b\//,"",path)
    if (path=="/dev/null") { curfile=""; skip=1; next }
    curfile=path; skip=noise(curfile)
    if (!skip) files[curfile]=1
    next
  }
  # A hunk context is only kept as a symbol surface if it LOOKS like a definition (a name followed by
  # "(", or a definition keyword) — git names hunk context per language and, for languages it has no
  # funcname pattern for (e.g. shell), it grabs an arbitrary nearby line. Keeping only definition-like
  # contexts avoids inflating the required set with junk; anything else falls back to the reliable
  # file-level surface, so nothing is ever lost from the gate.
  function deflike(c) {
    return (c ~ /[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(/) ||
           (c ~ /(^|[^A-Za-z])(function|func|def|fn|class|interface|trait|struct|impl|module|namespace|sub|package|method|proc)([^A-Za-z]|$)/)
  }
  /^@@ / {
    if (curfile=="" || skip) next
    ctx=$0; sub(/^@@[^@]*@@[[:space:]]*/,"",ctx); gsub(/\r/,"",ctx)
    gsub(/^[[:space:]]+|[[:space:]]+$/,"",ctx)
    if (ctx!="" && deflike(ctx)) { sym[curfile "::" ctx]=1; hassym[curfile]=1 }
    else { bare[curfile]=1 }
    next
  }
  END {
    for (k in sym) print k
    # bare file surface only when the file has a context-less hunk or no named context at all
    for (f in files) if (bare[f] || !hassym[f]) print f
    if (coldstart) print "@runtime::cold-start"
  }
' | sort -u
