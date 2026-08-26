#!/usr/bin/env bash
# Refinement-diagnostic oracle — proves a refine_check refactor changed no
# diagnostic.
#
# `lib/refinecheck/refine_check.ml` affects DIAGNOSTICS, not emitted code, so
# scripts/ir-oracle.sh proves exactly nothing about it: a checker that stopped
# checking emits byte-identical IR.  This script is the counterpart oracle —
# it runs `--check --refine-report` over the whole March corpus and pins every
# line of output.
#
# Two caches produce vacuous green if left warm:
#   .march/cas/artifacts-v2  -> a compile-path CAS hit short-circuits before
#                               --refine-report can print anything
#   .march/cas/vc            -> verification conditions are reused, so a
#                               checker that stopped checking still "proves"
# Both are cleared ONCE here, before the sweep — never between fixtures (the
# within-run warming is part of the recorded behaviour and is identical in the
# baseline and the check run, which walk the corpus in the same order).
#
#   scripts/refine-oracle.sh baseline /tmp/refine-base-<slug>   # record
#   scripts/refine-oracle.sh check    /tmp/refine-base-<slug>   # compare
#
# Suffix <slug> with your worktree name: /tmp is shared across every march
# worktree on this box, and a collided baseline presents as an inexplicable
# diagnostic diff — precisely the failure this oracle exists to rule out.
#
# A THIRD shared cache bites here and is not in .march/: ~/.cache/march holds
# the Marshal'd stdlib AST and typecheck env (bin/main.ml's stdlib_decls /
# get_stdlib_tc_env), keyed by stdlib content + compiler build id and shared by
# every worktree on the box.  The marshalled spans carry the ABSOLUTE paths of
# whichever worktree populated it, so stdlib diagnostics print another agent's
# directory and the diff moves without anyone touching the checker — measured
# 2026-08-26, 14 phantom `stdlib_prelude` lines.  The sweep therefore runs
# under a private HOME inside <dir>, and paths are normalised below as well.
#
# Runtime is ~6 minutes over ~300 z3-backed fixtures.  Let it finish; a
# half-run baseline is worse than none.
#
# See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 3, Task 3.1).
set -uo pipefail

# NB: the ${x:?msg} message must contain no `}` — bash ends the expansion at
# the first one, so a "{baseline|check}" in the message silently appends the
# tail of it to the variable's value.  (Both this plan's draft AND the
# ir-oracle draft had exactly that bug: MODE came out as "baseline <dir>}" and
# every invocation died with "unknown mode" before touching a fixture.)
USAGE='usage: refine-oracle.sh baseline|check <dir>'
MODE="${1:?$USAGE}"
DIR="${2:?$USAGE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/_build/default/bin/main.exe"
OUT="$DIR/refine.txt"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }

rm -rf "$ROOT/.march/cas/artifacts-v2" "$ROOT/.march/cas/vc"
mkdir -p "$DIR"
# Private HOME: ~/.cache/march is shared across worktrees (see the note above).
# Wiped per run so the stdlib blobs are always written by THIS worktree.
rm -rf "$DIR/home"
mkdir -p "$DIR/home"
export HOME="$DIR/home"
: > "$DIR/run.tmp"

n=0
for f in "$ROOT"/test/native/*.march "$ROOT"/stdlib/*.march; do
  [ -e "$f" ] || continue
  # Namespace by parent dir: basenames can collide across the two corpora.
  tag="$(basename "$(dirname "$f")")_$(basename "$f" .march)"
  # Normalise absolute paths so the manifest is machine- and worktree-
  # independent, then tag every line so a fixture that stops emitting shows up
  # as its lines disappearing rather than as a silent shift.
  # The second sed collapses any directory prefix on a stdlib path: the
  # compiler reaches prelude.march as either the staged `_build/default/bin/
  # ../stdlib/…` copy or the source tree, and which spelling appears is not a
  # property of the checker.
  "$EXE" --check --refine-report "$f" 2>&1 \
    | sed "s|$ROOT/||g" \
    | sed -E 's#[A-Za-z0-9_./-]*stdlib/#stdlib/#g' \
    | sed "s|^|$tag: |" >> "$DIR/run.tmp"
  n=$((n+1))
done

# Sorting makes the manifest insensitive to nothing that matters (every line
# carries its fixture tag) and immune to interleaving.
sort "$DIR/run.tmp" > "$DIR/run.sorted"
lines=$(wc -l < "$DIR/run.sorted" | tr -d ' ')
echo "fixtures=$n report_lines=$lines"

if [ "$n" -lt 100 ] || [ "$lines" -lt 50 ]; then
  echo "FATAL: $n fixtures / $lines report lines — the refinement checker is"
  echo "not being exercised (warm cache? stale build? wrong exe?).  Refusing"
  echo "to record a vacuous baseline."
  exit 2
fi

case "$MODE" in
  baseline)
    cp "$DIR/run.sorted" "$OUT"
    echo "baseline recorded: $OUT ($lines lines over $n fixtures)"
    ;;
  check)
    [ -f "$OUT" ] || { echo "FATAL: no baseline at $OUT"; exit 2; }
    if diff -u "$OUT" "$DIR/run.sorted" > "$DIR/refine.diff"; then
      echo "REFINEMENT DIAGNOSTICS IDENTICAL ($lines lines over $n fixtures)"
      exit 0
    else
      echo "DIAGNOSTICS CHANGED — $(grep -c '^[+-][^+-]' "$DIR/refine.diff") differing lines:"
      head -40 "$DIR/refine.diff"
      echo "(full diff: $DIR/refine.diff)"
      exit 1
    fi
    ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
