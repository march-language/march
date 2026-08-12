#!/usr/bin/env bash
# Agent-safe test runner.
#
# Separates build (dune RPC) from execution (direct binaries) so multiple
# agents can run tests concurrently without RPC contention.  Also wraps each
# runner with `timeout` so a single hung test can't block the whole suite.
#
# Usage:
#   scripts/run-tests.sh                 # full suite (~20-40 min, machine-dependent)
#   scripts/run-tests.sh -q              # quick only — skip Slow tests (~a few min)
#   scripts/run-tests.sh compiler eval   # run a subset by name
#   scripts/run-tests.sh -q stdlib       # quick subset
#
# Slow tests skipped by -q: repl_compiler_parity (JIT parity, ~5s),
#   compiled adversarial regressions (~5s), pbkdf2 key derivation (~3s).
#
# Environment:
#   MARCH_TEST_TIMEOUT  seconds per suite process  (default: 2400)
#   MARCH_DUNE_SHUTDOWN if non-empty, run `dune shutdown` first

set -euo pipefail

DUNE=${DUNE:-dune}
# This bounds ONE suite process (run_compiler/run_eval/run_codegen/run_stdlib),
# not the whole run — each runner below gets its own fresh $SUITE_TIMEOUT budget.
# Measured suite-process wall times (root-caused via bpftrace on ubuntu-24.04 CI):
#   run_codegen:  ~670s on GitHub ubuntu-24.04 runners; ~1790-1825s on a 4-vCPU droplet
#   run_compiler: ~160-500s
#   run_stdlib:   ~180-240s
#   run_eval:     ~1-20s
# 300s fired mid-run on the slowest legitimate run_codegen invocations. GNU
# `timeout` signals the whole process group, so a fire SIGTERMs the runner AND
# any in-flight `march`/`clang` children it spawned — the killed compiler
# process then produces EMPTY output with a WSIGNALED status, which surfaces
# as a bogus "compiler crashed" failure on a random test, not as an obvious
# timeout. 2400s sits safely above the ~1825s worst observed run; raise it
# further if a slower CI tier is added rather than lowering it back toward 300.
SUITE_TIMEOUT=${MARCH_TEST_TIMEOUT:-2400}

# Pin the dune root to the invocation directory.  Claude worktrees live at
# .claude/worktrees/<name> inside the main repo, so dune's upward root search
# escapes to the outer repo and can't see the worktree's targets.  --root must
# come AFTER the subcommand (this dune rejects `dune --root . build`).
DUNE_ROOT=(--root "$PWD")

# timeout(1) is GNU coreutils; macOS users can `brew install coreutils` for gtimeout.
# Plain macOS (no coreutils) has neither `timeout` nor `gtimeout`, so
# TIMEOUT_CMD falls through to "" below and runs are UNBOUNDED there. This
# guard is therefore effectively Linux-only: a local macOS run will NOT
# reproduce timeout-induced failures (e.g. the empty-output "compiler
# crashed" symptom above) even when CI hits them, because macOS never fires
# the timeout in the first place.
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
  $DUNE shutdown "${DUNE_ROOT[@]}" 2>/dev/null || true
fi

# Build phase: dune handles concurrent build requests internally
echo "==> dune build"
# @test/stage-source-trees carries no action: it exists so dune refreshes its
# COPIES of runtime/ and stdlib/ under _build/default. Tests that shell out to
# the compiler for a native compile link and read those copies, and building
# only test/*.exe does not refresh them — a stale copy has shown up as an
# undefined-symbol link error and as a --cap-sandbox binary with no embedded
# profile, neither of which is a real March bug. See the rule in test/dune.
BUILD_TARGETS=("@test/stage-source-trees")
for r in "${RUNNERS[@]}"; do
  BUILD_TARGETS+=("test/${r}.exe")
done
$DUNE build "${DUNE_ROOT[@]}" "${BUILD_TARGETS[@]}"

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
