#!/usr/bin/env bash
# Cross-language benchmark runner: March vs Elixir, OCaml, Rust
#
# Benchmarks: fib(40), binary-trees(15), tree-transform(depth=20 x100), list-ops(1M)
# Each benchmark is run 10 times; median, min, and max times are reported.
#
# Usage: bash bench/run_benchmarks.sh
#   Optional: RUNS=20 bash bench/run_benchmarks.sh   (override iteration count)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BENCH_DIR="$REPO_ROOT/bench"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

RUNS="${RUNS:-10}"

# Paths
DUNE=/Users/80197052/.opam/march/bin/dune
OCAMLOPT=/Users/80197052/.opam/march/bin/ocamlopt
MARCH=/Users/80197052/.opam/march/bin/march
ELIXIR=$(command -v elixir 2>/dev/null || true)
RUSTC=$(command -v rustc 2>/dev/null || true)

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

# ── compile step ──────────────────────────────────────────────────────────────
bold "Compiling..."

# March (native via LLVM backend)
printf '  March... '
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/fib.march            -o "$TMP/march_fib"  2>/dev/null) && printf 'fib ' || printf '(fib FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/binary_trees.march   -o "$TMP/march_bt"   2>/dev/null) && printf 'bt '  || printf '(bt FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/tree_transform.march -o "$TMP/march_tt"   2>/dev/null) && printf 'tt '  || printf '(tt FAILED) '
(cd "$REPO_ROOT" && "$DUNE" exec march -- --compile --opt 2 bench/list_ops.march       -o "$TMP/march_lo"   2>/dev/null) && printf 'lo '  || printf '(lo FAILED) '
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

# Rust (rustc with optimisations)
printf '  Rust... '
if [ -n "$RUSTC" ]; then
  "$RUSTC" -O "$BENCH_DIR/rust/fib.rs"            -o "$TMP/rust_fib"  2>/dev/null && printf 'fib ' || printf '(fib FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/binary_trees.rs"   -o "$TMP/rust_bt"   2>/dev/null && printf 'bt '  || printf '(bt FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/tree_transform.rs" -o "$TMP/rust_tt"   2>/dev/null && printf 'tt '  || printf '(tt FAILED) '
  "$RUSTC" -O "$BENCH_DIR/rust/list_ops.rs"       -o "$TMP/rust_lo"   2>/dev/null && printf 'lo '  || printf '(lo FAILED) '
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

printf '\n'
bold "Done."
printf '  Source files: bench/elixir/  bench/ocaml/  bench/rust/\n'
printf '  March sources: bench/*.march  (compiled with --opt 2)\n'
