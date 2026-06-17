#!/usr/bin/env bash
# Agent-safe test runner.
#
# Separates build (dune RPC) from execution (direct binaries) so multiple
# agents can run tests concurrently without RPC contention.  Also wraps each
# runner with `timeout` so a single hung test can't block the whole suite.
#
# Usage:
#   scripts/run-tests.sh                 # full suite (~17s)
#   scripts/run-tests.sh -q              # quick only — skip Slow tests (~2s)
#   scripts/run-tests.sh compiler eval   # run a subset by name
#   scripts/run-tests.sh -q stdlib       # quick subset
#
# Slow tests skipped by -q: repl_compiler_parity (JIT parity, ~5s),
#   compiled adversarial regressions (~5s), pbkdf2 key derivation (~3s).
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
QUICK_FLAG=""

# Parse flags and suite names
RUNNERS=()
for arg in "$@"; do
  if [[ "$arg" == "-q" ]]; then
    QUICK_FLAG="-q"
  else
    RUNNERS+=("run_${arg}")
  fi
done
[[ ${#RUNNERS[@]} -eq 0 ]] && RUNNERS=("${ALL_RUNNERS[@]}")

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
  if ! $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e $QUICK_FLAG; then
    FAILED=1
  fi
done

echo ""
[[ $FAILED -eq 0 ]] && echo "All suites passed." || echo "One or more suites FAILED."
exit $FAILED
