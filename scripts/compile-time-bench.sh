#!/usr/bin/env bash
# compile-time-bench.sh — where does a `march --compile` spend its time, and
# what does an EDIT cost once the caches are warm?
#
# This is B0 of specs/plans/incremental-codegen-cas-plan.md: the measurement
# that decides whether the incremental-compilation half of that plan is worth
# building.  It records nothing the compiler does not already print — it drives
# `--timings` (the `[timings]` stamps in bin/main.ml and Contract_pipeline) over
# a small corpus under a set of cache states and edit kinds, and folds the
# stamps into three buckets:
#
#   front end           parse … typecheck            (t[typecheck])
#   whole-program TIR   lower … opt                  (t[opt]  - t[typecheck])
#   back end            llvm-emit + clang            (t[clang] - t[opt])
#
# The back-end bucket also holds everything between the `opt` stamp and the
# `llvm-emit` stamp that has no stamp of its own: the alloc-contract analyses
# and the CAS SCC build + hashing before the post-TIR cache lookup.  On
# topology_app (2026-10-05) that was ~5.7 s of an 18.8 s compile, nearly all
# of it in lib/cas/scc.ml.  A tir-hit row's wall minus its stamped buckets is
# that cost; subtract it before reading back% as "LLVM + clang".
#
# Scenarios, per corpus program:
#
#   cold      fresh $HOME (no stdlib AST/tcenv cache, no runtime .o cache) AND
#             a fresh project dir (no .march/cas): what a new clone pays
#   warm      same source again, caches warm: expected source-level CAS hit
#   comment   a comment appended: expected post-TIR hit (same TIR, new digest)
#   leaf      a body-only edit to one function
#   sig       a function renamed at its definition and all call sites
#   field     a record type gains a field (layout change)
#
# Every run of an edit scenario applies a DIFFERENT edit (x + 2, then x + 3;
# one extra field, then two), so each run is a fresh miss against the warm
# cache instead of a hit on the previous run's artifact.
#
# `sig` and `field` need the compiler to still accept the edited program, so
# they run only on bench/compile_time_probe.march, which carries `-- BENCH:*`
# marker lines for exactly this.  tree_transform and topology_app get `leaf`
# through a known literal (the plan's gate is stated on topology's leaf edit),
# and no `sig`/`field`.  The table prints `n/a`
# for the rest rather than pretend.
#
#   scripts/compile-time-bench.sh                       # all corpora, --opt 2, 3 runs
#   scripts/compile-time-bench.sh --opt 0 --corpus small
#   scripts/compile-time-bench.sh --runs 5 --out /tmp/ct.tsv
#
# cpu_ms is user+sys of the compiler and the clang it waits for (/usr/bin/time
# -p).  The pipeline is sequential, so on a quiet machine wall ~= cpu; on a
# loaded one wall (and every bucket, which comes from wall-clock stamps) is
# inflated and cpu_ms is the number to trust.
#
# Output: a TSV of every run (default bench/results/<date>-compile-time-<arch>.tsv)
# and a median table on stdout.  Commit a baseline once, as
# specs/plans/incremental-codegen-cas-baseline.md, not as a running count.
#
# Interpreting the table against the plan's gate (§3 criterion 1): if for the
# edit scenarios at --opt 2 the back-end bucket is under half of wall time,
# the unit-split/object-cache phases (B3–B5) are not where the time is.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${MARCH_BENCH_EXE:-$ROOT/_build/default/bin/main.exe}"
FORGE="${MARCH_BENCH_FORGE:-$ROOT/_build/default/forge/bin/main.exe}"
# Per-corpus extra compiler flags (topology_app needs its --topology digest).
EXTRA_FLAGS=()
OPT=2
CORPUS=all
RUNS=3
OUT=""
KEEP=0
while [ $# -gt 0 ]; do
  case "$1" in
    --opt)    OPT="$2"; shift 2 ;;
    --corpus) CORPUS="$2"; shift 2 ;;
    --runs)   RUNS="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --march)  EXE="$2"; shift 2 ;;
    --keep)   KEEP=1; shift ;;
    -h|--help) awk 'NR==1{next} /^#/{sub(/^# ?/,""); print; next} {exit}' "$0"; exit 0 ;;
    *) echo "unknown arg: $1 (try --help)" >&2; exit 2 ;;
  esac
done

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe" >&2; exit 2; }
command -v python3 >/dev/null || { echo "FATAL: python3 is required (timestamps, medians)" >&2; exit 2; }
case "$CORPUS" in small|bench|topology|all) ;; *) echo "FATAL: --corpus must be small|bench|topology|all" >&2; exit 2 ;; esac

