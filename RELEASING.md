# Releasing

How versions are cut and how they reach users. Keep `version`, the CHANGELOG, and the git tag in lockstep.

## Versioning

[SemVer](https://semver.org). The `version` field in `.claude-plugin/plugin.json` is the **release gate**: Claude Code only offers an update to installed plugins when this string **changes**. So:

- **User-facing change** (a skill, a script, behaviour) → bump `version` + add a CHANGELOG entry.
- **Maintainer-only change** (this doc, internal tooling that doesn't ship behaviour) → **do not bump** `version`. Pushing it to `main` is invisible to users by design — there's no point making everyone "update" for a doc.

## Cutting a release

1. Feature branch → PR (one direction per PR).
2. In the PR: bump `version` in `.claude-plugin/plugin.json` **and** add a `## [X.Y.Z]` CHANGELOG entry.
3. Run the tests: `bash scripts/tests/run-all.sh` (green).
4. Merge to `main`.
5. **Tag the release** from `main`:
   ```bash
   git checkout main && git pull
   scripts/release.sh        # tags vX.Y.Z (read from plugin.json), pushes it, and (if gh is present) creates a GitHub Release from the CHANGELOG
   ```
   Or by hand: `git tag -a vX.Y.Z -m "Release X.Y.Z" && git push origin vX.Y.Z`.

Tags are annotated, named `vX.Y.Z`, and point at the release commit on `main`. History is backfilled from v2.0.0.

## How updates reach users (important)

Confirmed against the Claude Code plugin docs:

- **Auto-update is OFF by default for third-party marketplaces.** Merging to `main` and bumping `version` does **not** push to anyone automatically — the installed copy keeps running its cached version until refreshed.
- **To get updates, a user must either:**
  - refresh manually: `/plugin marketplace update qa-suite` then `/plugin update qa-skill@qa-suite`, **or**
  - enable auto-update once: `/plugin` → Marketplaces → `qa-suite` → enable auto-update (then new `version`s are picked up on startup).
- **Force the newest version right now** (maintainer or user):
  ```
  /plugin marketplace update qa-suite
  /plugin update qa-skill@qa-suite
  /reload-plugins
  ```
- **Pin to a specific release** (stable channel): add the marketplace at a tag —
  `/plugin marketplace add AleksandrGarnov/qa_skill@vX.Y.Z`.

Because updates are version-gated, always bump `version` for a user-facing release — otherwise the change ships but no one is offered it.
