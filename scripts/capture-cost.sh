#!/usr/bin/env bash
# capture-cost.sh — what would running capture inference (ocap phase 8a) on
# every build cost?
#
# The pass runs only on demand today (`march --dump-captures`, an editor
# hover, the soundness oracle).  This script forces it with MARCH_CAPTURES and
# compares `march --check` with and without it, per file:
#
#   off    plain `--check`
#   on     MARCH_CAPTURES=1: the pass over the file's own functions and what
#          they reach, which is what a build would run
#   all    MARCH_CAPTURES=all: the pass over every stdlib function as well,
#          reached or not (the upper bound; nothing would run this per build)
#
# Wall time is the median of N interleaved runs (default 11) under a private
# HOME with a warm stdlib cache, from a fresh working directory per run so no
# check artifact is reused.  The `pass` column is the pass's own time from
# `--timings` (the `captures` stamp minus the `typecheck` stamp), which is
# the number to trust: wall-time ratios this close to 1 are inside the noise.
#
# Usage: scripts/capture-cost.sh [-n RUNS] [FILE...]
# Defaults: a hello program (the stdlib's fixed cost), every bench/*.march,
# examples/http_requests.march and examples/lab_app's entry file.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MARCH="${MARCH_BIN:-$ROOT/_build/default/bin/main.exe}"
RUNS=11
if [[ "${1:-}" == "-n" ]]; then RUNS="$2"; shift 2; fi
[[ -x "$MARCH" ]] || { echo "capture-cost: no compiler at $MARCH (dune build --root . bin/main.exe)" >&2; exit 2; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export HOME="$WORK/home"
mkdir -p "$HOME"

if [[ $# -eq 0 ]]; then
  printf 'mod Hello do\n  needs IO.Console\n  fn main() do println("hello") end\nend\n' > "$WORK/hello.march"
  FILES=("$WORK/hello.march" "$ROOT"/bench/*.march "$ROOT/examples/http_requests.march")
  LAB="$(ls "$ROOT"/examples/lab_app/src/*.march 2>/dev/null | head -1 || true)"
  [[ -n "$LAB" ]] && FILES+=("$LAB")
else
  FILES=("$@")
fi

# One run: prints "<wall ms> <pass ms>".
one() {
  local mode="$1" file="$2" d out
  d="$(mktemp -d "$WORK/run.XXXXXX")"
  out="$d/out"
  local t0 t1
  t0=$(python3 -c 'import time; print(time.time())')
  ( cd "$d" && case "$mode" in
      off) "$MARCH" --check --timings "$file" ;;
      on)  MARCH_CAPTURES=1 "$MARCH" --check --timings "$file" ;;
      all) MARCH_CAPTURES=all "$MARCH" --check --timings "$file" ;;
    esac ) > "$out" 2>&1 || true
  t1=$(python3 -c 'import time; print(time.time())')
  python3 - "$t0" "$t1" "$out" <<'PY'
import re, sys
t0, t1, out = float(sys.argv[1]), float(sys.argv[2]), open(sys.argv[3]).read()
stamps = dict((m.group(2), float(m.group(1))) for m in re.finditer(r"\[timings\]\s+([0-9.]+)s\s+(\S+)", out))
p = (stamps["captures"] - stamps["typecheck"]) * 1000 if "captures" in stamps and "typecheck" in stamps else 0.0
print(f"{(t1 - t0) * 1000:.1f} {p:.2f}")
PY
  rm -rf "$d"
}

# Warm the stdlib cache once.
( cd "$WORK" && "$MARCH" --check "${FILES[0]}" >/dev/null 2>&1 || true )

printf '%-34s %9s %9s %9s %8s %9s %9s\n' file "off ms" "on ms" "on/off" "pass ms" "all ms" "all pass"
for f in "${FILES[@]}"; do
  : > "$WORK/off"; : > "$WORK/on"; : > "$WORK/all"
  for _ in $(seq "$RUNS"); do
    for mode in off on all; do one "$mode" "$f" >> "$WORK/$mode"; done
  done
  python3 - "$(basename "$f")" "$WORK/off" "$WORK/on" "$WORK/all" <<'PY'
import statistics, sys
def col(path, i):
    return [float(l.split()[i]) for l in open(path) if l.strip()]
name, off, on, al = sys.argv[1:5]
m = statistics.median
print(f"{name[:34]:<34} {m(col(off,0)):9.1f} {m(col(on,0)):9.1f} {m(col(on,0))/m(col(off,0)):9.3f} {m(col(on,1)):8.2f} {m(col(al,0)):9.1f} {m(col(al,1)):9.2f}")
PY
done
