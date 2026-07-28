#!/usr/bin/env bash
# Cross-language benchmark runner: March vs Elixir, OCaml, Rust, Python (+ NumPy)
#
# Benchmarks: fib(40), binary-trees(15), tree-transform(depth=20 x100), list-ops(1M),
# simd-sum/simd-map/simd-map2 (N=5M Float array ops — see docs/simd-vectorization.md).
# Each benchmark is run 10 times; median, min, and max times are reported.
#
# Usage: bash bench/run_benchmarks.sh
#   Optional: RUNS=20 bash bench/run_benchmarks.sh   (override iteration count)
#
# The simd-* benchmarks' NumPy row needs a local venv with numpy installed
# (not committed — python3 -m venv bench/.venv && bench/.venv/bin/pip install numpy);
# every other row and benchmark runs without it.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH_DIR="$REPO_ROOT/bench"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RUNS="${RUNS:-10}"

# Paths
DUNE=/Users/80197052/.opam/march/bin/dune
OCAMLOPT=/Users/80197052/.opam/march/bin/ocamlopt
OCAMLFIND=/Users/80197052/.opam/march/bin/ocamlfind
MARCH=/Users/80197052/.opam/march/bin/march
ELIXIR=$(command -v elixir 2>/dev/null || true)
RUSTC=$(command -v rustc 2>/dev/null || true)
PYTHON3=$(command -v python3 2>/dev/null || true)
NUMPY_PY=""
[ -x "$BENCH_DIR/.venv/bin/python" ] && NUMPY_PY="$BENCH_DIR/.venv/bin/python"

# ── formatting helpers ────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }
header(){ printf '\n'; bold "═══ $* ═══"; printf '  %-12s %8s %8s %8s\n' "Language" "Median" "Min" "Max"; printf '  %-12s %8s %8s %8s\n' "--------" "------" "---" "---"; }
row()   { printf '  %-12s %7.1f ms %6.1f ms %6.1f ms\n' "$1" "$2" "$3" "$4"; }
skip()  { printf '  %-12s   (not available)\n' "$1"; }

# ── timing: run a command $RUNS times, print "median min max" (ms) to stdout ─
# Outputs three space-separated floats: median min max
time_stats() {
  python3 - "$RUNS" "$@" <<'PYEOF'
import sys, time, subprocess
runs = int(sys.argv[1])
cmd  = sys.argv[2:]
times = []
for _ in range(runs):
    t0 = time.perf_counter()
    subprocess.run(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
    times.append((time.perf_counter() - t0) * 1000.0)
times.sort()
mid = len(times) // 2
median = (times[mid - 1] + times[mid]) / 2 if len(times) % 2 == 0 else times[mid]
print(f"{median:.1f} {times[0]:.1f} {times[-1]:.1f}")
PYEOF
}

# Helper: read the three stats and call row()
show() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    read -r median min max < <(time_stats "$@")
    row "$label" "$median" "$min" "$max"
  else
    skip "$label"
  fi
}

show_interp() {
  local label="$1" interp="$2"; shift 2
  if command -v "$interp" >/dev/null 2>&1; then
    read -r median min max < <(time_stats "$interp" "$@")
    row "$label" "$median" "$min" "$max"
  else
    skip "$label"
  fi
}

# ── self-timed: run a program $RUNS times, parse its own "TIME_MS <float>"
# line instead of measuring subprocess wall-clock. The simd-* benchmarks
# self-time only the operation (excluding data generation and, for
# interpreters, process startup) — see bench/simd_sum.march for why; using
# subprocess wall-clock here would mostly measure interpreter startup and
# data-generation cost, not the operation under test.
self_timed_stats() {
  python3 - "$RUNS" "$@" <<'PYEOF'
import sys, subprocess
runs = int(sys.argv[1])
cmd  = sys.argv[2:]
times = []
for _ in range(runs):
    out = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True, text=True).stdout
    for line in out.splitlines():
        if line.startswith("TIME_MS "):
            times.append(float(line.split(None, 1)[1]))
            break
times.sort()
mid = len(times) // 2
median = (times[mid - 1] + times[mid]) / 2 if len(times) % 2 == 0 else times[mid]
print(f"{median:.3f} {times[0]:.3f} {times[-1]:.3f}")
PYEOF
}

