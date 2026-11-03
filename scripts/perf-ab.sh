#!/usr/bin/env bash
# perf-ab.sh — same-box A/B performance comparison of two March compilers.
#
# Builds the compiler at two git refs, each in its own detached worktree,
# compiles one fixed benchmark set with each (`--compile --opt 2`), then runs
# the two sets of binaries interleaved on this machine and prints, per
# benchmark, the median wall time of each arm, the ratio, a bootstrap 95% CI
# and whether it is outside noise, plus the runtime's exact allocation
# counters. The measurement itself is scripts/perf-ab-measure.py.
#
# Design and rationale: specs/2026-10-30-perf-ab-runner-design.md. In short:
# absolute-ms baselines do not detect regressions on this project's machines
# (specs/benchmarks.md, "Compute-benchmark sweep"); only two compilers raced
# on the same box in the same minute do.
#
# Usage:
#   scripts/perf-ab.sh [options] [BASE [CAND]]
#     BASE   default: the newest release tag (v*) reachable from HEAD
#     CAND   default: HEAD
#   Options:
#     --runs N            timed rounds per arm (default 15)
#     --threshold PCT     smallest ratio change reported as slower/faster (default 3)
#     --metric cpu|wall   the time the verdict is on (default cpu: user+sys of the
#                         benchmark process; both are always reported)
#     --benches "a b"     benchmark names under bench/ (default: the fixed set below)
#     --base-dir DIR      use an existing checkout as BASE as-is (uncommitted edits included)
#     --cand-dir DIR      same for CAND; e.g. --cand-dir . for this worktree's edits
#     --work DIR          where worktrees and builds live (default $TMPDIR/march-perf-ab);
#                         a ref's built worktree is reused across runs, keyed by commit
#     --out DIR           write table.md and results.json here
#     --no-counter-gate   report allocation-counter increases without failing on them
#     --self-test aa      HEAD against itself; passes iff every row is within noise
#                         and every counter is identical
#     --self-test red     HEAD against HEAD with a spin loop injected into the
#                         runtime's march_alloc; passes iff the allocation-heavy
#                         benchmarks are reported slower and the counters are not
#
# Exit status: 0 no regression, 1 a regression (timing or counter), 2 the
# comparison is invalid (a build failed, a run failed, the arms' outputs
# differ). In --self-test mode: 0 the self-test passed, 1 it did not.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MEASURE="$REPO_ROOT/scripts/perf-ab-measure.py"

# The fixed set. Chosen to cover what the 1.0 performance work will tune:
# the call/arith core (fib), Perceus/FBIP (tree_transform), allocation
# (binary_trees), closures/HOFs (list_ops), the string ABI the inline
# small-string capacity will be chosen on (string_*, iolist_template), and
# JSON as the parse-heavy application workload. Each runs 20 ms - 1 s warm.
# Deliberately excluded: anything multi-threaded (string_parallel_scan,
# par_*: core contention makes the timing and the counters nondeterministic)
# and anything needing a network peer (http_*). See the design spec.
DEFAULT_BENCHES="fib tree_transform binary_trees list_ops
  string_build string_pipeline string_scan string_case string_split_large
  string_slice_walk string_small_churn iolist_template
  json_stream json_stream_strings"

RUNS=15
THRESHOLD=3
METRIC=cpu
BENCHES="$DEFAULT_BENCHES"
BASE_DIR=""
CAND_DIR=""
WORK="${TMPDIR:-/tmp}"
WORK="${WORK%/}/march-perf-ab"
OUT=""
COUNTER_GATE=""
SELF_TEST=""
POS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --runs) RUNS="$2"; shift 2 ;;
    --threshold) THRESHOLD="$2"; shift 2 ;;
    --metric) METRIC="$2"; shift 2 ;;
    --benches) BENCHES="$2"; shift 2 ;;
    --base-dir) BASE_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --cand-dir) CAND_DIR="$(cd "$2" && pwd)"; shift 2 ;;
    --work) WORK="$2"; shift 2 ;;
    --out) OUT="$2"; shift 2 ;;
    --no-counter-gate) COUNTER_GATE="--no-counter-gate"; shift ;;
    --self-test) SELF_TEST="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    -*) echo "perf-ab: unknown option $1" >&2; exit 2 ;;
    *) POS+=("$1"); shift ;;
  esac