ARCH="$(uname -m)"; DATE="$(date +%Y-%m-%d)"
if [ -z "$OUT" ]; then mkdir -p "$ROOT/bench/results"; OUT="$ROOT/bench/results/$DATE-compile-time-$ARCH.tsv"; fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/march-ctbench.XXXXXX")"
[ "$KEEP" = 1 ] || trap 'rm -rf "$TMP"' EXIT
echo "work dir: $TMP" >&2

ms_now() { python3 -c 'import time;print(int(time.time()*1000))'; }

printf 'corpus\tscenario\trun\topt\tstatus\ttotal_ms\tfront_ms\ttir_ms\tback_ms\tcpu_ms\n' > "$OUT"

# ── one compile ──────────────────────────────────────────────────────────────
# compile_once <home> <projdir> <src> <corpus> <scenario> <run>
# Runs from <projdir> (so the CAS lives in <projdir>/.march) with HOME=<home>
# (so the stdlib caches and runtime .o cache live there).  Parses the
# `[timings]` stamps into the three buckets.  Status is one of:
#   miss     full pipeline ran (clang stamp present)
#   tir-hit  stamps present up to opt, no llvm-emit/clang: post-TIR CAS hit
#   src-hit  no stamps at all: the source-level CAS exited before parsing
#   fail     non-zero exit (stderr kept in the work dir)
compile_once() {
  local home="$1" proj="$2" src="$3" corpus="$4" scen="$5" run="$6"
  local err="$TMP/$corpus.$scen.$run.err" out="$proj/out.bin"
  rm -f "$out"
  local t0 t1 rc
  t0=$(ms_now)
  ( cd "$proj" && HOME="$home" /usr/bin/time -p "$EXE" --compile --opt "$OPT" --timings ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} "$src" -o "$out" ) \
    >/dev/null 2>"$err"
  rc=$?
  t1=$(ms_now)
  local total=$((t1 - t0))
  local status front tir back
  if [ $rc -ne 0 ]; then
    status=fail; front=""; tir=""; back=""
    echo "  FAIL: $corpus/$scen run $run (rc=$rc), see $err" >&2
  else
    # Stamps are cumulative seconds since just before parsing.
    read -r status front tir back < <(python3 - "$err" <<'PY'
import re, sys
t = {}
for line in open(sys.argv[1], errors="replace"):
    m = re.match(r"\[timings\]\s+([0-9.]+)s\s+(\S+)", line)
    if m:
        t[m.group(2)] = float(m.group(1))
def ms(x): return str(int(round(x * 1000)))
if not t:
    print("src-hit", "-", "-", "-"); sys.exit()
fe = t.get("typecheck")
mid_end = t.get("opt", t.get("escape", t.get("perceus", t.get("lower"))))
if fe is None or mid_end is None:
    # Something unexpected; report what we have as a miss with blanks.
    print("miss", ms(fe) if fe else "-", "-", ms(t["clang"] - fe) if ("clang" in t and fe) else "-"); sys.exit()
if "clang" not in t:
    print("tir-hit", ms(fe), ms(mid_end - fe), "-"); sys.exit()
print("miss", ms(fe), ms(mid_end - fe), ms(t["clang"] - mid_end))
PY
)
    [ "$front" = - ] && front=""; [ "$tir" = - ] && tir=""; [ "$back" = - ] && back=""
  fi
  local cpu
  cpu=$(awk '$1=="user"||$1=="sys"{s+=$2} END{if (NR) printf "%d", s*1000}' "$err")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "$corpus" "$scen" "$run" "$OPT" "$status" "$total" "$front" "$tir" "$back" "$cpu" >> "$OUT"
  printf '  %-9s %-8s run %s  %-7s total %6s ms  fe %6s  tir %6s  be %6s  cpu %6s\n' \
    "$corpus" "$scen" "$run" "$status" "$total" "${front:--}" "${tir:--}" "${back:--}" "${cpu:--}" >&2
}

# ── edit recipes ─────────────────────────────────────────────────────────────
# Each takes <file> <k> and rewrites <file> in place so that run k differs from
# run k-1 (fresh miss).  They edit a COPY in the project dir, never the repo.
edit_comment() { printf '\n-- bench: comment edit %s\n' "$2" >> "$1"; }

