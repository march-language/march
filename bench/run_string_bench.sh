#!/usr/bin/env bash
# String performance harness (phase 1 measurement).
#
# Runs each bench/string_*.march benchmark compiled at --opt 2, five times,
# and reports median wall time, peak RSS, and the MARCH_STRING_STATS counters.
# See specs/2026-07-26-string-performance-design.md.
#
# Deliberate choices:
#   * python3 for timing and RSS rather than /usr/bin/time, whose output
#     format differs between macOS and Linux.
#   * Checksums are ASSERTED, not merely printed.  A benchmark whose work got
#     optimized away would otherwise report a wonderful number for doing
#     nothing, which is the classic way a perf suite lies.
#   * The stats pass is a SEPARATE, untimed run: instrumentation must never
#     contaminate the timings reported beside it.
#   * A failing benchmark is reported and the run continues, but the script
#     exits non-zero.  It never silently skips -- a perf suite that quietly
#     drops its hardest case is worse than no suite at all.
#
# Usage:
#   bash bench/run_string_bench.sh [name ...]
#   bash bench/run_string_bench.sh --verify-overhead
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH="$REPO_ROOT/_build/default/bin/main.exe"
OUT="$REPO_ROOT/bench/STRING_RESULTS.md"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RUNS=5
FAILURES=0

# Benchmark -> expected checksum.  Must match the `Expected output:` comment in
# each .march file and the entry in specs/benchmarks.md.  A benchmark whose
# knobs change needs its checksum updated in all three places.
expected_for() {
  case "$1" in
    string_scan)          echo "135000150" ;;
    string_case)          echo "200000000" ;;
    string_split_large)   echo "39000000"  ;;
    string_slice_walk)    echo "27000000"  ;;
    string_small_churn)   echo "17793810"  ;;
    string_parallel_scan) echo "16000000"  ;;
    *)                    echo ""          ;;
  esac
}

ALL_BENCHES="string_scan string_case string_split_large string_slice_walk
             string_small_churn string_parallel_scan"

if [ ! -x "$MARCH" ]; then
  echo "error: $MARCH not found. Run: dune build --root . bin/main.exe" >&2
  exit 1
fi

# Runs a command RUNS times; prints "median_ms min_ms max_ms peak_rss_bytes",
# or "RUNFAIL" if any run exits non-zero.
#
# ru_maxrss is BYTES on macOS and KILOBYTES on Linux.  Normalizing to bytes is
# the difference between a correct figure and a silent 1024x error.
timeit() {
  python3 - "$RUNS" "$@" <<'PYEOF'
import sys, time, subprocess, resource, platform
runs = int(sys.argv[1]); cmd = sys.argv[2:]
times = []
for _ in range(runs):
    start = time.perf_counter()
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    times.append((time.perf_counter() - start) * 1000.0)
    if r.returncode != 0:
        print("RUNFAIL 0 0 0"); sys.exit(0)
times.sort()
rss = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
if platform.system() != "Darwin":
    rss *= 1024                      # Linux reports kilobytes, macOS bytes
print(f"{times[len(times)//2]:.1f} {times[0]:.1f} {times[-1]:.1f} {rss}")
PYEOF
}

# --verify-overhead: the "zero cost when off" claim, checked rather than
# assumed.  Compares the most allocation-dense benchmark with the env var
# unset against MARCH_STRING_STATS=0 (both take the off path).  If merely
# having the counters compiled in costs more than 2%, every baseline number
# this harness reports is contaminated by its own instrumentation.
if [ "${1:-}" = "--verify-overhead" ]; then
  name=string_small_churn
  bin="$TMP/$name"
  if ! "$MARCH" --compile --opt 2 "$REPO_ROOT/bench/$name.march" -o "$bin" \
       > "$TMP/build.log" 2>&1; then
    echo "error: compile failed" >&2; sed -n '1,20p' "$TMP/build.log" >&2; exit 1
  fi
  read -r base _ _ _ <<< "$(timeit "$bin")"
  read -r off  _ _ _ <<< "$(MARCH_STRING_STATS=0 timeit "$bin")"
  echo "baseline ${base}ms   stats-off ${off}ms"
  awk -v a="$base" -v b="$off" 'BEGIN {
    pct = (b - a) / a * 100;
    printf "overhead %.2f%%\n", pct;
    exit (pct > 2.0) ? 1 : 0
  }' || { echo "FAIL: stats-off overhead exceeds 2%" >&2; exit 1; }
  echo "ok: overhead within 2%"
  exit 0
fi

if [ "$#" -gt 0 ]; then BENCHES="$*"; else BENCHES="$ALL_BENCHES"; fi

mb() { awk -v b="${1:-0}" 'BEGIN { printf "%.1f", b / 1048576 }'; }

