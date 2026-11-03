#!/usr/bin/env bash
# z3-rlimit-measure.sh — how much of z3's resource limit refinement proofs use.
#
# Phase 1 runs, with the z3 on PATH (or MARCH_Z3), a private HOME, cold
# caches, MARCH_REFINE_RLIMIT_LOG and MARCH_REFINE_Z3_LOG, under --limit
# (default: the current default) on:
#   - the refinecheck suite (test/test_refinecheck.exe),
#   - `march --check` over every specs/lang/types/{accept,reject} fixture
#     (each run also checks the stdlib's own obligations).
# Phase 2 re-runs every query phase 1 left `unknown`, alone, under --probe
# (default 30M) with a wall-clock cap, to find proofs the current limit is
# too small for.  Re-running only those is what keeps this affordable: a
# query that never closes burns its whole limit, and the suite has many.
#
# Prints, per stage (main, stage2): query count, decided (sat/unsat) count,
# the max and p99/p99.9 rlimit of decided queries, and how many phase-1
# unknowns phase 2 decided, with their max cost.  A new default must cover
# every decided cost; see specs/progress/2026-11-02-z3-rlimit-measurement.md.
#
# Usage: scripts/z3-rlimit-measure.sh [--limit N] [--probe N] [--out DIR]
set -euo pipefail

limit=""
probe=30000000
out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --limit) limit="$2"; shift 2 ;;
    --probe) probe="$2"; shift 2 ;;
    --out) out="$2"; shift 2 ;;
    -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
    *) echo "z3-rlimit-measure: unknown argument $1" >&2; exit 2 ;;
  esac
done

repo=$(cd "$(dirname "$0")/.." && pwd)
cd "$repo"
[ -n "$out" ] || out=$(mktemp -d "${TMPDIR:-/tmp}/z3-rlimit.XXXXXX")
mkdir -p "$out"
z3=${MARCH_Z3:-$(command -v z3)}
[ -x "$z3" ] || { echo "z3-rlimit-measure: no z3 (set MARCH_Z3 or put z3 on PATH)" >&2; exit 1; }

dune build --root . bin/main.exe test/test_refinecheck.exe
main="$repo/_build/default/bin/main.exe"

rl="$out/rlimit.log"
ql="$out/queries.log"
: > "$rl"; : > "$ql"
mkdir -p "$out/home" "$out/work"
(
  export HOME="$out/home"
  unset XDG_CACHE_HOME
  [ -n "$limit" ] && export MARCH_REFINE_RLIMIT="$limit"
  export MARCH_REFINE_RLIMIT_LOG="$rl" MARCH_REFINE_Z3_LOG="$ql"
  echo "phase 1: refinecheck suite..." >&2
  "$repo/_build/default/test/test_refinecheck.exe" -e > "$out/refinecheck.out" 2>&1 || true
  echo "phase 1: conformance fixtures..." >&2
  for f in "$repo"/specs/lang/types/accept/*.march "$repo"/specs/lang/types/reject/*.march; do
    ( cd "$out/work" && "$main" --check "$f" > /dev/null 2>&1 ) || true
  done
)

echo "phase 2: re-running phase-1 unknowns at rlimit $probe..." >&2
mkdir -p "$out/unknown"
python3 - "$ql" "$out/unknown" "$probe" <<'PY'
import hashlib, re, sys
log, outdir, probe = sys.argv[1], sys.argv[2], sys.argv[3]
text = open(log).read()
seen = set()
for block in text.split(";; ==== sent\n")[1:]:
    q, _, rest = block.partition(";; ==== verdict: ")
    if not rest.startswith("unknown"):
        continue
    q = re.sub(r"\(set-option :rlimit \d+\)", f"(set-option :rlimit {probe})", q)
    h = hashlib.sha1(q.encode()).hexdigest()[:16]
    if h in seen:
        continue
    seen.add(h)
    stage = "stage2" if "check-sat-assuming" in q else "main"
    with open(f"{outdir}/{stage}-{h}.smt2", "w") as f:
        f.write(q + "(get-info :rlimit)\n")
PY
jobs=$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2) | tr -d '[:space:]')
export z3
find "$out/unknown" -name '*.smt2' -print0 | xargs -0 -P "$jobs" -n 1 sh -c '
  r=$(perl -e "alarm 180; exec @ARGV" "$z3" -smt2 "$1" 2>/dev/null | tr "\n" " ")
  echo "$(basename "$1" .smt2) $r" > "$1.out"' sh

python3 - "$rl" "$out/unknown" <<'PY'
import glob, os, re, sys
rl, udir = sys.argv[1], sys.argv[2]
rows = {}
for line in open(rl):
    p = line.rstrip("\n").split("\t")
    if len(p) == 3:
        rows.setdefault(p[1], []).append((int(p[0]), p[2]))
probe = {}
for f in glob.glob(os.path.join(udir, "*.out")):
    s = open(f).read().split()
    name = s[0]; stage = name.split("-")[0]
    verdict = s[1] if len(s) > 1 else "timeout"
    m = re.search(r":rlimit (\d+)", " ".join(s))
    probe.setdefault(stage, []).append((verdict, int(m.group(1)) if m else None))
def pct(xs, p):
    xs = sorted(xs)
    return xs[min(len(xs) - 1, int(p * len(xs)))] if xs else 0
for stage in sorted(set(rows) | set(probe)):
    r = rows.get(stage, [])
    dec = [n for n, v in r if v in ("sat", "unsat")]
    pr = probe.get(stage, [])
    newly = [n for v, n in pr if v in ("sat", "unsat") and n is not None]
    print(f"{stage}: queries={len(r)} decided={len(dec)} undecided={len(r) - len(dec)} "
          f"decided_max={max(dec) if dec else 0} decided_p99={pct(dec, .99)} decided_p999={pct(dec, .999)}")
    print(f"{stage}: distinct unknowns re-run={len(pr)} decided_at_probe={len(newly)} "
          f"probe_decided_max={max(newly) if newly else 0} "
          f"still_unknown={sum(1 for v, _ in pr if v == 'unknown')} timed_out={sum(1 for v, _ in pr if v not in ('sat','unsat','unknown'))}")
PY
