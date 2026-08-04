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

# ── Toolchain discovery ──────────────────────────────────────────────────────
# PATH first, then the conventional opam switch. These used to be absolute paths
# into one developer's switch, which made the published numbers unreproducible in
# a specific and quiet way: a missing tool does not fail here, it drops that
# language's ROW. Anyone else running the command the docs tell them to run got a
# smaller comparison and no indication that it was smaller. Every resolved path
# and every omission is now printed before any timing (see the toolchain banner).
#
# Override any of these from the environment if your tools live elsewhere:
#   MARCH=/path/to/march bash bench/run_benchmarks.sh
OPAM_BIN="${OPAM_SWITCH_BIN:-$HOME/.opam/march/bin}"

find_tool() {                      # find_tool VAR_VALUE name…
  local preset="$1"; shift
  if [ -n "$preset" ]; then printf '%s' "$preset"; return; fi
  local n
  for n in "$@"; do
    local p
    p="$(command -v "$n" 2>/dev/null || true)"
    [ -n "$p" ] && { printf '%s' "$p"; return; }
    [ -x "$OPAM_BIN/$n" ] && { printf '%s' "$OPAM_BIN/$n"; return; }
  done
  printf ''
}

DUNE="$(find_tool "${DUNE:-}" dune)"
OCAMLOPT="$(find_tool "${OCAMLOPT:-}" ocamlopt)"
OCAMLFIND="$(find_tool "${OCAMLFIND:-}" ocamlfind)"
MARCH="$(find_tool "${MARCH:-}" march)"
ELIXIR="$(find_tool "${ELIXIR:-}" elixir)"
RUSTC="$(find_tool "${RUSTC:-}" rustc)"
PYTHON3="$(find_tool "${PYTHON3:-}" python3)"
NUMPY_PY=""
[ -x "$BENCH_DIR/.venv/bin/python" ] && NUMPY_PY="$BENCH_DIR/.venv/bin/python"

# ── formatting helpers ────────────────────────────────────────────────────────
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }
dim()   { printf '\033[2m%s\033[0m\n' "$*"; }

# ── Provenance banner ────────────────────────────────────────────────────────
# Printed BEFORE any timing, so a reader of pasted output can tell what actually
# ran. A results table that silently omits a language is the failure mode this
# exists to prevent: versions come from the tools themselves rather than from a
# hand-maintained table that can drift from the run it claims to describe.
first_line() { "$@" 2>&1 | head -1 | tr -d '\r'; }

tool_version() {                   # tool_version LABEL PATH VERSION-ARGS…
  local label="$1" path="$2"; shift 2
  if [ -z "$path" ] || [ ! -x "$path" ]; then
    printf '  %-8s \033[2m— not found, this row will be MISSING from the tables\033[0m\n' "$label"
    MISSING="$MISSING $label"
  else
    printf '  %-8s %s\n' "$label" "$(first_line "$path" "$@")"
  fi
}

