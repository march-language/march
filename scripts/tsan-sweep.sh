#!/usr/bin/env bash
# tsan-sweep.sh — ThreadSanitizer sweep over test/native (not part of the
# default suite: it needs a working TSAN toolchain and takes a long time).
#
# Builds each test/native/<name>.march that has a <name>.expected with
# MARCH_SANITIZE=thread and runs it standalone at each scheduler count, with a
# SIGALRM deadline (never kill -9 a wedged March process). A run FAILS if it
# prints a ThreadSanitizer report or hits the deadline. Output that differs
# from the .expected, or a nonzero exit, is listed as a NOTE only: some
# fixtures expect a panic, and some need the environment their dune rule sets.
#
# Some fixtures are skipped, each with its reason (see skip_reason below).
# The 2026-10-12 sweep that this script records is described in
# specs/progress/2026-10-12-tsan-*.md and
# specs/todos/2026-10-12-tsan-sweep-uncovered-fixtures.md.
#
#   scripts/tsan-sweep.sh [-s "1 2 14"] [-t SECONDS] [NAME...]
#
# NAMEs restrict the sweep to those fixtures (default: all). Exit 0 iff no run
# failed.
set -u
cd "$(dirname "$0")/.."
scheds="1 2 14"; deadline=120
while getopts "s:t:" o; do
  case $o in
    s) scheds=$OPTARG ;;
    t) deadline=$OPTARG ;;
    *) echo "usage: $0 [-s \"1 2 14\"] [-t SECONDS] [NAME...]" >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
march=./_build/default/bin/main.exe
[ -x "$march" ] || { echo "build first: dune build --root . bin/main.exe test/native_actor_counter.out" >&2; exit 2; }

# Why a fixture is not swept (empty: swept).  A case statement, not an
# associative array: macOS ships bash 3.2.
skip_reason() {
  case "$1" in
    ffi_codec|ffi_codec2|ffi_interp_shim|ffi_optres)
      echo "needs the C objects its dune rule links" ;;
    js_*)
      echo "a --target js program, not native" ;;
    shell_*|observe_*|diagnose_runaway)
      echo "needs the client its dune rule starts (specs/todos/2026-10-12-tsan-sweep-uncovered-fixtures.md)" ;;
  esac
}

if [ $# -gt 0 ]; then names=("$@")
else
  names=()
  for f in test/native/*.march; do
    b=$(basename "$f" .march)
    [ -f "test/native/$b.expected" ] && names+=("$b")
  done
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/tsan-sweep.XXXXXX")
runs=0; failed=0; skipped=0; notes=0
for b in "${names[@]}"; do
  why=$(skip_reason "$b")
  if [ -n "$why" ]; then
    echo "  [$b] SKIP ($why)"; skipped=$((skipped + 1)); continue
  fi
  if ! MARCH_SANITIZE=thread "$march" --compile -o "$work/$b" "test/native/$b.march" \
       > "$work/$b.clog" 2>&1; then
    echo "  [$b] COMPILE FAIL (log: $work/$b.clog)"; failed=$((failed + 1)); continue
  fi
  for n in $scheds; do
    runs=$((runs + 1))
    MARCH_NUM_SCHEDULERS=$n perl -e 'alarm shift; exec @ARGV' "$deadline" "$work/$b" \
      > "$work/$b.$n.out" 2> "$work/$b.$n.err" < /dev/null
    rc=$?
    if grep -q "WARNING: ThreadSanitizer" "$work/$b.$n.err"; then
      echo "  [$b n=$n] TSAN REPORT (rc=$rc, $work/$b.$n.err)"; failed=$((failed + 1))
    elif [ "$rc" = 142 ]; then
      echo "  [$b n=$n] DEADLINE ${deadline}s"; failed=$((failed + 1))
    elif [ "$rc" != 0 ] || ! cmp -s "$work/$b.$n.out" "test/native/$b.expected"; then
      echo "  [$b n=$n] note: rc=$rc, output vs .expected differs or nonzero exit"
      notes=$((notes + 1))
    fi
  done
done
echo "=== tsan sweep: $runs runs, $failed failed, $notes notes, $skipped fixtures skipped (outputs in $work) ==="
[ "$failed" = 0 ]
