#!/usr/bin/env bash
# Lazy-lowering identity gate: lowering stdlib bodies on demand must not change
# one byte of the emitted program.
#
# `Lower.lower_module ~lazy_bodies` (bin/main.ml's native compile) lowers only
# the stdlib function bodies the pre-mono prune can reach and leaves the rest
# as stubs (specs/progress/2026-11-26-lazy-stdlib-lowering.md).  Its whole
# claim is that the emitted program is the one eager lowering emits.  This
# script checks that claim on every program of the IR-oracle corpus
# (test/native, test/snapshots/src, bench) and the capability conformance
# programs (test/cap_conformance: the frames, restricts and grants whose
# passes mint calls after lowering), plus the multi-file fixtures
# test/native/<name>/entry.march with their lib/ on MARCH_LIB_PATH: each is
# compiled with
# `--emit-llvm` twice by the SAME compiler, once as is and once with
# `--disable-pass lazy-lower`, and the two `.ll` files must be byte-identical.
# Both runs must also agree on whether the program compiles at all (a stub
# the prune reaches is a compile error under lazy lowering only).
#
# Nothing is normalised.  The two compiles differ only in the switch: same
# file name (in two sibling directories), same private HOME (warmed by one
# serial compile first), same MARCH_STDLIB.
#
# Not vacuous: each run also passes `--timings`, whose `lower` line counts
# the TIR functions; lazy lowering leaves stubs with no nested functions, so
# the count differs when it engaged.  The gate demands it engaged on at least
# 100 programs (a build where it silently never ran would otherwise be
# green), and `--self-test` demands that a real difference turns it red: it
# compiles one program with the eager side also under `--disable-pass opt`.
#
#   scripts/lazy-lower-gate.sh                 # whole corpus (~560 programs)
#   scripts/lazy-lower-gate.sh FILE...         # just these programs
#   scripts/lazy-lower-gate.sh --self-test     # must report RED and exit 0
#   scripts/lazy-lower-gate.sh -j 8 -w DIR     # parallelism / keep the work dir
#   scripts/lazy-lower-gate.sh --shard 1/2     # shard K of N (1-based)
#
# Exit 0: every program identical.  Exit 1: a difference (program and first
# differing line printed; files kept under the work dir).  Exit 2: harness
# failure (no compiler, too few programs emitted or engaged).
#
# MARCH_ORACLE_EXE points at another compiler (pair it with MARCH_STDLIB).
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="${MARCH_ORACLE_EXE:-$ROOT/_build/default/bin/main.exe}"
JOBS="${MARCH_ORACLE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
WORK=""
SELF_TEST=0
SHARD=""
FILES=()
while [ $# -gt 0 ]; do
  case "$1" in
    -j) JOBS="$2"; shift 2 ;;
    -w) WORK="$2"; shift 2 ;;
    --self-test) SELF_TEST=1; shift ;;
    --shard) SHARD="$2"; shift 2 ;;
    -h|--help) sed -n '2,38p' "$0"; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) FILES+=("$1"); shift ;;
  esac
done

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }
KEEP=1
if [ -z "$WORK" ]; then WORK="$(mktemp -d "${TMPDIR:-/tmp}/lazy-lower-gate.XXXXXX")"; KEEP=0; fi
mkdir -p "$WORK"
rm -rf "$WORK/lazy" "$WORK/eager" "$WORK/parts"
mkdir -p "$WORK/lazy" "$WORK/eager" "$WORK/parts" "$WORK/home/.cache"
export HOME="$WORK/home"
export MARCH_STDLIB="${MARCH_STDLIB:-$ROOT/stdlib}"
# The switch must come from this script alone.
unset MARCH_DISABLE_PASS
EAGER_EXTRA="${LAZY_GATE_EAGER_EXTRA:-}"
export EXE WORK EAGER_EXTRA