print_provenance() {
  MISSING=""
  # Start the machine file fresh and stamp the run's provenance as its first
  # record, so a committed .jsonl documents the machine it came from.
  if [ -n "$MACHINE_OUT" ]; then
    : > "$MACHINE_OUT"
    local cpu cores
    if [ -r /proc/cpuinfo ]; then
      cpu="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//')"
      cores="$(nproc 2>/dev/null || echo 0)"
    else
      cpu="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo unknown)"
      cores="$(sysctl -n hw.ncpu 2>/dev/null || echo 0)"
    fi
    printf '{"meta":true,"date":"%s","host":"%s","cpu":"%s","cores":%s,"runs":%s,"load":"%s"}\n' \
      "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$(json_escape "$(uname -srm)")" \
      "$(json_escape "$cpu")" "$cores" "$RUNS" \
      "$(json_escape "$(uptime | sed 's/.*load average[s]*: *//')")" >> "$MACHINE_OUT"
  fi
  bold "═══ Environment ═══"
  printf '  %-8s %s\n' "date" "$(date -u '+%Y-%m-%dT%H:%M:%SZ') (UTC)"
  printf '  %-8s %s\n' "host" "$(uname -srm)"
  # /proc first: Linux ships a `sysctl` too, so probing for the COMMAND rather
  # than for the data source sent Linux down the macOS branch and printed
  # "cpu unknown / cores unknown" on exactly the dedicated hosts worth
  # recording. Probe for the file, which only one of the two platforms has.
  if [ -r /proc/cpuinfo ]; then
    printf '  %-8s %s\n' "cpu" "$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ *//' || echo unknown)"
    printf '  %-8s %s\n' "cores" "$(nproc 2>/dev/null || echo unknown)"
  elif command -v sysctl >/dev/null 2>&1; then
    printf '  %-8s %s\n' "cpu" "$(sysctl -n machdep.cpu.brand_string 2>/dev/null || sysctl -n hw.model 2>/dev/null || echo unknown)"
    printf '  %-8s %s\n' "cores" "$(sysctl -n hw.ncpu 2>/dev/null || echo unknown)"
  fi
  # Load matters: these runs are short, and a busy machine inflates them. Print
  # it rather than trusting whoever pastes the output to mention it.
  printf '  %-8s %s\n' "load" "$(uptime | sed 's/.*load average[s]*: *//')"
  printf '  %-8s %s\n' "runs" "$RUNS per benchmark (median/min/max reported)"

  printf '\n'
  bold "═══ Toolchain ═══"
  # March is reported from the compiler that actually BUILDS the benchmarks —
  # `dune exec` against this working tree — not from whatever `march` happens to
  # be on PATH. Those differ routinely (an installed release vs. the tree you
  # are testing), and reporting the wrong one is the same class of error as
  # omitting a language silently.
  if [ -n "$DUNE" ]; then
    printf '  %-8s %s\n' "March" \
      "$( (cd "$REPO_ROOT" && "$DUNE" exec --root . march -- --version 2>/dev/null | head -1) || echo 'build failed' ) (dune exec, this working tree)"
  else
    printf '  %-8s \033[2m— dune not found; March rows will be MISSING\033[0m\n' "March"
    MISSING="$MISSING March"
  fi
  tool_version "OCaml"  "$OCAMLOPT"  -version
  tool_version "Rust"   "$RUSTC"     --version
  # `elixir --version` leads with the Erlang/OTP banner; the Elixir line is
  # further down. Report both, Elixir first.
  if [ -n "$ELIXIR" ] && [ -x "$ELIXIR" ]; then
    printf '  %-8s %s\n' "Elixir" \
      "$("$ELIXIR" --version 2>&1 | grep -m1 '^Elixir' || echo unknown)"
    printf '  %-8s %s\n' "" \
      "$("$ELIXIR" --version 2>&1 | grep -m1 '^Erlang' || true)"
  else
    printf '  %-8s \033[2m— not found, this row will be MISSING from the tables\033[0m\n' "Elixir"
    MISSING="$MISSING Elixir"
  fi
  tool_version "Python" "$PYTHON3"   --version
  if [ -n "$NUMPY_PY" ]; then
    printf '  %-8s %s\n' "NumPy" "$("$NUMPY_PY" -c 'import numpy; print("numpy " + numpy.__version__)' 2>/dev/null || echo 'venv present, numpy import failed')"
  else
    printf '  %-8s \033[2m— no bench/.venv, NumPy rows will be MISSING\033[0m\n' "NumPy"
    MISSING="$MISSING NumPy"
  fi

  if [ -n "$MISSING" ]; then
    printf '\n'
    printf '\033[1;33m  WARNING\033[0m these languages are absent:%s\n' "$MISSING"
    printf '          The tables below are NOT the full published comparison.\n'
    printf '          Install them, or state the omission when quoting these numbers.\n'
  fi
  printf '\n'
}
# ── Machine-readable output (JSONL) ──────────────────────────────────────────
# When MACHINE_OUT names a file, every row() also appends one JSON object there,
# tagged with the current benchmark (set by header()). This is the data a chart
# is generated FROM — a committed run under bench/results/*.jsonl plus
# bench/chart.py means a published chart is regenerable from data in the repo,
# never transcribed from a terminal (the failure that lost two languages once).
MACHINE_OUT="${MACHINE_OUT:-}"
CUR_BENCH=""
json_escape() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
emit_json() {  # emit_json language median min max
  [ -n "$MACHINE_OUT" ] || return 0
  printf '{"benchmark":"%s","language":"%s","median_ms":%s,"min_ms":%s,"max_ms":%s}\n' \
    "$(json_escape "$CUR_BENCH")" "$(json_escape "$1")" "$2" "$3" "$4" >> "$MACHINE_OUT"
}

header(){ CUR_BENCH="${1%% —*}"; printf '\n'; bold "═══ $* ═══"; printf '  %-12s %8s %8s %8s\n' "Language" "Median" "Min" "Max"; printf '  %-12s %8s %8s %8s\n' "--------" "------" "---" "---"; }
row()   { printf '  %-12s %7.1f ms %6.1f ms %6.1f ms\n' "$1" "$2" "$3" "$4"; emit_json "$1" "$2" "$3" "$4"; }
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

# ── provenance ────────────────────────────────────────────────────────────────
print_provenance

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