# Load check, reported rather than enforced: a busy machine is a reason to
# distrust the timings, not a reason to refuse to measure memory.  Busy is
# defined as 1-minute load above half the core count.
NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
LOADAVG=$(uptime | sed 's/.*load average[s]*: //')
# macOS separates the three values with SPACES, Linux with COMMAS.  Normalize
# commas to spaces and force a numeric read (`+0`) -- a bare string like
# "29.88 21.66 22.16" compares LEXICALLY in awk, so "29.88..." > 7 is false and
# the warning silently never fires on exactly the busy machines it is for.
LOAD1=$(echo "$LOADAVG" | tr ',' ' ' | awk '{print $1+0}')
LOAD_BUSY=$(awk -v l="$LOAD1" -v n="$NCPU" 'BEGIN { print (l+0 > n/2) ? 1 : 0 }')
if [ "$LOAD_BUSY" = "1" ]; then
  echo "WARNING: 1-min load average $LOAD1 on $NCPU cores — timings will be unreliable." >&2
  echo "         Memory and allocation figures are unaffected." >&2
fi

{
  printf '# String Benchmark Results\n\n'
  printf 'Generated by `bench/run_string_bench.sh`. Median of %d runs, compiled `--opt 2`.\n' "$RUNS"
  printf 'Phase 1 of the string performance work — see `specs/2026-07-26-string-performance-design.md`.\n\n'
  printf 'Machine: %s, %s cores. %s\n\n' \
    "$(uname -sm)" "$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo '?')" "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  # Record load average WITH the results.  A run taken on a busy machine looks
  # identical to a clean one otherwise, and this repo is routinely worked in
  # from several worktrees at once -- one session running bench/fib.march
  # across every core doubled every timing here while leaving RSS untouched,
  # which reads as a performance regression if the load is not recorded.
  printf 'Load average at start: %s\n\n' "$LOADAVG"
  if [ "$LOAD_BUSY" = "1" ]; then
    printf '> ⚠️ **Timings on this run are NOT trustworthy**: 1-minute load average was %s on a\n' "$LOAD1"
    printf '> %s-core machine when it started. Peak RSS, allocation counts and copy volumes are\n' "$NCPU"
    printf '> load-independent and remain valid; wall-clock columns should be re-taken on an idle\n'
    printf '> machine before being compared against anything.\n\n'
  fi
  printf '| Benchmark | Median ms | Min | Max | Peak RSS MB | Str allocs | Obj allocs | Copied MB | Peak live MB |\n'
  printf '|---|---|---|---|---|---|---|---|---|\n'
} > "$OUT"

for name in $BENCHES; do
  src="$REPO_ROOT/bench/$name.march"
  bin="$TMP/$name"

  if [ ! -f "$src" ]; then
    echo "FAIL $name: no such benchmark ($src)" >&2
    printf '| %s | **NO SUCH BENCHMARK** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  if ! "$MARCH" --compile --opt 2 "$src" -o "$bin" > "$TMP/$name.build.log" 2>&1; then
    echo "FAIL $name: compile error (see $TMP/$name.build.log)" >&2
    sed -n '1,20p' "$TMP/$name.build.log" >&2
    printf '| %s | **COMPILE FAILED** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  # Correctness gate: the checksum proves the work actually happened.
  actual=$("$bin" 2>/dev/null | grep '^checksum=' | cut -d= -f2)
  want=$(expected_for "$name")
  if [ -z "$actual" ]; then
    echo "FAIL $name: no checksum= line in output" >&2
    printf '| %s | **NO CHECKSUM** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi
  if [ -z "$want" ]; then
    echo "FAIL $name: no expected checksum registered in expected_for()" >&2
    printf '| %s | **UNREGISTERED** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi
  if [ "$actual" != "$want" ]; then
    echo "FAIL $name: checksum $actual, expected $want" >&2
    printf '| %s | **CHECKSUM MISMATCH** (%s vs %s) | | | | | | | |\n' \
      "$name" "$actual" "$want" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  read -r med mn mx rss <<< "$(timeit "$bin")"
  if [ "$med" = "RUNFAIL" ]; then
    echo "FAIL $name: nonzero exit during timed run" >&2
    printf '| %s | **RUN FAILED** | | | | | | | |\n' "$name" >> "$OUT"
    FAILURES=$((FAILURES + 1)); continue
  fi

  # Stats pass: separate and untimed, so instrumentation never contaminates
  # the timings above.
  MARCH_STRING_STATS=1 "$bin" > /dev/null 2> "$TMP/$name.stats"
  stat_of() { grep "^march_string_stats $1 " "$TMP/$name.stats" | awk '{print $3}'; }

  printf '| %s | %s | %s | %s | %s | %s | %s | %s | %s |\n' \
    "$name" "$med" "$mn" "$mx" "$(mb "$rss")" \
    "$(stat_of allocs)" "$(stat_of obj_allocs)" \
    "$(mb "$(stat_of copy_bytes)")" "$(mb "$(stat_of peak_live_bytes)")" >> "$OUT"

  echo "ok   $name  ${med}ms  rss $(mb "$rss")MB  copied $(mb "$(stat_of copy_bytes)")MB"
done

if [ "$FAILURES" -gt 0 ]; then
  printf '\n**%d benchmark(s) failed — the results above are incomplete.**\n' "$FAILURES" >> "$OUT"
  echo "$FAILURES benchmark(s) failed" >&2
  exit 1
fi
echo "wrote $OUT"
