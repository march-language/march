#!/usr/bin/env bash
# Cross-language comparison for bench/string_small_churn.march.
#
# Purpose, singular: settle phase 2 Task 4 — is a size-class freelist (or a
# small-string optimization) worth building? See
# specs/2026-07-26-string-performance-profile.md.
#
# The four baselines are chosen to SEPARATE two explanations that a single
# number cannot distinguish:
#
#   Rust    String, NO small-string optimization — allocates per string exactly
#           as March does. If March trails Rust, the gap is allocator and
#           refcount overhead, which a freelist addresses.
#   C++     std::string, HAS small-string optimization — short strings live
#           inline with no allocation at all. Bounds the prize from inline
#           storage, a much larger change than a freelist. (The only C++ in this
#           repo, and here for exactly this reason.)
#   Python  CPython's pymalloc IS a size-class freelist for small objects —
#           close to the design under consideration, in a much slower language.
#   C       malloc per string, no header, no refcount — the floor.
#
# Honesty rules, same as bench/run_string_bench.sh:
#   * every implementation must print the SAME checksum. A mismatch means they
#     are not doing the same work, and the run FAILS rather than reporting
#     numbers nobody can compare.
#   * a missing toolchain is reported as SKIPPED, loudly. It is never silently
#     omitted, because a table with a missing row looks complete.
#   * load average is recorded; timings on a busy machine are not comparable.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH="$REPO_ROOT/_build/default/bin/main.exe"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

EXPECTED="checksum=17793810"
RUNS=3
FAILURES=0

NCPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
LOADAVG=$(uptime | sed 's/.*load average[s]*: //')
LOAD1=$(echo "$LOADAVG" | tr ',' ' ' | awk '{print $1+0}')
if awk -v l="$LOAD1" -v n="$NCPU" 'BEGIN { exit !(l+0 > n/2) }'; then
  echo "WARNING: 1-min load $LOAD1 on $NCPU cores — timings unreliable." >&2
fi

# Median of RUNS wall-clock milliseconds, or RUNFAIL.
timeit() {
  python3 - "$RUNS" "$@" <<'PYEOF'
import sys, time, subprocess
runs = int(sys.argv[1]); cmd = sys.argv[2:]
ts = []
for _ in range(runs):
    t = time.perf_counter()
    r = subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    ts.append((time.perf_counter() - t) * 1000.0)
    if r.returncode != 0:
        print("RUNFAIL"); sys.exit(0)
ts.sort()
print(f"{ts[len(ts)//2]:.1f}")
PYEOF
}

# report <label> <binary-or-command...>
report() {
  local label="$1"; shift
  local out
  out=$("$@" 2>/dev/null | grep '^checksum=' | head -1)
  if [ "$out" != "$EXPECTED" ]; then
    printf '  %-22s CHECKSUM MISMATCH (%s, expected %s)\n' "$label" "${out:-none}" "$EXPECTED" >&2
    FAILURES=$((FAILURES + 1)); return
  fi
  local ms; ms=$(timeit "$@")
  if [ "$ms" = "RUNFAIL" ]; then
    printf '  %-22s RUN FAILED\n' "$label" >&2
    FAILURES=$((FAILURES + 1)); return
  fi
  printf '  %-22s %8s ms\n' "$label" "$ms"
}

skip() { printf '  %-22s SKIPPED (%s not installed)\n' "$1" "$2"; }

echo "string_small_churn — 2M short-string build/concat/compare cycles"
echo "machine: $(uname -sm), ${NCPU} cores, load ${LOADAVG}"
echo

# ── March ────────────────────────────────────────────────────────────────
if [ -x "$MARCH" ]; then
  if "$MARCH" --compile --opt 2 "$REPO_ROOT/bench/string_small_churn.march" \
       -o "$TMP/march_churn" > "$TMP/march.log" 2>&1; then
    report "March" "$TMP/march_churn"
  else
    echo "  March                  COMPILE FAILED (see $TMP/march.log)" >&2
    FAILURES=$((FAILURES + 1))
  fi
else
  echo "  March                  SKIPPED (run: dune build --root . bin/main.exe)" >&2
  FAILURES=$((FAILURES + 1))
fi

# ── Rust (String, no SSO — the like-for-like control) ─────────────────────
if command -v rustc > /dev/null 2>&1; then
  rustc -O -o "$TMP/rust_churn" "$REPO_ROOT/bench/rust/string_small_churn.rs" 2>/dev/null \
    && report "Rust (no SSO)" "$TMP/rust_churn" \
    || { echo "  Rust                   COMPILE FAILED" >&2; FAILURES=$((FAILURES+1)); }
else
  skip "Rust (no SSO)" rustc
fi

# ── C++ (std::string, has SSO — bounds the prize) ─────────────────────────
if command -v c++ > /dev/null 2>&1; then
  c++ -O2 -std=c++17 -o "$TMP/cpp_churn" "$REPO_ROOT/bench/cpp/string_small_churn.cpp" 2>/dev/null \
    && report "C++ (std::string SSO)" "$TMP/cpp_churn" \
    || { echo "  C++                    COMPILE FAILED" >&2; FAILURES=$((FAILURES+1)); }
else
  skip "C++ (std::string SSO)" c++
fi

# ── C (malloc floor) ─────────────────────────────────────────────────────
if command -v cc > /dev/null 2>&1; then
  cc -O2 -o "$TMP/c_churn" "$REPO_ROOT/bench/c/string_small_churn.c" 2>/dev/null \
    && report "C (malloc)" "$TMP/c_churn" \
    || { echo "  C                      COMPILE FAILED" >&2; FAILURES=$((FAILURES+1)); }
else
  skip "C (malloc)" cc
fi

# ── Python (pymalloc size classes) ───────────────────────────────────────
if command -v python3 > /dev/null 2>&1; then
  report "Python (pymalloc)" python3 "$REPO_ROOT/bench/python/string_small_churn.py"
else
  skip "Python (pymalloc)" python3
fi

echo
if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES implementation(s) failed — the table above is incomplete." >&2
  exit 1
fi
echo "all implementations agree on $EXPECTED"
