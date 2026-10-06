#!/usr/bin/env bash
# Determinism oracle — proves the compiler's output depends only on the source
# and the compiler, not on the environment it ran in.
#
# For every program in ir-oracle's corpus it runs `--emit-llvm
# --dump-impl-hashes` under FOUR conditions and demands byte-identical `.ll`
# and `.hashes` output across all of them:
#
#   1  cold HOME A, cwd X    (no ~/.cache/march: stdlib is parsed+typechecked fresh)
#   2  warm HOME A, cwd X    (the stdlib_ast/stdlib_tcenv cache files 1 wrote)
#   3  cold HOME B, cwd Y
#   4  warm HOME B, cwd Y
#
# The pair (1,2) is the cache-warmth axis that produced different TIR for the
# same source until PR #805/#807 (specs/todos/2026-10-01-cold-stdlib-cache-
# changes-specializations.md, specs/todos/2026-10-05-post-tir-hash-depends-on-
# home-cache.md); the pair (1,3) is the cwd axis (the CAS store lives under
# <cwd>/.march/cas and ~/.cache/march blobs carry absolute paths).  Every
# condition sees the SAME compiler and the SAME source text; the only things
# that may differ are HOME and cwd.
#
# What is normalised: NOTHING.  The emitted IR embeds no path (verified
# 2026-10-06: `grep` for the cwd and the source path in a `.ll` written from
# both a relative and an absolute source path finds nothing), the .hashes file
# is symbol+hex only, and the CAS store location differs by cwd but is not an
# output.  Any difference, including one introduced by a future path-embedding
# change, is therefore a finding, not noise; if a legitimate difference ever
# appears, add the smallest sed here and list it in this header.
#
# Symbols still carry global fresh-name counters ($lam<n>, $apply$<n>, see
# specs/plans/incremental-codegen-cas-plan.md §14), so identity is only
# expected when the compiler's whole process state is identical — which is
# exactly the property this oracle tests.  That is also why --self-test can
# force a red: compiling conditions 3/4 against a stdlib copy with one extra
# lambda shifts every counter after it.
#
# The corpus is ir-oracle's (test/native, test/snapshots/src, bench) plus
# examples/topology_app compiled with its `--topology` digest.  topology_app is
# the program the known drift (#805) showed on: the ir-oracle corpus alone was
# GREEN on a pre-#805 compiler, topology_app was RED (cold kept an extra mono
# clone of `Topology.offer_actor_role` and every later `$apply$N` shifted).
# Its digest is written by `forge topology check` (MARCH_ORACLE_FORGE, default
# _build/default/forge/bin/main.exe); without a forge exe that leg is skipped
# LOUDLY, since a run without it cannot see that drift class.
#
#   scripts/determinism-oracle.sh                    # --corpus small (snapshots + topology_app, ~30 programs)
#   scripts/determinism-oracle.sh --corpus all       # + test/native + bench (~420 programs; CI)
#   scripts/determinism-oracle.sh --self-test        # must print RED: proves the oracle can fail
#   scripts/determinism-oracle.sh -j 8 -w /tmp/det   # parallelism / keep the work dir
#
# Exit 0: every program identical across all four conditions.  Exit 1: at
# least one difference (each is reported as program, condition pair, file and
# first differing line).  Exit 2: setup error or a vacuous run (too few
# programs emitted).
#
# Prove the oracle RED before trusting a GREEN (CLAUDE.md, "Refactor oracles"):
# `--self-test` does that in ~20 s and CI runs it before the real sweep.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Like ir-oracle: MARCH_ORACLE_EXE freezes the compiler so a rebuild mid-run
# cannot mix two compilers into one verdict.
EXE="${MARCH_ORACLE_EXE:-$ROOT/_build/default/bin/main.exe}"
FORGE="${MARCH_ORACLE_FORGE:-$ROOT/_build/default/forge/bin/main.exe}"

# The compiler resolves its stdlib exe-relatively, and from _build/default/bin
# that is _build/default/stdlib FIRST: a copy dune restages on every build.  A
# `dune build` or test run in the same worktree while the oracle runs rewrites
# it under the compiler, and one condition then parses different stdlib bytes
# than the others (seen 2026-10-06: condition 4 of bench/dataframe_bench got
# a second stdlib_ast_* cache key and +5 on every $apply$ counter while a
# concurrent `run-tests.sh -q compiler` restaged the tree).  Pin the source
# tree, which only a checkout can change; the worker also fails a program
# whose HOME ends up with more than one stdlib cache key, naming this cause.
export MARCH_STDLIB="${MARCH_STDLIB:-$ROOT/stdlib}"

