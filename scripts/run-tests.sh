#!/usr/bin/env bash
# Agent-safe test runner.
#
# Separates build (dune RPC) from execution (direct binaries) so multiple
# agents can run tests concurrently without RPC contention.  Also wraps each
# runner with `timeout` so a single hung test can't block the whole suite.
#
# Usage:
#   scripts/run-tests.sh                 # run all four suites
#   scripts/run-tests.sh compiler eval   # run a subset by name
#
# Environment:
#   MARCH_TEST_TIMEOUT  seconds per suite process  (default: 300)
#   MARCH_DUNE_SHUTDOWN if non-empty, run `dune shutdown` first

set -euo pipefail

DUNE=${DUNE:-dune}
SUITE_TIMEOUT=${MARCH_TEST_TIMEOUT:-300}

# timeout(1) is GNU coreutils; macOS users can `brew install coreutils` for gtimeout.
if command -v timeout &>/dev/null; then
  TIMEOUT_CMD="timeout $SUITE_TIMEOUT"
elif command -v gtimeout &>/dev/null; then
  TIMEOUT_CMD="gtimeout $SUITE_TIMEOUT"
else
  TIMEOUT_CMD=""  # no timeout available; runs unbounded
fi
ALL_RUNNERS=(run_compiler run_eval run_codegen run_stdlib)

# Allow caller to specify a subset: scripts/run-tests.sh compiler stdlib
if [[ $# -gt 0 ]]; then
  RUNNERS=()
  for arg in "$@"; do
    RUNNERS+=("run_${arg}")
  done
else
  RUNNERS=("${ALL_RUNNERS[@]}")
fi

# Optionally clear stale daemon before starting (useful after a crashed session)
if [[ -n "${MARCH_DUNE_SHUTDOWN:-}" ]]; then
  echo "==> dune shutdown (clearing stale daemon)"
  $DUNE shutdown 2>/dev/null || true
fi

# Build phase: dune handles concurrent build requests internally
echo "==> dune build"
BUILD_TARGETS=()
for r in "${RUNNERS[@]}"; do
  BUILD_TARGETS+=("test/${r}.exe")
done
$DUNE build "${BUILD_TARGETS[@]}"

# Execution phase: run binaries directly — no dune RPC, no output buffering
FAILED=0
for runner in "${RUNNERS[@]}"; do
  echo ""
  echo "==> ${runner}"
  if ! $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e; then
    FAILED=1
  fi
done

echo ""
[[ $FAILED -eq 0 ]] && echo "All suites passed." || echo "One or more suites FAILED."
exit $FAILED