show_self_timed() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    read -r median min max < <(self_timed_stats "$@")
    row "$label" "$median" "$min" "$max"
  else
    skip "$label"
  fi
}

show_interp_self_timed() {
  local label="$1" interp="$2"; shift 2
  if command -v "$interp" >/dev/null 2>&1; then
    read -r median min max < <(self_timed_stats "$interp" "$@")
    row "$label" "$median" "$min" "$max"
  else
    skip "$label"
  fi
}

# ── compile step ──────────────────────────────────────────────────────────────
bold "Compiling..."

# March (native via LLVM backend)
printf '  March... '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/fib.march            -o "$TMP/march_fib"  2>/dev/null) && printf 'fib ' || printf '(fib FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/binary_trees.march   -o "$TMP/march_bt"   2>/dev/null) && printf 'bt '  || printf '(bt FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/tree_transform.march -o "$TMP/march_tt"   2>/dev/null) && printf 'tt '  || printf '(tt FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/list_ops.march       -o "$TMP/march_lo"   2>/dev/null) && printf 'lo '  || printf '(lo FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/simd_sum.march       -o "$TMP/march_ss"   2>/dev/null) && printf 'ss '  || printf '(ss FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/simd_map.march       -o "$TMP/march_sm"   2>/dev/null) && printf 'sm '  || printf '(sm FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --compile --opt 2 bench/simd_map2.march      -o "$TMP/march_sm2"  2>/dev/null) && printf 'sm2 ' || printf '(sm2 FAILED) '
printf '\n'

# OCaml (ocamlopt native compiler)
printf '  OCaml... '
if [ -x "$OCAMLOPT" ]; then
  "$OCAMLOPT" "$BENCH_DIR/ocaml/fib.ml"            -o "$TMP/ocaml_fib"  2>/dev/null && printf 'fib ' || printf '(fib FAILED) '
  "$OCAMLOPT" "$BENCH_DIR/ocaml/binary_trees.ml"   -o "$TMP/ocaml_bt"   2>/dev/null && printf 'bt '  || printf '(bt FAILED) '
  "$OCAMLOPT" "$BENCH_DIR/ocaml/tree_transform.ml" -o "$TMP/ocaml_tt"   2>/dev/null && printf 'tt '  || printf '(tt FAILED) '
  "$OCAMLOPT" "$BENCH_DIR/ocaml/list_ops.ml"       -o "$TMP/ocaml_lo"   2>/dev/null && printf 'lo '  || printf '(lo FAILED) '
  printf '\n'
else
  printf '(ocamlopt not found)\n'
fi
# simd-* OCaml benchmarks self-time via Unix.gettimeofday, so link the unix package.
if [ -x "$OCAMLFIND" ]; then
  printf '  OCaml (simd)... '
  "$OCAMLFIND" ocamlopt -package unix -linkpkg "$BENCH_DIR/ocaml/simd_sum.ml"  -o "$TMP/ocaml_ss"  2>/dev/null && printf 'ss '  || printf '(ss FAILED) '
  "$OCAMLFIND" ocamlopt -package unix -linkpkg "$BENCH_DIR/ocaml/simd_map.ml"  -o "$TMP/ocaml_sm"  2>/dev/null && printf 'sm '  || printf '(sm FAILED) '
  "$OCAMLFIND" ocamlopt -package unix -linkpkg "$BENCH_DIR/ocaml/simd_map2.ml" -o "$TMP/ocaml_sm2" 2>/dev/null && printf 'sm2 ' || printf '(sm2 FAILED) '
  printf '\n'
else
  printf '  OCaml (simd)... (ocamlfind not found)\n'
fi