# probe: `x + 1 -- BENCH:LEAF`  →  `x + (1+k) -- BENCH:LEAF`
edit_leaf_probe() {
  local n=$((1 + $2))
  sed -i.bak -E "s/x \+ [0-9]+ -- BENCH:LEAF/x + $n -- BENCH:LEAF/" "$1" && rm -f "$1.bak"
}
# tree_transform: `Leaf(n + 1)` in inc_leaves  →  `Leaf(n + (1+k))`
edit_leaf_tree() {
  local n=$((1 + $2))
  sed -i.bak -E "s/Leaf\(n \+ [0-9]+\)/Leaf(n + $n)/" "$1" && rm -f "$1.bak"
}
# topology_app: the `{ factor: 10 }` literal Back.start returns  →  `{ factor: 10+k }`
edit_leaf_topology() {
  local n=$((10 + $2))
  sed -i.bak -E "s/\{ factor: [0-9]+ \}/{ factor: $n }/" "$1" && rm -f "$1.bak"
}
# probe: rename sig_target (definition + every call site) to sig_target_vK
edit_sig_probe() {
  # No \b: BSD sed (macOS) lacks it.  Every occurrence is followed by `(` or
  # whitespace, and the optional group swallows a previous run's suffix.
  sed -i.bak -E "s/sig_target(_v[0-9]+)?/sig_target_v$2/g" "$1" && rm -f "$1.bak"
}
# probe: Box gains k extra Int fields, and its one construction site fills them.
edit_field_probe() {
  local k="$2" tyfields="" initfields="" i
  for i in $(seq 1 "$k"); do tyfields="$tyfields, p$i : Int"; initfields="$initfields, p$i: 0"; done
  sed -i.bak -E "s/type Box = \{ v : Int, w : Int[^}]*\} -- BENCH:FIELD_TYPE/type Box = { v : Int, w : Int$tyfields } -- BENCH:FIELD_TYPE/" "$1" \
    && sed -i.bak -E "s/let b = \{ v: use_a\(xs\), w: 7[^}]*\} -- BENCH:FIELD_INIT/let b = { v: use_a(xs), w: 7$initfields } -- BENCH:FIELD_INIT/" "$1" \
    && rm -f "$1.bak"
}

# ── one corpus program ───────────────────────────────────────────────────────
# run_corpus <name> <srcdir> <entry, relative to srcdir> <leaf-recipe|-> <sig-recipe|-> <field-recipe|->
run_corpus() {
  local name="$1" srcdir="$2" entry="$3" leaf="$4" sig="$5" field="$6"
  echo "== $name  (--opt $OPT, $RUNS runs)" >&2
  local base="$TMP/$name"; mkdir -p "$base"

  # cold: fresh HOME + fresh project dir per run (stdlib caches, runtime .o
  # cache and the CAS all empty).
  local r
  for r in $(seq 1 "$RUNS"); do
    local h="$base/cold-home-$r" p="$base/cold-proj-$r"
    mkdir -p "$h" "$p"; cp -R "$srcdir"/. "$p"/
    compile_once "$h" "$p" "$p/$entry" "$name" cold "$r"
    [ "$KEEP" = 1 ] || rm -rf "$h" "$p"
  done

  # warm state: two untimed compiles.  The first, in a throwaway project dir,
  # only populates $HOME's stdlib caches; the second primes the real project's
  # CAS.  Priming straight into a fresh $HOME is not enough: the first compile
  # in a fresh $HOME produces a different post-TIR key than every later one
  # (seen on topology_app, 2026-10-04), so a comment edit would miss against
  # an artifact no steady-state compile can ever hit.
  local h="$base/home" p="$base/proj" wp="$base/home-warmup-proj"
  mkdir -p "$h" "$p" "$wp"; cp -R "$srcdir"/. "$p"/; cp -R "$srcdir"/. "$wp"/
  ( cd "$wp" && HOME="$h" "$EXE" --compile --opt "$OPT" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} "$wp/$entry" -o "$wp/out.bin" ) \
    >/dev/null 2>"$TMP/$name.warmup.err" || { echo "  FAIL: HOME warm-up compile for $name, see $TMP/$name.warmup.err" >&2; return; }
  [ "$KEEP" = 1 ] || rm -rf "$wp"
  ( cd "$p" && HOME="$h" "$EXE" --compile --opt "$OPT" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} "$p/$entry" -o "$p/out.bin" ) \
    >/dev/null 2>"$TMP/$name.prime.err" || { echo "  FAIL: priming compile for $name, see $TMP/$name.prime.err" >&2; return; }
  cp "$p/$entry" "$base/pristine.march"

  for r in $(seq 1 "$RUNS"); do compile_once "$h" "$p" "$p/$entry" "$name" warm "$r"; done

  local scen recipe
  for scen in comment leaf sig field; do
    case "$scen" in
      comment) recipe=edit_comment ;;
      leaf)    recipe="$leaf" ;;
      sig)     recipe="$sig" ;;
      field)   recipe="$field" ;;
    esac
    if [ "$recipe" = "-" ]; then
      for r in $(seq 1 "$RUNS"); do
        printf '%s\t%s\t%s\t%s\t%s\t\t\t\t\t\n' "$name" "$scen" "$r" "$OPT" "n/a" >> "$OUT"
      done
      echo "  $name $scen: n/a (no safe edit recipe for this program)" >&2
      continue
    fi
    for r in $(seq 1 "$RUNS"); do
      cp "$base/pristine.march" "$p/$entry"
      "$recipe" "$p/$entry" "$r"
      compile_once "$h" "$p" "$p/$entry" "$name" "$scen" "$r"
    done
    cp "$base/pristine.march" "$p/$entry"
  done
}

