#!/usr/bin/env bash
# bench-grants.sh — the cost of a dependency-grant boundary call (ocap phase 6).
#
# Builds three binaries from bench/grant_enter*.march against the dependency in
# bench/grant_enter_dep/ (on MARCH_LIB_PATH), all at --opt 2:
#
#   framed    bench/grant_enter.march under a scoped grant
#             (grant_dep: IO.FileRead("/srv/")): every app -> dep call enters
#             the grant frame
#   static    bench/grant_enter_static.march under an unscoped grant
#             (grant_dep: IO.FileRead): the package is proven pure, so its
#             frames are dropped and each call is a plain call
#   control   bench/grant_enter.march with no grants file: the dependency is
#             ordinary lib-path code
#
# Each program makes 1,000,000 boundary calls, each doing 1,000 internal
# dependency calls, and prints 500000500000000. It checks that the grant-frame
# decisions are the expected ones (MARCH_DUMP_GRANT_FRAMES), that all three
# print the same answer, then runs them interleaved (default 11 rounds) and
# prints the median and minimum wall time of each, and
#
#   ns per boundary call = (median(variant) - median(control)) / 1e6
#
# The phase-6 budget is <= 50 ns for the framed call and within noise for the
# static one (specs/plans/2026-11-22-ocap-p6-grants-plan.md, "Performance").
# Watch the load average it prints: on a shared machine a load above about
# twice the core count makes the numbers lie.
#
# Usage: scripts/bench-grants.sh [--runs N] [--keep]
#   MARCH_BIN=<compiler>   use this compiler (default: _build/default/bin/main.exe,
#                          built with `dune build --root . bin/main.exe` if missing)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
RUNS=11
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --keep) KEEP=1; shift ;;
    -h|--help) sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "bench-grants.sh: unknown argument $1" >&2; exit 2 ;;
  esac
done

MARCH="${MARCH_BIN:-$ROOT/_build/default/bin/main.exe}"
if [ ! -x "$MARCH" ]; then
  (cd "$ROOT" && dune build --root . bin/main.exe)
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bench-grants.XXXXXX")"
if [ "$KEEP" = 0 ]; then trap 'rm -rf "$WORK"' EXIT; else echo "work dir: $WORK"; fi

mkdir "$WORK/grant_enter_dep"
cp "$ROOT"/bench/grant_enter_dep/*.march "$WORK/grant_enter_dep/"
# The entries go in their own directory: a granted library root inside the
# entry's directory is a dep_module_conflict.
mkdir "$WORK/app"
cp "$ROOT/bench/grant_enter.march" "$ROOT/bench/grant_enter_static.march" "$WORK/app/"
DEP="$(cd "$WORK/grant_enter_dep" && pwd -P)"
printf 'grant_dep\t%s\tforge.toml:1\tIO.FileRead("/srv/")\n' "$DEP" > "$WORK/grants.scoped"
printf 'grant_dep\t%s\tforge.toml:1\tIO.FileRead\n' "$DEP" > "$WORK/grants.static"

build() { # out src [grants]
  local out="$1" src="$2" grants="${3:-}" frames="$WORK/$1.frames"
  local flag=()
  [ -n "$grants" ] && flag=(--dep-grants "$WORK/$grants")
  if ! (cd "$WORK/app" && MARCH_DUMP_GRANT_FRAMES=1 MARCH_LIB_PATH="$DEP" \
          "$MARCH" --compile --opt 2 ${flag[@]+"${flag[@]}"} "$src" -o "$WORK/$out" \
          > "$WORK/$out.log" 2>&1); then
    echo "bench-grants.sh: compiling $out failed:" >&2
    cat "$WORK/$out.log" >&2
    exit 1
  fi
  grep '^grant-frame ' "$WORK/$out.log" > "$frames" || true
}

expect_frames() { # out wrapped(true|false|none)
  local out="$1" want="$2" frames="$WORK/$1.frames"
  if [ "$want" = none ]; then
    if [ -s "$frames" ]; then
      echo "bench-grants.sh: $out has grant frames with no grants file:" >&2
      cat "$frames" >&2; exit 1
    fi
    return
  fi
  local n bad
  n=$(grep -c "pkg=grant_dep" "$frames" || true)
  bad=$(grep -vc "wrapped=$want" "$frames" || true)
  if [ "$n" -lt 3 ] || [ "$bad" -ne 0 ]; then
    echo "bench-grants.sh: $out: expected every GrantDep fn wrapped=$want, got:" >&2
    cat "$frames" >&2; exit 1
  fi
}

echo "building (march: $MARCH) ..."
build framed  grant_enter.march        grants.scoped
build static  grant_enter_static.march grants.static
build control grant_enter.march
expect_frames framed  true
expect_frames static  false
expect_frames control none

WANT=500000500000000
for b in framed static control; do
  got="$("$WORK/$b")"
  if [ "$got" != "$WANT" ]; then
    echo "bench-grants.sh: $b printed '$got', expected $WANT" >&2; exit 1
  fi
done

echo "load average: $(uptime | sed 's/.*load averages*: *//')  (cores: $(sysctl -n hw.ncpu 2>/dev/null || nproc))"
python3 -I - "$WORK" "$RUNS" <<'PY'
import statistics, subprocess, sys, time
work, runs = sys.argv[1], int(sys.argv[2])
names = ["framed", "static", "control"]
times = {n: [] for n in names}
for r in range(runs):
    # rotate the order each round so no variant always runs first
    for n in names[r % 3:] + names[:r % 3]:
        t0 = time.perf_counter()
        subprocess.run([f"{work}/{n}"], stdout=subprocess.DEVNULL, check=True)
        times[n].append(time.perf_counter() - t0)
med = {n: statistics.median(times[n]) * 1e3 for n in names}
mn = {n: min(times[n]) * 1e3 for n in names}
calls = 1_000_000
print(f"\n{runs} interleaved runs, --opt 2, wall time (ms)\n")
print("| variant | grant | frames | median ms | min ms | ns per boundary call (median) | (min) |")
print("|---|---|---|---:|---:|---:|---:|")
rows = [("framed", 'IO.FileRead("/srv/")', "kept"),
        ("static", "IO.FileRead", "dropped"),
        ("control", "none", "none")]
for n, g, f in rows:
    if n == "control":
        d1 = d2 = "-"
    else:
        d1 = f"{(med[n] - med['control']) * 1e6 / calls:.1f}"
        d2 = f"{(mn[n] - mn['control']) * 1e6 / calls:.1f}"
    print(f"| {n} | `{g}` | {f} | {med[n]:.1f} | {mn[n]:.1f} | {d1} | {d2} |")
print("\nbudget: framed <= 50 ns per boundary call; static within noise of control")
PY
