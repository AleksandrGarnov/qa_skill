#!/usr/bin/env bash
# Flag test smells in the changed TEST files — a cheap, read-only signal for branch-review step 1.5.
#
# A test that can't fail, never runs, or depends on wall-clock time gives false confidence: CI is green
# while the behaviour is unchecked. These are lexical HEURISTICS (named after the test-smell catalogs,
# testsmells.org): a hint where to look, never a finding by itself — an assertion can live in a helper,
# a sleep can be intentional. The reviewer reads each hit before it becomes anything.
#
#   focused           it.only / test.only / describe.only / fit / fdescribe — the rest of the suite stops running
#   skipped           .skip / xit / xdescribe / @pytest.mark.skip / pytest.skip / @unittest.skip / markTestSkipped / @Disabled
#   sleepy            sleep / time.sleep / asyncio.sleep / usleep / waitForTimeout / setTimeout / Thread.sleep
#   nondeterministic  Math.random / Date.now / new Date() / datetime.now / time.time / random.* / rand() / Carbon::now / now()
#   unawaited-assert  expect(...).resolves / .rejects with no await/return on the line — the assertion can't fail
#   no-assertion      a Python test_* function or a JS/TS it()/test() callback with no assert/expect/should/verify in it
#
# Usage:
#   test-smells.sh <file>...       # pass the changed files (e.g. from branch-diff.sh); non-test files are ignored
# Output: "<file>:<line> | <smell> | <trimmed source line>", one per hit, then "smells: <n> in <m> test file(s)".
# Exit 0 whatever it finds (it is a signal, not a gate); 2 on usage error.
set -euo pipefail

[ "$#" -gt 0 ] || { echo "usage: test-smells.sh <file>..." >&2; exit 2; }

is_test_file() {
  case "$1" in
    *.test.js|*.test.jsx|*.test.ts|*.test.tsx|*.test.mjs|*.spec.js|*.spec.jsx|*.spec.ts|*.spec.tsx|*.spec.mjs) return 0 ;;
    *_test.py|*/test_*.py|test_*.py|*_spec.rb|*Test.php|*_test.go) return 0 ;;
    */__tests__/*|*/tests/*.js|*/tests/*.ts|*/test/*.js|*/test/*.ts) return 0 ;;
  esac
  return 1
}

total=0; files=0
for f in "$@"; do
  [ -f "$f" ] || continue
  is_test_file "$f" || continue
  files=$((files+1))
  hits="$(awk -v F="$f" '
    function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return substr(s, 1, 120) }
    function hit(n, kind, src) { printf "%s:%d | %s | %s\n", F, n, kind, trim(src) }
    function asserts(s) {
      return s ~ /(^|[^A-Za-z_])(assert[A-Za-z_]*|expect[A-Za-z_]*|should|verify[A-Za-z_]*|check[A-Z][A-Za-z_]*)[ \t]*[(.!]/ ||
             s ~ /(^|[^A-Za-z_])assert[ \t]/ || s ~ /pytest\.raises|\.assert_[a-z_]*called|t\.(Error|Fatal)/
    }
    BEGIN { py = (F ~ /\.py$/); js = (F ~ /\.(m?jsx?|tsx?)$/) }
    {
      line = $0
      code = line; sub(/^[ \t]*(\/\/|#).*/, "", code)     # whole-line comments carry no smell
      if (code == "") next

      if (code ~ /(^|[^A-Za-z_.])(it|test|describe|context)\.only[ \t]*\(/ || code ~ /(^|[^A-Za-z_.])f(it|describe)[ \t]*\(/)
        hit(NR, "focused", line)
      if (code ~ /(^|[^A-Za-z_.])(it|test|describe|context)\.skip[ \t]*\(/ || code ~ /(^|[^A-Za-z_.])x(it|describe|test)[ \t]*\(/ ||
          code ~ /@pytest\.mark\.(skip|xfail)|pytest\.skip\(|@unittest\.skip|markTestSkipped|markTestIncomplete|@Disabled|@Ignore/)
        hit(NR, "skipped", line)
      if (code ~ /(^|[^A-Za-z_.])(time\.|asyncio\.|Thread\.)?sleep[ \t]*\(/ || code ~ /(^|[^A-Za-z_])usleep[ \t]*\(/ ||
          code ~ /waitForTimeout[ \t]*\(/ || code ~ /(^|[^A-Za-z_.])setTimeout[ \t]*\(/)
        hit(NR, "sleepy", line)
      if (code ~ /Math\.random[ \t]*\(|Date\.now[ \t]*\(|new Date[ \t]*\([ \t]*\)|datetime\.(now|today|utcnow)[ \t]*\(|time\.time[ \t]*\(|(^|[^A-Za-z_.])random\.[a-z]+[ \t]*\(|(^|[^A-Za-z_>:])(mt_)?rand[ \t]*\(|Carbon::now|(^|[^A-Za-z_.>:])now[ \t]*\([ \t]*\)/)
        hit(NR, "nondeterministic", line)
      if (code ~ /\.(resolves|rejects)[ \t]*\./ && code !~ /(^|[^A-Za-z_])(await|return)[ \t]/)
        hit(NR, "unawaited-assert", line)

      track(code, line)
    }
    # --- no-assertion: Python test_* functions, delimited by indentation ---
    # --- no-assertion: JS/TS it()/test() callbacks, delimited by brace depth ---
    function track(code, line,   ind, i, c) {
      if (py) {
        match(code, /^[ \t]*/); ind = RLENGTH
        if (inpy && ind <= pyind && code !~ /^[ \t]*$/) close_py()
        if (code ~ /^[ \t]*(async[ \t]+)?def[ \t]+test[A-Za-z0-9_]*[ \t]*\(/) { inpy = 1; pyind = ind; pystart = NR; pysrc = line; pyok = 0; return }
        if (inpy && asserts(code)) pyok = 1
      }
      if (js) {
        if (!injs && code ~ /(^|[^A-Za-z_.])(it|test)(\.only|\.each[^(]*\([^)]*\))?[ \t]*\(/ && code !~ /\.(skip|todo)[ \t]*\(/) {
          injs = 1; depth = 0; opened = 0; jsstart = NR; jssrc = line; jsok = 0
        }
        if (injs) {
          if (asserts(code)) jsok = 1
          for (i = 1; i <= length(code); i++) {
            c = substr(code, i, 1)
            if (c == "{") { depth++; opened = 1 } else if (c == "}") depth--
          }
          if (opened && depth <= 0) { if (!jsok) hit(jsstart, "no-assertion", jssrc); injs = 0 }
        }
      }
    }
    function close_py() { if (!pyok) hit(pystart, "no-assertion", pysrc); inpy = 0 }
    END { if (inpy) close_py() }
  ' "$f")"
  if [ -n "$hits" ]; then
    printf '%s\n' "$hits"
    total=$((total + $(printf '%s\n' "$hits" | grep -c .)))
  fi
done

echo "smells: $total in $files test file(s)"