# One program: compile both ways, compare.  Writes parts/<tag> as
#   SAME <tag> <engaged 0|1> | DIFF <tag> <why> | SKIP <tag>
gate_one() {
  f="$1"
  base="$(basename "$f" .march)"
  tag="$(basename "$(dirname "$f")")_$base"
  # A multi-file fixture (test/native/<name>/entry.march) finds its modules
  # in the sibling lib/ through MARCH_LIB_PATH, as its dune rule does.
  libdir="$(cd "$(dirname "$f")" && pwd)/lib"
  if [ "$base" = entry ] && [ -d "$libdir" ]; then export MARCH_LIB_PATH="$libdir"; else unset MARCH_LIB_PATH; fi
  for side in lazy eager; do
    mkdir -p "$WORK/$side/$tag"
    cp "$f" "$WORK/$side/$tag/$base.march"
    rm -f "$WORK/$side/$tag/$base.ll"
  done
  # Relative path from inside the directory, as ir-oracle does: the .ll
  # embeds the source path as given.
  (cd "$WORK/lazy/$tag" && "$EXE" --emit-llvm --timings "$base.march") \
    >"$WORK/lazy/$tag/log" 2>&1
  lz=$?
  # shellcheck disable=SC2086
  (cd "$WORK/eager/$tag" && "$EXE" --emit-llvm --timings --disable-pass "lazy-lower$EAGER_EXTRA" "$base.march") \
    >"$WORK/eager/$tag/log" 2>&1
  ez=$?
  lll="$WORK/lazy/$tag/$base.ll"; ell="$WORK/eager/$tag/$base.ll"
  if [ $lz -ne 0 ] || [ $ez -ne 0 ] || [ ! -f "$lll" ] || [ ! -f "$ell" ]; then
    if [ $lz -eq $ez ] && [ ! -f "$lll" ] && [ ! -f "$ell" ]; then
      printf 'SKIP %s\n' "$tag" > "$WORK/parts/$tag"
      rm -rf "$WORK/lazy/$tag" "$WORK/eager/$tag"
    else
      printf 'DIFF %s compiles differently (exit lazy=%s eager=%s); see %s\n' \
        "$tag" "$lz" "$ez" "$WORK/lazy/$tag/log" > "$WORK/parts/$tag"
    fi
    return
  fi
  if cmp -s "$lll" "$ell"; then
    lfns=$(grep -o '\] *[0-9.]*s  lower  fns=[0-9]*' "$WORK/lazy/$tag/log" | head -1 | sed 's/.*fns=//')
    efns=$(grep -o '\] *[0-9.]*s  lower  fns=[0-9]*' "$WORK/eager/$tag/log" | head -1 | sed 's/.*fns=//')
    engaged=0; [ -n "$lfns" ] && [ "$lfns" != "$efns" ] && engaged=1
    printf 'SAME %s %s\n' "$tag" "$engaged" > "$WORK/parts/$tag"
    # Only a difference is kept: the corpus's IR runs to gigabytes.
    rm -rf "$WORK/lazy/$tag" "$WORK/eager/$tag"
  else
    line=$(cmp "$lll" "$ell" 2>&1 | sed 's/.*line //')
    printf 'DIFF %s first differing line %s: lazy: %s | eager: %s\n' "$tag" "$line" \
      "$(sed -n "${line}p" "$lll" | cut -c1-160)" "$(sed -n "${line}p" "$ell" | cut -c1-160)" \
      > "$WORK/parts/$tag"
  fi
}
export -f gate_one

if [ $SELF_TEST -eq 1 ]; then
  # The eager side also skips the Opt loop, which changes the emitted code of
  # any program that calls a function: a gate that stays green here cannot
  # see a difference at all.
  prog="$ROOT/bench/tree_transform.march"
  LAZY_GATE_EAGER_EXTRA=",opt" EAGER_EXTRA=",opt" gate_one "$prog"
  res="$(cat "$WORK/parts/"*)"
  [ $KEEP -eq 0 ] && rm -rf "$WORK"
  case "$res" in
    DIFF*) echo "self-test: RED as required ($res)"; exit 0 ;;
    *) echo "self-test FAILED: the gate did not see a real difference: $res"; exit 1 ;;
  esac
fi

if [ ${#FILES[@]} -gt 0 ]; then
  printf '%s\n' "${FILES[@]}" > "$WORK/fixtures.txt"
else
  ls "$ROOT"/test/native/*.march "$ROOT"/test/native/*/entry.march \
    "$ROOT"/test/snapshots/src/*.march "$ROOT"/bench/*.march \
    "$ROOT"/test/cap_conformance/*.march \
    2>/dev/null > "$WORK/fixtures.txt"
fi
if [ -n "$SHARD" ]; then
  k="${SHARD%/*}"; n="${SHARD#*/}"
  awk -v k="$k" -v n="$n" '(NR - 1) % n == k - 1' "$WORK/fixtures.txt" > "$WORK/fixtures.shard"
  mv "$WORK/fixtures.shard" "$WORK/fixtures.txt"
fi
want=$(wc -l < "$WORK/fixtures.txt" | tr -d ' ')
# Warm the private HOME's stdlib cache with one serial compile.
gate_one "$(head -1 "$WORK/fixtures.txt")"
start_s=$(date +%s)
tr '\n' '\0' < "$WORK/fixtures.txt" | xargs -0 -P "$JOBS" -n 1 bash -c 'gate_one "$1"' _ \
  || { echo "FATAL: xargs failed; the sweep is incomplete"; exit 2; }
got=$(ls "$WORK/parts" | wc -l | tr -d ' ')
[ "$got" -eq "$want" ] || { echo "FATAL: $got of $want programs produced a result"; exit 2; }
cat "$WORK"/parts/* | sort > "$WORK/results.txt"
same=$(grep -c '^SAME' "$WORK/results.txt")
diffs=$(grep -c '^DIFF' "$WORK/results.txt")
skips=$(grep -c '^SKIP' "$WORK/results.txt")
engaged=$(grep -c '^SAME .* 1$' "$WORK/results.txt")
echo "jobs=$JOBS elapsed=$(( $(date +%s) - start_s ))s programs=$want identical=$same different=$diffs skipped=$skips (lazy lowering engaged on $engaged)"
if [ "$diffs" -gt 0 ]; then
  grep '^DIFF' "$WORK/results.txt"
  echo "RED: lazy lowering changed the output of $diffs program(s); work dir kept: $WORK"
  exit 1
fi
if [ ${#FILES[@]} -eq 0 ] && [ -z "$SHARD" ] && { [ "$same" -lt 100 ] || [ "$engaged" -lt 100 ]; }; then
  echo "FATAL: only $same programs emitted and $engaged engaged lazy lowering: the gate is not exercising it"
  exit 2
fi
echo "GREEN: identical .ll with and without lazy lowering across $same programs"
[ $KEEP -eq 0 ] && rm -rf "$WORK"
exit 0