# ── internal per-program worker (invoked via xargs; not for users) ───────────
# usage: determinism-oracle.sh --one <workdir> <argsfile>
# The args file has three lines: tag, source path, extra compiler flags
# (possibly empty).  One file per program keeps xargs' whitespace splitting
# away from paths and flags.
if [ "${1:-}" = "--one" ]; then
  WORK="$2"; args="$3"
  tag="$(sed -n 1p "$args")"; src="$(sed -n 2p "$args")"; flags="$(sed -n 3p "$args")"
  base="$(basename "$src" .march)"
  out="$WORK/out/$tag"
  rm -rf "$out"; mkdir -p "$out"
  # Two cwds and two HOMEs, all private to this program so workers never
  # share cache state (a shared HOME would make "cold" depend on scheduling).
  cwdX="$WORK/cwdX/$tag"; cwdY="$WORK/cwdY/$tag"
  homeA="$WORK/homeA/$tag"; homeB="$WORK/homeB/$tag"
  rm -rf "$cwdX" "$cwdY" "$homeA" "$homeB"
  mkdir -p "$cwdX" "$cwdY" "$homeA" "$homeB"
  cp "$src" "$cwdX/$base.march"; cp "$src" "$cwdY/$base.march"
  # The self-test (and anyone reproducing a red by hand) points conditions
  # 3/4 at a different stdlib tree; the real oracle leaves this unset.
  stdlib_b="${MARCH_DET_PERTURB_STDLIB:-}"
  run_cond() { # <n> <cwd> <home> <stdlib-override-or-empty>
    local n="$1" cwd="$2" home="$3" sl="$4" rc
    rm -f "$cwd/$base.ll" "$cwd/$base.hashes"
    # $flags is deliberately unquoted: it is a space-separated flag list
    # (e.g. `--topology /abs/path.json`), never a user path with spaces.
    if [ -n "$sl" ]; then
      # shellcheck disable=SC2086
      (cd "$cwd" && HOME="$home" MARCH_STDLIB="$sl" "$EXE" --emit-llvm --dump-impl-hashes $flags "$base.march") >"$out/$n.log" 2>&1
    else
      # shellcheck disable=SC2086
      (cd "$cwd" && HOME="$home" "$EXE" --emit-llvm --dump-impl-hashes $flags "$base.march") >"$out/$n.log" 2>&1
    fi
    rc=$?
    if [ "$rc" -eq 0 ] && [ -f "$cwd/$base.ll" ] && [ -f "$cwd/$base.hashes" ]; then
      mv "$cwd/$base.ll" "$out/$n.ll"; mv "$cwd/$base.hashes" "$out/$n.hashes"
      echo ok > "$out/$n.status"
    else
      echo "fail($rc)" > "$out/$n.status"
    fi
  }
  # "cold" = the HOME has no ~/.cache/march at all; it was just created.
  run_cond 1 "$cwdX" "$homeA" ""
  # A compile that succeeded must have populated the stdlib cache, or
  # condition 2 is not "warm" and the (1,2) comparison is vacuous.
  if [ "$(cat "$out/1.status")" = ok ] && [ ! -d "$homeA/.cache/march" ]; then
    echo "warn: $tag: condition 1 compiled but left no ~/.cache/march; (1,2) did not test cold vs warm" > "$out/warn"
  fi
  run_cond 2 "$cwdX" "$homeA" ""
  run_cond 3 "$cwdY" "$homeB" "$stdlib_b"
  run_cond 4 "$cwdY" "$homeB" "$stdlib_b"

  # Keys are stdlib_ast_<compiler>_<dir>_<source-hash>: with one compiler and
  # one directory, a second key in one HOME means the stdlib bytes changed
  # between its cold and warm compile.  That is the apparatus, not the
  # compiler, and any .ll difference it produces would be misread as drift.
  for hh in "$homeA" "$homeB"; do
    if [ "$(ls "$hh/.cache/march" 2>/dev/null | grep -c '^stdlib_ast_')" -gt 1 ]; then
      echo "FAIL  $tag  stdlib source changed under the oracle ($(ls "$hh/.cache/march" | grep -c '^stdlib_ast_') stdlib_ast keys in one HOME): a concurrent build or checkout rewrote $MARCH_STDLIB; rerun with nothing else touching the tree" > "$out/result"
      exit 0
    fi
  done
  s1="$(cat "$out/1.status")"; s2="$(cat "$out/2.status")"
  s3="$(cat "$out/3.status")"; s4="$(cat "$out/4.status")"
  if [ "$s1" != ok ] && [ "$s2" != ok ] && [ "$s3" != ok ] && [ "$s4" != ok ]; then
    # Ill-typed negative fixtures are expected in the corpus; record them so
    # a run that skips everything is visibly vacuous.
    echo "SKIP  $tag" > "$out/result"; exit 0
  fi
  if [ "$s1" != ok ] || [ "$s2" != ok ] || [ "$s3" != ok ] || [ "$s4" != ok ]; then
    echo "FAIL  $tag  exit status differs: 1=$s1 2=$s2 3=$s3 4=$s4" > "$out/result"; exit 0
  fi
  # Condition 1 is the reference; a program is OK only if 2, 3 and 4 all
  # match it in both files.  Report the first mismatch with its first line.
  for n in 2 3 4; do
    for ext in ll hashes; do
      if ! cmp -s "$out/1.$ext" "$out/$n.$ext"; then
        first="$(diff "$out/1.$ext" "$out/$n.$ext" | grep '^[<>]' | head -1)"
        echo "FAIL  $tag  conditions (1,$n) .$ext differ; first: $first" > "$out/result"
        exit 0
      fi
    done
  done
  echo "OK    $tag" > "$out/result"
  exit 0
