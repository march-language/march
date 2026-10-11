#!/usr/bin/env bash
# tsan-wedge-loop.sh — regression loop for the MARCH_SANITIZE=thread wedge
# (specs/progress/2026-10-11-macos-tsan-scheduler-wedge.md). Not part of the
# default suite: it needs a working TSAN toolchain and takes ~1-2 minutes.
#
# Compiles test/native/run_until_idle_ping_pong.march (n cut to 1000) under
# TSAN and runs it RUNS times at 2 schedulers. Each run has a SIGALRM deadline
# (a wedged run exits 142; never kill -9 a wedged March process). On macOS each
# run is sandboxed without task-port access, so TSAN's atos symbolizer cannot
# start and falls back to in-process dladdr+demangle -- the deep-stack path
# that turned a TSAN report into a self-deadlock before the fix.
#
# Fails if any run wedges or prints a ThreadSanitizer report.
#
#   scripts/tsan-wedge-loop.sh [RUNS]     (default 20)
set -u
cd "$(dirname "$0")/.."
runs=${1:-20}
march=./_build/default/bin/main.exe
[ -x "$march" ] || { echo "build first: dune build --root . bin/main.exe test/native_actor_counter.out" >&2; exit 2; }

work=$(mktemp -d "${TMPDIR:-/tmp}/tsan-wedge.XXXXXX")
sed 's/let n = 200000/let n = 1000/' test/native/run_until_idle_ping_pong.march > "$work/pp.march"
if ! MARCH_SANITIZE=thread "$march" --compile -o "$work/pp" "$work/pp.march" > "$work/compile.log" 2>&1; then
  echo "TSAN compile failed:"; cat "$work/compile.log"; exit 2
fi

wrap=()
if [ "$(uname)" = Darwin ]; then
  wrap=(sandbox-exec -p '(version 1)(allow default)(deny mach-priv-task-port)')
fi

wedged=0; reported=0
for i in $(seq 1 "$runs"); do
  MARCH_NUM_SCHEDULERS=2 perl -e 'alarm shift; exec @ARGV' 30 "${wrap[@]}" "$work/pp" > "$work/out.$i" 2>&1
  rc=$?
  [ "$rc" = 142 ] && wedged=$((wedged + 1))
  grep -q "WARNING: ThreadSanitizer" "$work/out.$i" && reported=$((reported + 1))
  printf '%s ' "$rc"
done
echo
echo "wedged $wedged/$runs, runs with a TSAN report $reported/$runs (outputs in $work)"
[ "$wedged" = 0 ] && [ "$reported" = 0 ]
