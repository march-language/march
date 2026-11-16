#!/usr/bin/env bash
# test-release-gate.sh: scripts/release-gate.sh against a fake `gh`.
#
# The gate decides whether a tag may ship, so it must be shown to go RED, not
# only green. Each case writes the workflow runs the API would return and
# asserts the exit code and a fragment of the output. No network, no build;
# needs jq (the fake gh applies the script's own --jq filter to the canned
# JSON, so the filter is under test too).
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
command -v jq >/dev/null || { echo "test-release-gate: jq not found" >&2; exit 1; }
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT

# Fake gh: `gh api PATH --jq FILTER`. PATH picks a canned file under $FIX:
#   .../workflows/W/runs?...  -> $FIX/W.json    (a missing file = no runs)
#   .../commits/REF           -> {"sha": REF}
#   .../compare/A...main      -> $FIX/compare.json
cat > "$T/gh" <<'FAKE'
#!/usr/bin/env bash
set -euo pipefail
[ "$1" = api ] && [ "$3" = --jq ] || { echo "fake gh: unexpected: $*" >&2; exit 2; }
path=$2 filter=$4
case "$path" in
  */workflows/*/runs\?*)
    wf=${path#*/workflows/}; wf=${wf%%/*}
    case "$path" in *head_sha=*|*branch=main\&event=push*) ;; *) echo "fake gh: unfiltered runs query: $path" >&2; exit 2 ;; esac
    if [ -f "$FIX/$wf.json" ]; then jq -r "$filter" "$FIX/$wf.json"; else echo '{"workflow_runs":[]}' | jq -r "$filter"; fi ;;
  */compare/*) jq -r "$filter" "$FIX/compare.json" ;;
  */commits/*) [ "${path##*/}" != unknown ] || exit 1; jq -n -r --arg sha "${path##*/}" '{sha:$sha}'" | $filter" ;;
  *) echo "fake gh: unexpected path: $path" >&2; exit 2 ;;
esac
FAKE
chmod +x "$T/gh"

SHA=1111111111111111111111111111111111111111
# run SHA STATUS CONCLUSION EVENT BRANCH -> one workflow_runs element
run() { printf '{"head_sha":"%s","status":"%s","conclusion":%s,"event":"%s","head_branch":"%s","html_url":"https://example.invalid/run"}' \
          "$1" "$2" "$([ "$3" = null ] && echo null || echo "\"$3\"")" "$4" "$5"; }
# fixture NAME COMPARE [WORKFLOW RUN...]... ; runs are newest first
fails=0 n=0
setup() {   # setup COMPARE_STATUS
  FIX="$T/fix.$n"; rm -rf "$FIX"; mkdir -p "$FIX"; export FIX
  printf '{"status":"%s"}' "$1" > "$FIX/compare.json"
}
runs() {    # runs WORKFLOW RUN...
  local wf=$1; shift; local IFS=,
  printf '{"workflow_runs":[%s]}' "$*" > "$FIX/$wf"
}
check() {   # check NAME WANT_EXIT FRAGMENT ARG
  n=$((n + 1))
  local got=0 out
  out=$(GH="$T/gh" REPO=o/r GITHUB_STEP_SUMMARY= "$HERE/release-gate.sh" "$4" 2>&1) || got=$?
  if [ "$got" != "$2" ] || ! grep -qF -- "$3" <<< "$out"; then
    fails=$((fails + 1))
    echo "FAIL: $1 (exit $got, want $2; want fragment: $3)"; sed 's/^/    /' <<< "$out"
  else
    echo "ok: $1"
  fi
}

green()  { run "$SHA" completed success push main; }
OTHER=2222222222222222222222222222222222222222

setup ahead; runs ci.yml.json "$(green)"; runs doc-lint.yml.json "$(green)"
check "both green" 0 "GREEN for $SHA" "$SHA"

setup identical; runs ci.yml.json "$(green)"; runs doc-lint.yml.json "$(green)"
check "green at main's HEAD" 0 "GREEN" "$SHA"

setup ahead; runs ci.yml.json "$(run "$SHA" completed failure push main)"; runs doc-lint.yml.json "$(green)"
check "ci failed" 1 "ci.yml: failure" "$SHA"
check "a red commit is not told to re-run" 1 "Do not release this commit" "$SHA"

setup ahead; runs ci.yml.json "$(green)"; runs doc-lint.yml.json "$(run "$SHA" completed failure push main)"
check "doc-lint failed" 1 "doc-lint.yml: failure" "$SHA"

setup ahead; runs ci.yml.json "$(run "$SHA" completed timed_out push main)"; runs doc-lint.yml.json "$(green)"
check "ci timed out" 1 "ci.yml: timed_out" "$SHA"

setup ahead; runs ci.yml.json "$(run "$SHA" completed cancelled push main)"; runs doc-lint.yml.json "$(green)"
check "ci cancelled in a merge burst" 1 "ci.yml: no verdict (1 run(s)" "$SHA"
check "... and says how to run CI on the commit" 1 "gh workflow run ci.yml --ref main" "$SHA"

setup ahead; runs doc-lint.yml.json "$(green)"
check "no ci run at all (Markdown-only commit)" 1 "ci.yml: no verdict (no run for this commit)" "$SHA"

setup ahead; runs ci.yml.json "$(run "$SHA" in_progress null push main)"; runs doc-lint.yml.json "$(green)"
check "ci still running" 1 "ci.yml: still in_progress" "$SHA"

setup ahead
runs ci.yml.json "$(run "$SHA" completed success workflow_dispatch release-check)" "$(run "$SHA" completed cancelled push main)"
runs doc-lint.yml.json "$(green)"
check "a dispatched run gives the verdict a cancelled push run did not" 0 "ci.yml: success (workflow_dispatch)" "$SHA"

setup ahead
runs ci.yml.json "$(run "$SHA" completed failure workflow_dispatch main)" "$(green)"
runs doc-lint.yml.json "$(green)"
check "the newest verdict decides: a later red run overrides an earlier green" 1 "ci.yml: failure (workflow_dispatch)" "$SHA"

setup ahead
runs ci.yml.json "$(run "$SHA" completed success pull_request some-branch)" "$(run "$SHA" completed success push some-branch)"
runs doc-lint.yml.json "$(green)"
check "a pull request's run, or a push to another branch, is not a verdict" 1 "ci.yml: no verdict" "$SHA"

setup diverged; runs ci.yml.json "$(green)"; runs doc-lint.yml.json "$(green)"
check "green but not on main" 1 "not on main" "$SHA"

setup ahead
check "an unresolvable ref" 1 "cannot resolve 'unknown'" unknown

# --newest-green: nightly's walk over ci.yml's push runs on main.
setup ahead
runs ci.yml.json "$(run "$OTHER" in_progress null push main)" "$(run "$OTHER" completed cancelled push main)" "$(green)"
check "newest-green skips running and cancelled runs" 0 "$SHA" --newest-green

setup ahead
runs ci.yml.json "$(run "$OTHER" completed cancelled push main)" "$(run "$OTHER" completed failure push main)" "$(green)"
check "newest-green: main is red" 1 "main is red (CI failure on $OTHER)" --newest-green

setup ahead
runs ci.yml.json "$(run "$OTHER" completed cancelled push main)"
check "newest-green: no verdict" 1 "no completed green CI run" --newest-green

echo
if [ "$fails" -gt 0 ]; then echo "test-release-gate: $fails of $n FAILED"; exit 1; fi
echo "test-release-gate: all $n passed"