fi

# ── driver ───────────────────────────────────────────────────────────────────
CORPUS=small; JOBS=""; WORK=""; SELF_TEST=0
while [ $# -gt 0 ]; do
  case "$1" in
    --corpus) CORPUS="${2:?--corpus needs small or all}"; shift 2 ;;
    -j) JOBS="${2:?-j needs a number}"; shift 2 ;;
    -w) WORK="${2:?-w needs a directory}"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    -h|--help) sed -n '2,45p' "$0"; exit 0 ;;
    *) echo "unknown argument: $1 (see --help)"; exit 2 ;;
  esac
done
case "$CORPUS" in small|all) ;; *) echo "FATAL: --corpus must be small or all, got: $CORPUS"; exit 2 ;; esac
[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }
"$EXE" --help 2>&1 | grep -q -- '--dump-impl-hashes' \
  || { echo "FATAL: $EXE has no --dump-impl-hashes (stale build?)"; exit 2; }

if [ -z "$JOBS" ]; then
  JOBS="$( (nproc 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4) )"
fi
if [ -z "$WORK" ]; then
  WORK="$(mktemp -d "${TMPDIR:-/tmp}/det-oracle.XXXXXX")"
  KEEP=0
else
  mkdir -p "$WORK"; KEEP=1
fi
WORK="$(cd "$WORK" && pwd)"
rm -rf "$WORK/out" "$WORK/cwdX" "$WORK/cwdY" "$WORK/homeA" "$WORK/homeB"
mkdir -p "$WORK/out"

# ── --self-test: the oracle must go RED on a deliberate perturbation ────────
# Conditions 3/4 compile against a copy of stdlib with one extra lambda in
# List; the fresh-name counters shift, so .ll and .hashes must differ from
# conditions 1/2.  A GREEN here means the oracle is broken (compare the two
# shipped-broken oracles in CLAUDE.md), and the script exits 1.
if [ "$SELF_TEST" -eq 1 ]; then
  rm -rf "$WORK/stdlib_perturbed"
  cp -R "$ROOT/stdlib" "$WORK/stdlib_perturbed"
  lst="$WORK/stdlib_perturbed/list.march"
  grep -q '^  fn map(' "$lst" || { echo "FATAL: stdlib/list.march has no 'fn map(' to perturb next to"; exit 2; }
  awk 'BEGIN{done=0} /^  fn map\(/ && !done {print "  pfn det_oracle_perturb(xs : List(Int)) : List(Int) do"; print "    List.map(xs, fn x -> x + 1)"; print "  end"; print ""; done=1} {print}' \
    "$lst" > "$lst.tmp" && mv "$lst.tmp" "$lst"
  grep -q det_oracle_perturb "$lst" || { echo "FATAL: perturbation did not land in $lst"; exit 2; }
  prog="$ROOT/test/snapshots/src/closure_hof.march"
  [ -f "$prog" ] || { echo "FATAL: self-test program $prog missing"; exit 2; }
  mkdir -p "$WORK/args"
  printf '%s\n%s\n%s\n' src_closure_hof "$prog" "" > "$WORK/args/src_closure_hof"
  MARCH_DET_PERTURB_STDLIB="$WORK/stdlib_perturbed" "$0" --one "$WORK" "$WORK/args/src_closure_hof"
  res="$(cat "$WORK/out/src_closure_hof/result")"
  echo "self-test: $res"
  case "$res" in
    FAIL*) echo "self-test RED as required: the oracle detects a perturbed stdlib."; rc=0 ;;
    *)     echo "self-test did NOT go red — the oracle is vacuous; refusing to trust it."; rc=1 ;;
  esac
  [ "$KEEP" -eq 1 ] || rm -rf "$WORK"
  exit "$rc"
