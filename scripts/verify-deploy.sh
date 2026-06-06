#!/usr/bin/env bash
# Deterministic entry-criteria check: is THIS branch's commit actually deployed
# to the staging environment? Testing a different build invalidates the verdict,
# so this is run before the test pass (test-iteration step 9).
#
# It fetches a version/health endpoint that exposes the deployed commit and
# checks whether the expected commit hash is present in the response.
#
# Usage: verify-deploy.sh <version-url> <expected-commit>
#   <version-url>      URL that returns the deployed build/commit (e.g.
#                      https://stage.example/version, /healthz, /api/build-info)
#   <expected-commit>  full or short commit hash of the branch under test
#
# Security: this only performs a GET on a URL the caller supplies. Do NOT pass
# secrets on the command line; if the endpoint needs auth, fetch it another way.
#
# Exit codes: 0 = match (deployed), 1 = unreachable, 2 = mismatch (wrong build).
set -euo pipefail

url="${1:?usage: verify-deploy.sh <version-url> <expected-commit>}"
expected="${2:?expected commit required}"
short="${expected:0:7}"

body="$(curl -fsS --max-time 15 "$url")" || {
  echo "DEPLOY-CHECK: UNREACHABLE ($url)"
  exit 1
}

if printf '%s' "$body" | grep -qiF "$short"; then
  echo "DEPLOY-CHECK: OK (commit $short is live at $url)"
  exit 0
fi

echo "DEPLOY-CHECK: MISMATCH (expected commit $short not found at $url)"
echo "--- response (first 500 chars) ---"
printf '%s' "$body" | head -c 500
echo
echo "Staging is running a different build — deploy this branch before testing."
exit 2
