#!/usr/bin/env bash
# Regression test for scripts/run-tests.sh's FAILURE ATTRIBUTION.
#
# The defect this pins: run-tests.sh used to collapse every runner failure into
# a single `FAILED=1` bit and print only "One or more suites FAILED." That
# permits a genuinely misleading CI result, because a runner can print
# "Test Successful" and STILL exit non-zero -- a wrapper/launcher failure after
# the test process emitted its summary, a timeout kill, a signal. The reported
# output then contains no [FAIL] line anywhere and nothing naming the suite, so
# a failure around the stdlib runners is indistinguishable from a real test
# failure or from a runner that was never reached at all.
#
# So the central case below is exactly that: a fake runner that prints
# "Test Successful" and exits non-zero. A run-tests.sh that reports it only as
# an anonymous aggregate failure must fail this test.
#
# Driven through MARCH_TEST_RUNNER_ROOT / MARCH_TEST_SKIP_BUILD, which exist
# for this test alone -- no dune, no real runners, runs in well under a second.
#
# Usage: scripts/test-run-tests.sh

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")
SUT="$HERE/run-tests.sh"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/run-tests-test.XXXXXX")
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Build a fake runner tree: $TMP/root/test/<name>.exe behaving as told.
# $1 name, $2 exit status, $3 stdout text
make_runner() {
  mkdir -p "$TMP/root/test"
  cat > "$TMP/root/test/$1.exe" <<EOF
#!/usr/bin/env bash
echo "$3"
exit $2
EOF
  chmod +x "$TMP/root/test/$1.exe"
}

# Run the script under test against the fake tree. Captures combined output and
# the real exit status (NOT through a pipe, which would report the pipe's).
run_sut() {
  ( cd "$REPO" && MARCH_TEST_SKIP_BUILD=1 MARCH_TEST_RUNNER_ROOT="$TMP/root" \
      bash "$SUT" "$@" >"$TMP/out" 2>&1 )
  SUT_STATUS=$?
  SUT_OUT=$(cat "$TMP/out")
}

check() { # description, condition-already-evaluated via $?
  if [[ $1 -eq 0 ]]; then
    echo "  [OK]   $2"; PASS=$(( PASS + 1 ))
  else
    echo "  [FAIL] $2"; FAIL=$(( FAIL + 1 ))
    echo "--- captured output ---"; echo "$SUT_OUT"; echo "--- end ---"
  fi
}

contains() { case "$SUT_OUT" in *"$1"*) return 0;; *) return 1;; esac; }

echo "== case 1: a runner that prints 'Test Successful' and exits non-zero =="
# This is the headline case from the report: a successful-looking test summary
# followed by a launcher failure must be attributed to THAT runner by name.
make_runner run_compiler 3 "Test Successful in 1.000s. 42 tests run."
run_sut compiler
[[ $SUT_STATUS -ne 0 ]]; check $? "script still exits non-zero"
contains "run_compiler"; check $? "names the failing runner"
contains "exit status 3"; check $? "reports the original exit status (3)"
contains "Test Successful"; check $? "the runner's own misleading summary is still shown"
# The aggregate line alone is not enough -- it must not be the ONLY signal.
[[ $(echo "$SUT_OUT" | grep -c 'run_compiler') -ge 2 ]]; check $? "attributed at the failure point AND in the summary"

echo "== case 2: a runner killed by a signal =="
mkdir -p "$TMP/root/test"
cat > "$TMP/root/test/run_eval.exe" <<'EOF'
#!/usr/bin/env bash
echo "Test Successful in 0.100s. 7 tests run."
kill -9 $$
EOF
chmod +x "$TMP/root/test/run_eval.exe"
run_sut eval
[[ $SUT_STATUS -ne 0 ]]; check $? "script exits non-zero"
contains "signal 9"; check $? "decodes the signal number rather than printing a bare 137"
contains "run_eval"; check $? "names the runner"

echo "== case 3: a suite whose executable is missing never counts as passing =="
rm -rf "$TMP/root"; mkdir -p "$TMP/root"
run_sut codegen
[[ $SUT_STATUS -ne 0 ]]; check $? "script exits non-zero"
contains "NOT RUN"; check $? "distinguishes 'never started' from 'tests failed'"
contains "run_codegen"; check $? "names the unstarted runner"

echo "== case 4: several failures are ALL listed, not just the first =="
make_runner run_compiler 3 "Test Successful."
make_runner run_eval 5 "Test Successful."
make_runner run_codegen 0 "Test Successful."
run_sut compiler eval codegen
[[ $SUT_STATUS -ne 0 ]]; check $? "script exits non-zero"
contains "run_compiler"; check $? "lists run_compiler"
contains "run_eval"; check $? "lists run_eval"
contains "exit status 5"; check $? "keeps each runner's own status"
[[ $(echo "$SUT_OUT" | grep -c '^  - run_') -eq 2 ]]; check $? "summary lists exactly the 2 failures"

echo "== case 5: the all-green path is unchanged =="
make_runner run_compiler 0 "Test Successful."
make_runner run_eval 0 "Test Successful."
run_sut compiler eval
[[ $SUT_STATUS -eq 0 ]]; check $? "script exits 0"
contains "All suites passed."; check $? "still prints the all-passed line"
! contains "SUITE FAILED"; check $? "prints no failure attribution"

echo ""
echo "passed: $PASS   failed: $FAIL"
[[ $FAIL -eq 0 ]] || exit 1
