#!/usr/bin/env bash
# Refinement inference over the whole stdlib, one bounded run per module.
#
# `march --check --refine-infer --refine-infer-stdlib` on a trivial entry
# targets every stdlib function in ONE run with ONE global probe budget: it
# took 48 minutes and spent the budget before reaching most modules
# (specs/progress/2026-11-06-refine-infer-fixes.md).  This runs
# `--refine-infer-module M` once per stdlib module, in parallel, each with its
# own budget, under a private HOME, and writes one JSON report per module.
#
# usage: scripts/refine-infer-stdlib-sweep.sh [OUT_DIR] [MODULE ...]
#   OUT_DIR   where the reports go (default: a fresh temp dir, printed)
#   MODULE    sweep only these modules (default: every stdlib module)
# env:
#   MARCH_BIN          compiler (default: ./_build/default/bin/main.exe)
#   SWEEP_JOBS         parallel runs (default: CPU count / 2)
#   SWEEP_BUDGET       probe budget per module (default: 300)
#   SWEEP_TIMEOUT      seconds per module before it is cut off (default: 600)
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
march=${MARCH_BIN:-$root/_build/default/bin/main.exe}
[ -x "$march" ] || { echo "no compiler at $march (dune build --root . bin/main.exe)" >&2; exit 2; }
out=${1:-$(mktemp -d "${TMPDIR:-/tmp}/refine-infer-sweep.XXXXXX")}
shift || true
mkdir -p "$out"
cpus=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)
jobs=${SWEEP_JOBS:-$(( cpus > 1 ? cpus / 2 : 1 ))}
budget=${SWEEP_BUDGET:-300}
limit=${SWEEP_TIMEOUT:-600}

if [ "$#" -gt 0 ]; then
  mods=("$@")
else
  # The module each stdlib file declares: its first `mod Name do`.
  mods=()
  while IFS= read -r m; do mods+=("$m"); done < <(
    for f in "$root"/stdlib/*.march; do
      sed -n 's/^mod \([A-Z][A-Za-z0-9_]*\) do.*/\1/p' "$f" | head -n 1
    done | sort -u)
fi

# `timeout` is GNU coreutils; macOS has none by default.
if command -v timeout >/dev/null 2>&1; then tmo=timeout
elif command -v gtimeout >/dev/null 2>&1; then tmo=gtimeout
else tmo=perl_timeout; fi
perl_timeout() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV' "$s" "$@"; }
export -f perl_timeout

home=$(mktemp -d "${TMPDIR:-/tmp}/refine-infer-sweep-home.XXXXXX")
entry_dir=$(mktemp -d "${TMPDIR:-/tmp}/refine-infer-sweep-entry.XXXXXX")
trap 'rm -rf "$home" "$entry_dir"' EXIT
printf 'mod RefineInferSweep__ do\n  fn main() : Int do 0 end\nend\n' > "$entry_dir/sweep.march"

one() {
  local m=$1 start rc
  start=$(date +%s)
  rc=0
  ( cd "$entry_dir" && HOME="$home" $tmo "$limit" "$march" --check --refine-infer-json \
      --refine-infer-module "$m" --refine-infer-budget "$budget" sweep.march \
      > "$out/$m.json" 2> "$out/$m.err" ) || rc=$?
  printf '%-24s rc=%-3s %4ss\n' "$m" "$rc" "$(( $(date +%s) - start ))"
}
export -f one
export march out home entry_dir budget limit tmo

echo "sweeping ${#mods[@]} module(s), $jobs at a time, budget $budget, into $out" >&2
start=$(date +%s)
printf '%s\n' "${mods[@]}" | xargs -P "$jobs" -I{} bash -c 'one "$@"' _ {} | sort > "$out/summary.txt"
cat "$out/summary.txt"
proposed=$(cat "$out"/*.json 2>/dev/null | grep -o '"accepted": [0-9]*' | awk '{s+=$2} END {print s+0}')
failed=$(grep -vc 'rc=0 ' "$out/summary.txt" || true)
echo "done in $(( $(date +%s) - start ))s: ${#mods[@]} module(s), $proposed proposal(s), $failed run(s) not rc=0; reports in $out"