# Rust (rustc with optimisations)
printf '  Rust... '
if [ -n "$RUSTC" ]; then
  "$RUSTC" -O "$BENCH_DIR/rust/fib.rs"            -o "$TMP/rust_fib"  2>/dev/null && printf 'fib ' || printf '(fib FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/binary_trees.rs"   -o "$TMP/rust_bt"   2>/dev/null && printf 'bt '  || printf '(bt FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/tree_transform.rs" -o "$TMP/rust_tt"   2>/dev/null && printf 'tt '  || printf '(tt FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/list_ops.rs"       -o "$TMP/rust_lo"   2>/dev/null && printf 'lo '  || printf '(lo FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/simd_sum.rs"       -o "$TMP/rust_ss"   2>/dev/null && printf 'ss '  || printf '(ss FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/simd_map.rs"       -o "$TMP/rust_sm"   2>/dev/null && printf 'sm '  || printf '(sm FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/simd_map2.rs"      -o "$TMP/rust_sm2"  2>/dev/null && printf 'sm2 ' || printf '(sm2 FAILED) '
  printf '\n'
else
  printf '(rustc not found)\n'
fi

# Elixir: interpreted (BEAM JIT) — no ahead-of-time compilation step needed
if [ -n "$ELIXIR" ]; then
  printf '  Elixir... (script mode, BEAM JIT)\n'
else
  printf '  Elixir... (not found)\n'
fi

# Python / NumPy: interpreted — no ahead-of-time compilation step needed
if [ -n "$PYTHON3" ]; then
  printf '  Python... (interpreted)\n'
else
  printf '  Python... (not found)\n'
fi
if [ -n "$NUMPY_PY" ]; then
  printf '  NumPy...  (bench/.venv)\n'
else
  printf '  NumPy...  (not set up — python3 -m venv bench/.venv && bench/.venv/bin/pip install numpy)\n'
fi

# ── run benchmarks ────────────────────────────────────────────────────────────
printf '\n'
dim "Running each benchmark $RUNS times. Reporting median / min / max wall-clock time."

# ── fib(40) ───────────────────────────────────────────────────────────────────
header "fib(40) — naive recursive"
[ -x "$TMP/march_fib"  ] && show "March"  "$TMP/march_fib"              || skip "March"
[ -x "$TMP/ocaml_fib"  ] && show "OCaml"  "$TMP/ocaml_fib"              || skip "OCaml"
[ -x "$TMP/rust_fib"   ] && show "Rust"   "$TMP/rust_fib"               || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp "Elixir" elixir "$BENCH_DIR/elixir/fib.exs" || skip "Elixir"

# ── binary-trees(15) ─────────────────────────────────────────────────────────
header "binary-trees(15) — alloc/GC stress"
printf '  (Allocates and walks complete binary trees; stresses allocator and GC.)\n'
[ -x "$TMP/march_bt"   ] && show "March"  "$TMP/march_bt"               || skip "March"
[ -x "$TMP/ocaml_bt"   ] && show "OCaml"  "$TMP/ocaml_bt"               || skip "OCaml"
[ -x "$TMP/rust_bt"    ] && show "Rust"   "$TMP/rust_bt"                || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp "Elixir" elixir "$BENCH_DIR/elixir/binary_trees.exs" || skip "Elixir"

# ── tree-transform (FBIP showcase) ───────────────────────────────────────────
header "tree-transform(depth=20, 100 passes) — Perceus FBIP showcase"
printf '  March rewrites leaf values in-place (RC=1, zero alloc after first pass).\n'
printf '  OCaml/Rust allocate a fresh tree each pass.\n'
printf '  Elixir is purely functional; allocates fresh nodes each pass on BEAM.\n'
[ -x "$TMP/march_tt"   ] && show "March"  "$TMP/march_tt"               || skip "March"
[ -x "$TMP/ocaml_tt"   ] && show "OCaml"  "$TMP/ocaml_tt"               || skip "OCaml"
[ -x "$TMP/rust_tt"    ] && show "Rust"   "$TMP/rust_tt"                || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp "Elixir" elixir "$BENCH_DIR/elixir/tree_transform.exs" || skip "Elixir"

# ── list-ops (HOF pipeline) ───────────────────────────────────────────────────
header "list-ops(1M) — map/filter/fold HOF pipeline"
printf '  range(1..1M) |> map(*2) |> filter(%%3=0) |> sum.\n'
printf '  Rust iterators fuse into a single loop (zero allocation).\n'
printf '  March, OCaml, Elixir allocate intermediate lists.\n'
[ -x "$TMP/march_lo"   ] && show "March"  "$TMP/march_lo"               || skip "March"
[ -x "$TMP/ocaml_lo"   ] && show "OCaml"  "$TMP/ocaml_lo"               || skip "OCaml"
[ -x "$TMP/rust_lo"    ] && show "Rust"   "$TMP/rust_lo"                || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp "Elixir" elixir "$BENCH_DIR/elixir/list_ops.exs" || skip "Elixir"

# ── simd-sum(5M) — Float array reduction ─────────────────────────────────────
header "simd-sum(5M) — Float array reduction"
printf '  sum(arr). March native_float_arr_sum auto-vectorizes at -O2 (see docs/simd-vectorization.md).\n'
printf '  Self-timed: each program times only the operation itself (excludes data\n'
printf '  generation / interpreter startup) and reports it via a TIME_MS line.\n'
[ -x "$TMP/march_ss"   ] && show_self_timed "March"  "$TMP/march_ss"               || skip "March"
[ -x "$TMP/ocaml_ss"   ] && show_self_timed "OCaml"  "$TMP/ocaml_ss"               || skip "OCaml"
[ -x "$TMP/rust_ss"    ] && show_self_timed "Rust"   "$TMP/rust_ss"                || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp_self_timed "Elixir" elixir "$BENCH_DIR/elixir/simd_sum.exs" || skip "Elixir"
[ -n "$PYTHON3"        ] && show_interp_self_timed "Python" "$PYTHON3" "$BENCH_DIR/python/simd_sum.py" || skip "Python"
[ -n "$NUMPY_PY"       ] && show_interp_self_timed "NumPy"  "$NUMPY_PY" "$BENCH_DIR/python/simd_sum_numpy.py" || skip "NumPy"

# ── simd-map(5M) — elementwise Float map ─────────────────────────────────────
header "simd-map(5M) — elementwise (x * 2.0 + 1.0)"
printf '  March map_float, with a concrete-Float single-use callback, gets the boxing-free\n'
printf '  inlined clone (Stage 4 Option B) and genuinely vectorizes. Self-timed (see above).\n'
[ -x "$TMP/march_sm"   ] && show_self_timed "March"  "$TMP/march_sm"               || skip "March"
[ -x "$TMP/ocaml_sm"   ] && show_self_timed "OCaml"  "$TMP/ocaml_sm"               || skip "OCaml"
[ -x "$TMP/rust_sm"    ] && show_self_timed "Rust"   "$TMP/rust_sm"                || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp_self_timed "Elixir" elixir "$BENCH_DIR/elixir/simd_map.exs" || skip "Elixir"
[ -n "$PYTHON3"        ] && show_interp_self_timed "Python" "$PYTHON3" "$BENCH_DIR/python/simd_map.py" || skip "Python"
[ -n "$NUMPY_PY"       ] && show_interp_self_timed "NumPy"  "$NUMPY_PY" "$BENCH_DIR/python/simd_map_numpy.py" || skip "NumPy"

# ── simd-map2(5M) — elementwise two-array zip ────────────────────────────────
header "simd-map2(5M) — elementwise (a[i] + b[i])"
printf '  March map2_float is correct but NOT YET vectorized/inlined (see docs/simd-vectorization.md\n'
printf '  "Known limitations") — included deliberately so the numbers stay honest. Self-timed.\n'
[ -x "$TMP/march_sm2"  ] && show_self_timed "March"  "$TMP/march_sm2"              || skip "March"
[ -x "$TMP/ocaml_sm2"  ] && show_self_timed "OCaml"  "$TMP/ocaml_sm2"              || skip "OCaml"
[ -x "$TMP/rust_sm2"   ] && show_self_timed "Rust"   "$TMP/rust_sm2"               || skip "Rust"
[ -n "$ELIXIR"         ] && show_interp_self_timed "Elixir" elixir "$BENCH_DIR/elixir/simd_map2.exs" || skip "Elixir"
[ -n "$PYTHON3"        ] && show_interp_self_timed "Python" "$PYTHON3" "$BENCH_DIR/python/simd_map2.py" || skip "Python"
[ -n "$NUMPY_PY"       ] && show_interp_self_timed "NumPy"  "$NUMPY_PY" "$BENCH_DIR/python/simd_map2_numpy.py" || skip "NumPy"

printf '\n'
bold "Done."
printf '  Source files: bench/elixir/  bench/ocaml/  bench/rust/  bench/python/\n'
printf '  March sources: bench/*.march  (compiled with --opt 2)\n'
