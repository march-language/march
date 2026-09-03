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
: > "$WORK/manifest.tmp"
skipped=0; emitted=0

for f in "$ROOT"/test/native/*.march "$ROOT"/test/snapshots/src/*.march "$ROOT"/bench/*.march; do
  [ -e "$f" ] || continue
  base="$(basename "$f" .march)"
  # Namespace by parent dir: basenames collide across the three corpora.
  tag="$(basename "$(dirname "$f")")_$base"
  cp "$f" "$WORK/$tag.march"
  rm -f "$WORK/$tag.ll"
  if "$EXE" --emit-llvm "$WORK/$tag.march" >"$WORK/$tag.log" 2>&1 && [ -f "$WORK/$tag.ll" ]; then
    printf '%s  %s\n' "$(shasum -a 256 <"$WORK/$tag.ll" | cut -d' ' -f1)" "$tag" >> "$WORK/manifest.tmp"
    emitted=$((emitted+1))
  else
    # A fixture that does not compile is EXPECTED for some corpus entries
    # (ill-typed negative tests).  Record it as a skip WITH its tag so a
    # refactor that newly breaks a previously-emitting fixture shows up as a
    # manifest line changing, not as a silent pass.
    printf 'SKIP  %s\n' "$tag" >> "$WORK/manifest.tmp"
    skipped=$((skipped+1))
  fi
done

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