done

mkdir -p "$WORK"
WORK="$(cd "$WORK" && pwd)"
RUN="$WORK/run-$$"
rm -rf "$RUN"; mkdir -p "$RUN"
[ -n "$OUT" ] || OUT="$RUN"
mkdir -p "$OUT"

log() { echo "perf-ab: $*" >&2; }

# build_tree DIR: build the compiler in checkout DIR. `--root .` because a
# checkout nested under another dune project otherwise builds the OUTER one
# (CLAUDE.md, "Worktree note").
build_tree() {
  local dir="$1"
  log "building compiler in $dir"
  if ! (cd "$dir" && dune build --root . bin/main.exe) > "$RUN/build-$(basename "$dir").log" 2>&1; then
    log "compiler build FAILED in $dir:"; tail -30 "$RUN/build-$(basename "$dir").log" >&2
    exit 2
  fi
}

# tree_for REF: a built, detached worktree at REF's commit, reused if present.
# A detached worktree, never a checkout of this tree: the two compilers must
# not share a _build, a runtime copy or a stdlib.
tree_for() {
  local sha dir
  sha="$(git -C "$REPO_ROOT" rev-parse --verify "$1^{commit}")"
  dir="$WORK/tree-$sha"
  if [ ! -d "$dir" ]; then
    git -C "$REPO_ROOT" worktree add --detach "$dir" "$sha" > /dev/null 2>&1 \
      || { log "git worktree add failed for $1 ($sha)"; exit 2; }
  fi
  [ -x "$dir/_build/default/bin/main.exe" ] || build_tree "$dir" >&2
  echo "$dir"
}

# make_slow_tree SRC: a copy of checkout SRC whose runtime spins in every
# march_alloc. The red self-test's candidate: it does the same work and
# allocates exactly as much, only slower, so it must turn the timing red
# and leave the counters green.
make_slow_tree() {
  local src="$1" dir
  dir="$WORK/slow-$(git -C "$src" rev-parse HEAD)"
  if [ ! -d "$dir" ]; then
    git -C "$REPO_ROOT" worktree add --detach "$dir" "$(git -C "$src" rev-parse HEAD)" > /dev/null 2>&1 \
      || { log "git worktree add failed for the slow tree"; exit 2; }
    python3 - "$dir/runtime/march_runtime.c" <<'PYEOF'
import sys
p = sys.argv[1]
s = open(p).read()
anchor = "void *march_alloc(int64_t sz) {\n"
assert s.count(anchor) == 1, "march_alloc definition not found exactly once"
s = s.replace(anchor, anchor + "    for (volatile int perf_ab_spin = 0; perf_ab_spin < 200; perf_ab_spin++) { }\n")
open(p, "w").write(s)
PYEOF
  fi
  [ -x "$dir/_build/default/bin/main.exe" ] || build_tree "$dir" >&2
  echo "$dir"
}

case "$SELF_TEST" in
  "") ;;
  aa|red) POS=(HEAD HEAD) ;;
  *) echo "perf-ab: --self-test takes aa or red" >&2; exit 2 ;;
esac

BASE_REF="${POS[0]:-}"
CAND_REF="${POS[1]:-HEAD}"
if [ -z "$BASE_REF" ] && [ -z "$BASE_DIR" ]; then
  BASE_REF="$(git -C "$REPO_ROOT" describe --tags --abbrev=0 --match 'v*' HEAD)"
fi

if [ -n "$BASE_DIR" ]; then build_tree "$BASE_DIR"; A_TREE="$BASE_DIR"; A_LABEL="$BASE_DIR"
else A_TREE="$(tree_for "$BASE_REF")"; A_LABEL="$BASE_REF ($(git -C "$A_TREE" rev-parse --short HEAD))"; fi
if [ -n "$CAND_DIR" ]; then build_tree "$CAND_DIR"; B_TREE="$CAND_DIR"; B_LABEL="$CAND_DIR"
else B_TREE="$(tree_for "$CAND_REF")"; B_LABEL="$CAND_REF ($(git -C "$B_TREE" rev-parse --short HEAD))"; fi
if [ "$SELF_TEST" = red ]; then
  B_TREE="$(make_slow_tree "$B_TREE")"; B_LABEL="$B_LABEL + march_alloc spin"
