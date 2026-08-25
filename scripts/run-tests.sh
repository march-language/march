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
#   scripts/run-tests.sh stdlib_march    # the .march stdlib test files
#   scripts/run-tests.sh test_jit        # the REPL-JIT / --jit alcotest suite
#
# Suites: compiler, eval, codegen, stdlib, stdlib_march, test_jit.  The first
# four are test/run_<name>.exe; stdlib_march is test/test_stdlib_march.exe,
# which runs the .march test files under test/stdlib/; test_jit is
# test/test_jit.exe, which drives the REPL JIT / `march --jit` as subprocesses
# of a freshly built bin/main.exe.
#
# Slow tests skipped by -q: repl_compiler_parity (JIT parity, ~5s),
#   compiled adversarial regressions (~5s), pbkdf2 key derivation (~3s), and
#   test_jit's ORC/clang REPL-session and --jit-file cases (~5-10s).
#
# test_jit is NOT a plain alcotest exe: `dune runtest` normally runs it with
# HOME and MARCH_BIN pinned (see the `(test (name test_jit) ...)` stanza in
# test/dune) because it spawns bin/main.exe as a subprocess for REPL/--jit
# sessions.  Running the built exe directly (as this script does for every
# suite) skips that env, and test_jit.ml's fallback path SILENTLY SKIPS
# (`Alcotest.(check pass)`, reported as a pass) whenever MARCH_BIN/main.exe or
# libLLVM isn't found — so this script sets MARCH_BIN and HOME itself, below,
# to keep the jit cases actually executing rather than vacuously skipping.
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
# Every alcotest executable in test/ that carries tests.  test_stdlib_march is
# NOT named run_* — it is a separate (test ...) stanza whose groups (the .march
# stdlib test files under test/stdlib/, and the distributed-OTP groups) exist
# nowhere else.  It was missing from this list, so a group registered there
# never ran under this script no matter which subset argument was passed, and a
# fully green run said nothing about it.  `dune runtest` did cover it, which is
# exactly why the gap was easy to miss locally.
ALL_RUNNERS=(run_compiler run_eval run_codegen run_stdlib test_stdlib_march test_jit)
QUICK_FLAG=""

# Map a suite name to its executable.  Accepts the bare name ("compiler",
# "stdlib_march"), or the exact exe name ("run_compiler").  An unknown name is
# a hard error: it used to build test/run_<typo>.exe and fail inside dune with
# a confusing "don't know how to build" instead of naming the mistake.
resolve_runner() {
  local arg="$1" r
  for r in "${ALL_RUNNERS[@]}"; do
    if [[ "$r" == "$arg" || "$r" == "run_${arg}" || "$r" == "test_${arg}" ]]; then
      echo "$r"; return 0
    fi
  done
  return 1
}

# Parse flags and suite names
RUNNERS=()
for arg in "$@"; do
  if [[ "$arg" == "-q" ]]; then
    QUICK_FLAG="-q"
  elif runner=$(resolve_runner "$arg"); then
    RUNNERS+=("$runner")
  else
    echo "unknown suite: ${arg}" >&2
    echo "known suites: ${ALL_RUNNERS[*]}" >&2
    exit 2
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
# bin/main.exe is a BUILD TARGET, not just a dependency of the runners: many
# tests shell out to the real compiler (native-compile fixtures, the LLVM IR
# validity gate, the capability-ceiling CLI tests), and dune does not rebuild
# it as a side effect of building test/*.exe. A stale one is served from the
# shared cache and fails as a bogus source-level error — twice observed:
# `unknown option '--no-cap-strict'` for a flag that was in bin/main.ml, and
# "I cannot find `I32x4`" for a stdlib type whose module was in the manifest.
# Neither looks like a stale binary; both cost a real debugging detour.
BUILD_TARGETS=("@test/stage-source-trees" "bin/main.exe")
for r in "${RUNNERS[@]}"; do
  BUILD_TARGETS+=("test/${r}.exe")
done
$DUNE build "${DUNE_ROOT[@]}" "${BUILD_TARGETS[@]}"

# Execution phase: run binaries directly — no dune RPC, no output buffering
FAILED=0
for runner in "${RUNNERS[@]}"; do
  echo ""
  echo "==> ${runner}"
  if [[ "$runner" == "test_jit" ]]; then
    # test_jit spawns bin/main.exe as a subprocess for REPL/--jit sessions
    # (see test/dune's `(test (name test_jit) ...)` stanza) and silently
    # SKIPS those cases — reported as passing — if MARCH_BIN doesn't resolve
    # to a real binary. Mirror dune's env here so the jit cases actually run
    # instead of vacuously skipping.
    mkdir -p "$PWD/_build/jit_home"
    if ! HOME="$PWD/_build/jit_home" MARCH_BIN="$PWD/_build/default/bin/main.exe" \
        $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e $QUICK_FLAG; then
      FAILED=1
    fi
  else
    if ! $TIMEOUT_CMD ./_build/default/test/${runner}.exe -e $QUICK_FLAG; then
      FAILED=1
    fi
  fi
done

echo ""
[[ $FAILED -eq 0 ]] && echo "All suites passed." || echo "One or more suites FAILED."
exit $FAILED