fi

# ── corpus (shared with ir-oracle.sh; keep the globs in step) ───────────────
ARGS="$WORK/args"; rm -rf "$ARGS"; mkdir -p "$ARGS"
add_program() { # <tag> <src> <flags>
  printf '%s\n%s\n%s\n' "$1" "$2" "$3" > "$ARGS/$1"
}
if [ "$CORPUS" = all ]; then
  globs="$ROOT/test/native/*.march $ROOT/test/snapshots/src/*.march $ROOT/bench/*.march"
else
  globs="$ROOT/test/snapshots/src/*.march"
fi
for f in $globs; do
  [ -e "$f" ] || continue
  # Namespace by parent dir, as ir-oracle does: basenames collide across corpora.
  add_program "$(basename "$(dirname "$f")")_$(basename "$f" .march)" "$f" ""
done
# examples/topology_app: no `main`; forge generates it from topology.toml via
# the digest `forge topology check` writes (it holds no absolute paths), and
# the compiler takes it as --topology.  Stage the project once; the four
# conditions share the digest path exactly as they share the stdlib path.
if [ -x "$FORGE" ]; then
  d="$WORK/topology_app"; rm -rf "$d"; mkdir -p "$d"
  cp "$ROOT/examples/topology_app/topology.toml" "$ROOT/examples/topology_app/forge.toml" "$d/"
  cp -R "$ROOT/examples/topology_app/src" "$d/src"
  if (cd "$d" && "$FORGE" topology check) > "$d/topology.check.log" 2>&1 && [ -f "$d/.forge/topology.json" ]; then
    add_program examples_topology_app "$d/src/topology_app.march" "--topology $d/.forge/topology.json"
  else
    echo "FATAL: forge topology check failed; see $d/topology.check.log"; exit 2
  fi
else
  echo "WARNING: no forge exe at $FORGE; skipping examples/topology_app, the program"
  echo "         the known cold/warm drift (#805) showed on.  Build it: dune build --root . forge/bin/main.exe"
fi
total="$(ls "$ARGS" | wc -l | tr -d ' ')"
echo "determinism-oracle: corpus=$CORPUS programs=$total jobs=$JOBS work=$WORK"
start="$(date +%s)"
# xargs -P fans the per-program worker out; each worker writes only under
# its own $WORK/out/<tag>, so there is no shared state to race on.
ls "$ARGS" | sed "s|^|$ARGS/|" | xargs -n 1 -P "$JOBS" "$0" --one "$WORK"
cat "$WORK"/out/*/result | sort > "$WORK/results.txt"
cat "$WORK"/out/*/warn 2>/dev/null | sort -u | head -3
ok="$(grep -c '^OK' "$WORK/results.txt")"
skip="$(grep -c '^SKIP' "$WORK/results.txt")"
fail="$(grep -c '^FAIL' "$WORK/results.txt")"
echo "ok=$ok skipped=$skip failed=$fail elapsed=$(( $(date +%s) - start ))s"

min=10; [ "$CORPUS" = all ] && min=100
if [ $((ok + fail)) -lt "$min" ]; then
  echo "FATAL: only $((ok + fail)) programs emitted IR — the corpus is not being"
  echo "exercised (stale build? wrong exe?).  Refusing to report a vacuous verdict."
  [ "$KEEP" -eq 1 ] || rm -rf "$WORK"
  exit 2
fi
if [ "$fail" -gt 0 ]; then
  echo "NONDETERMINISTIC — $fail program(s) differ across HOME/cwd conditions:"
  grep '^FAIL' "$WORK/results.txt"
  echo "(work dir kept: $WORK; compare out/<tag>/{1,2,3,4}.{ll,hashes})"
  exit 1
fi
echo "DETERMINISTIC across $ok programs × 4 conditions (cold/warm HOME × cwd)"
[ "$KEEP" -eq 1 ] || rm -rf "$WORK"
exit 0