want() { [ "$CORPUS" = all ] || [ "$CORPUS" = "$1" ]; }

if want small; then
  d="$TMP/src-small"; mkdir -p "$d"; cp "$ROOT/bench/compile_time_probe.march" "$d/"
  run_corpus small "$d" compile_time_probe.march edit_leaf_probe edit_sig_probe edit_field_probe
fi
if want bench; then
  d="$TMP/src-bench"; mkdir -p "$d"; cp "$ROOT/bench/tree_transform.march" "$d/"
  run_corpus bench "$d" tree_transform.march edit_leaf_tree - -
fi
if want topology; then
  # topology_app has no `main`: `forge run` generates it from topology.toml,
  # via the digest `forge topology check` writes to .forge/topology.json, and
  # compiles with `--topology .forge/topology.json`.  Do the same: stage the
  # whole project (the entry's sibling .march files are part of the
  # source-level key), write the digest once (it holds no absolute paths), and
  # pass the flag.  Compiling the bare entry without it is not what any user
  # runs (and on 2026-10-04 it emitted invalid LLVM IR).
  [ -x "$FORGE" ] || { echo "FATAL: $FORGE not built. Run: dune build --root . forge/bin/main.exe" >&2; exit 2; }
  d="$TMP/src-topology"; mkdir -p "$d"
  cp "$ROOT/examples/topology_app/topology.toml" "$ROOT/examples/topology_app/forge.toml" "$d/"
  cp -R "$ROOT/examples/topology_app/src" "$d/src"
  ( cd "$d" && "$FORGE" topology check ) >"$TMP/topology.check.log" 2>&1 \
    || { echo "FATAL: forge topology check failed, see $TMP/topology.check.log" >&2; exit 1; }
  EXTRA_FLAGS=(--topology .forge/topology.json)
  run_corpus topology "$d" src/topology_app.march edit_leaf_topology - -
  EXTRA_FLAGS=()
fi

# ── summary ─────────────────────────────────────────────────────────────────
echo >&2
python3 - "$OUT" <<'PY'
import csv, sys, statistics
rows = list(csv.DictReader(open(sys.argv[1]), delimiter="\t"))
order = ["cold", "warm", "comment", "leaf", "sig", "field"]
corpora = []
for r in rows:
    if r["corpus"] not in corpora: corpora.append(r["corpus"])
def med(vals):
    vals = [float(v) for v in vals if v not in ("", None)]
    return statistics.median(vals) if vals else None
def fmt(v): return f"{'-':>6}" if v is None else f"{int(round(v)):>6}"
# back% is the back end's share of the three stamped buckets, not of wall time:
# wall also holds process start-up and the CAS copy, which no phase can remove.
print(f"{'corpus':<9} {'scenario':<8} {'status':<8} {'n':>2} {'total':>6} {'front':>6} {'tir':>6} {'back':>6}  back%  {'cpu':>6}   (medians over runs, ms)")
for c in corpora:
    for s in order:
        rs_all = [r for r in rows if r["corpus"] == c and r["scenario"] == s]
        if not rs_all: continue
        if all(r["status"] == "n/a" for r in rs_all):
            print(f"{c:<9} {s:<8} {'n/a':<8}"); continue
        # One row per status: a scenario that hit the cache on some runs and
        # missed on others is two populations, not one median.
        for st in sorted(set(r["status"] for r in rs_all)):
            rs = [r for r in rs_all if r["status"] == st]
            tot, fe, tir, be, cpu = (med([r.get(k) for r in rs]) for k in ("total_ms", "front_ms", "tir_ms", "back_ms", "cpu_ms"))
            parts = [x for x in (fe, tir, be) if x is not None]
            share = f"{100*be/sum(parts):5.0f}%" if (be is not None and sum(parts)) else "      "
            print(f"{c:<9} {s:<8} {st:<8} {len(rs):>2} {fmt(tot)} {fmt(fe)} {fmt(tir)} {fmt(be)}  {share}  {fmt(cpu)}")
print()
print("gate (plan §3, criterion 1): for leaf/sig/field misses at --opt 2, is back% over ~60 and")
print("the topology total over ~10 s?  Below that, B3-B5 are not where the time goes.")
print(f"rows: {sys.argv[1]}")
PY
