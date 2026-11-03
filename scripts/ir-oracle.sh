#!/usr/bin/env bash
# IR oracle — proves a refactor changed no emitted code.
#
# --emit-llvm writes <file>.ll and exits BEFORE the CAS cache path: the CAS
# lookup lives inside the `if !do_compile` branch of bin/main.ml's compile
# function, while the --emit-llvm-only write is in that branch's `else`.  So a
# warm cache cannot short-circuit it.  Output is byte-identical across repeated
# runs and across differently-named copies of the same source (re-verified
# 2026-08-25 at 8d2b22fb), so a plain sha256 over the .ll text is a sound
# oracle.
#
# Hash the .ll TEXT, never a compiled binary: two freshly linked Mach-O
# binaries always differ (random LC_UUID), which makes `cmp` vacuous on macOS.
#
#   scripts/ir-oracle.sh baseline /tmp/ir-base   # record
#   scripts/ir-oracle.sh check    /tmp/ir-base   # compare
#
# The sweep runs MARCH_ORACLE_JOBS programs at once (default: CPU count).  Each
# worker writes only its own <tag>.{march,ll,log} and parts/<tag> under the work dir and the
# manifest is SORTED, so worker interleaving cannot move a byte.  Workers share
# a private HOME inside <dir> (warmed by one serial compile first, so the
# stdlib Marshal blob is written once, not raced), never ~/.cache/march: that
# one is shared by every worktree and its spans carry other worktrees' paths.
# MARCH_STDLIB is pinned to the source tree so a concurrent `dune build`
# restaging _build/default/stdlib cannot tear the corpus across two stdlibs.
#
# Manifests recorded before 2026-10-30 hashed IR compiled from an ABSOLUTE
# path and are not comparable with this version's; re-record them.
#
# For the usual "did my branch move any IR" question, scripts/oracle-base.sh
# records the baseline from the merge-base once and caches it by commit.
#
# See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 0, Task 0.1).
set -uo pipefail

# NB: the ${x:?msg} message must contain no `}` — bash ends the expansion at the
# first one, so a "{baseline|check}" in the message silently appends the tail of
# it to the variable's value.  (The plan's first draft had exactly that bug: MODE
# came out as "baseline <dir>}" and every invocation died with "unknown mode".)
USAGE='usage: ir-oracle.sh baseline|check <dir>'
MODE="${1:?$USAGE}"
DIR="${2:?$USAGE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# MARCH_ORACLE_EXE points the oracle at a FROZEN copy of the compiler so a
# baseline can keep running while the worktree is rebuilt underneath it (a
# relink mid-run silently mixes two compilers into one manifest).  A copy
# cannot find stdlib exe-relatively, so pair it with MARCH_STDLIB.
EXE="${MARCH_ORACLE_EXE:-$ROOT/_build/default/bin/main.exe}"
WORK="$DIR/work"
MANIFEST="$DIR/ir.sha256"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }

mkdir -p "$WORK"
rm -rf "$WORK/parts"; mkdir -p "$WORK/parts"
JOBS="${MARCH_ORACLE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
export HOME="$DIR/home"
mkdir -p "$HOME/.cache"
export MARCH_STDLIB="${MARCH_STDLIB:-$ROOT/stdlib}"
export EXE WORK

emit_one() {
  f="$1"
  base="$(basename "$f" .march)"
  # Namespace by parent dir: basenames collide across the three corpora.
  tag="$(basename "$(dirname "$f")")_$base"
  cp "$f" "$WORK/$tag.march"
  rm -f "$WORK/$tag.ll"
  # Compile by RELATIVE path from inside $WORK: the .ll embeds the source path
  # as given (panic locations, string literals and their lengths), so an
  # absolute one would make every hash depend on where <dir> is, and a baseline
  # recorded in one directory could never be checked from another.
  if (cd "$WORK" && "$EXE" --emit-llvm "$tag.march") >"$WORK/$tag.log" 2>&1 && [ -f "$WORK/$tag.ll" ]; then
    printf '%s  %s\n' "$(shasum -a 256 <"$WORK/$tag.ll" | cut -d' ' -f1)" "$tag" > "$WORK/parts/$tag"
  else
    # A fixture that does not compile is EXPECTED for some corpus entries
    # (ill-typed negative tests).  Record it as a skip WITH its tag so a
    # refactor that newly breaks a previously-emitting fixture shows up as a
    # manifest line changing, not as a silent pass.
    printf 'SKIP  %s\n' "$tag" > "$WORK/parts/$tag"
  fi
}
export -f emit_one

ls "$ROOT"/test/native/*.march "$ROOT"/test/snapshots/src/*.march "$ROOT"/bench/*.march \
  2>/dev/null > "$WORK/fixtures.txt"
# Warm the private HOME's stdlib cache with one serial compile before fanning out.
emit_one "$(head -1 "$WORK/fixtures.txt")"
start_s=$(date +%s)
# NOT `xargs -I{}`: macOS xargs refuses a -I line over 255 bytes ("command
# line cannot be assembled, too long"), stops, and leaves a partial corpus.
# With -n 1 the path is appended as $1 instead.  Then demand one part per
# fixture, so a worker or xargs that died early is an error, not a short manifest.
tr '\n' '\0' < "$WORK/fixtures.txt" | xargs -0 -P "$JOBS" -n 1 bash -c 'emit_one "$1"' _ \
  || { echo "FATAL: xargs failed; the sweep is incomplete"; exit 2; }
want=$(wc -l < "$WORK/fixtures.txt" | tr -d ' '); got=$(ls "$WORK/parts" | wc -l | tr -d ' ')
[ "$got" -eq "$want" ] || { echo "FATAL: $got of $want fixtures produced a result"; exit 2; }
cat "$WORK"/parts/* > "$WORK/manifest.tmp"
emitted=$(grep -vc '^SKIP' "$WORK/manifest.tmp")
skipped=$(grep -c '^SKIP' "$WORK/manifest.tmp")
echo "jobs=$JOBS elapsed=$(( $(date +%s) - start_s ))s"

sort "$WORK/manifest.tmp" > "$WORK/manifest.sorted"
echo "emitted=$emitted skipped=$skipped"

if [ "$emitted" -lt 100 ]; then
  echo "FATAL: only $emitted fixtures emitted IR — the corpus is not being"
  echo "exercised (stale build? wrong exe?).  Refusing to record a vacuous"
  echo "baseline."
  exit 2
fi

case "$MODE" in
  baseline)
    mkdir -p "$DIR"
    cp "$WORK/manifest.sorted" "$MANIFEST"
    echo "baseline recorded: $MANIFEST ($emitted programs)"
    ;;
  check)
    [ -f "$MANIFEST" ] || { echo "FATAL: no baseline at $MANIFEST"; exit 2; }
    if diff -u "$MANIFEST" "$WORK/manifest.sorted" > "$DIR/ir.diff"; then
      echo "IR IDENTICAL across $emitted programs"
      exit 0
    else
      echo "IR CHANGED — $(grep -c '^[+-][^+-]' "$DIR/ir.diff") differing lines:"
      head -40 "$DIR/ir.diff"
      echo "(full diff: $DIR/ir.diff)"
      exit 1
    fi
    ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