fi
log "A = $A_LABEL"
log "B = $B_LABEL"

# compile_arm ARM TREE NAME: compile the CANDIDATE's copy of bench/NAME.march
# with TREE's compiler, stdlib and runtime. Both arms compile the same source
# text: the comparison is of compilers, so the program must not vary. Each arm
# gets a private HOME and its own cwd, so neither the global CAS
# (~/.march/cas), the stdlib cache (~/.cache/march) nor the project CAS
# (<cwd>/.march/cas) can serve one arm's artifact to the other.
compile_arm() {
  local tree="$2" name="$3" dir="$RUN/$1"
  mkdir -p "$dir/home" "$dir/src" "$dir/bin"
  cp "$B_SRC_TREE/bench/$name.march" "$dir/src/$name.march"
  (cd "$dir/src" && HOME="$dir/home" MARCH_STDLIB="$tree/stdlib" MARCH_RUNTIME_DIR="$tree/runtime" \
     "$tree/_build/default/bin/main.exe" --compile --opt 2 "$name.march" -o "$dir/bin/$name") \
     > "$dir/$name.compile.log" 2>&1
}

B_SRC_TREE="$B_TREE"
PAIRS=()
SKIPPED=()
for name in $BENCHES; do
  if [ ! -f "$B_SRC_TREE/bench/$name.march" ]; then
    log "no bench/$name.march in the candidate tree"; exit 2
  fi
  if [ -f "$A_TREE/bench/$name.march" ] && ! cmp -s "$A_TREE/bench/$name.march" "$B_SRC_TREE/bench/$name.march"; then
    log "note: bench/$name.march differs between the refs; both arms compile the candidate's copy"
  fi
  if ! compile_arm A "$A_TREE" "$name"; then
    SKIPPED+=("$name (A's compiler rejects it: $RUN/A/$name.compile.log)"); continue
  fi
  if ! compile_arm B "$B_TREE" "$name"; then
    log "candidate failed to compile bench/$name.march:"; tail -20 "$RUN/B/$name.compile.log" >&2; exit 2
  fi
  PAIRS+=("$name:$RUN/A/bin/$name:$RUN/B/bin/$name")
done
[ ${#PAIRS[@]} -gt 0 ] || { log "no benchmark compiled with both compilers"; exit 2; }

set +e
python3 "$MEASURE" --runs "$RUNS" --threshold "$THRESHOLD" --metric "$METRIC" $COUNTER_GATE \
  --label-a "$A_LABEL" --label-b "$B_LABEL" \
  --out-md "$OUT/table.md" --out-json "$OUT/results.json" "${PAIRS[@]}"
rc=$?
set -e
if [ ${#SKIPPED[@]} -gt 0 ]; then
  { echo; echo "Not compared:"; printf -- '- %s\n' "${SKIPPED[@]}"; } | tee -a "$OUT/table.md"
fi
log "table: $OUT/table.md"

[ -n "$SELF_TEST" ] || exit "$rc"

# Self-test verdicts, read from results.json rather than the exit code so a
# red test cannot pass by failing for the wrong reason (e.g. invalid output).
python3 - "$OUT/results.json" "$SELF_TEST" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1])); mode = sys.argv[2]
bs = {b["name"]: b for b in r["benchmarks"]}
bad = list(r["invalid"])
if mode == "aa":
    for n, b in bs.items():
        if b["verdict"] != "~":
            bad.append(f"{n}: A/A verdict {b['verdict']} (ratio {b['ratio']:.3f})")
        if b["counter_changes"]:
            bad.append(f"{n}: A/A counters differ {b['counter_changes']}")
else:
    # The spin is per allocation, so these must go red; fib allocates nothing
    # and is not asserted either way.
    for n in ("binary_trees", "tree_transform", "list_ops"):
        if n in bs and bs[n]["verdict"] != "slower":
            bad.append(f"{n}: injected slowdown not detected (verdict {bs[n]['verdict']}, ratio {bs[n]['ratio']:.3f})")
    for n, b in bs.items():
        if b["counter_regressed"]:
            bad.append(f"{n}: counters changed under a pure slowdown {b['counter_changes']}")
if bad:
    print(f"SELF-TEST {mode}: FAIL"); [print("  " + m) for m in bad]; sys.exit(1)
print(f"SELF-TEST {mode}: PASS")
PYEOF
