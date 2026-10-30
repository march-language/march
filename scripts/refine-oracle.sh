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
# Both live under the compiler's cwd (<cwd>/.march/cas), so every fixture runs
# from its own fresh directory under <dir>/cwd/: each one starts with both
# caches cold, nothing warms across fixtures, and the fixtures can run in
# parallel (MARCH_ORACLE_JOBS at once, default: CPU count) without one
# fixture's cache hits depending on which others happened to finish first.
# (Before 2026-10-30 the sweep was serial and shared one warming cache in the
# repo root; a baseline recorded by that version is not comparable to this
# one.  Re-record it.)
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
# Serial, this took ~6 minutes; in parallel it is bounded by the slowest
# fixtures.  Let it finish; a half-run baseline is worse than none.
#
# For the usual "did my branch move any diagnostic" question,
# scripts/oracle-base.sh records the baseline from the merge-base once and
# caches it by commit.
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
EXE="${MARCH_ORACLE_EXE:-$ROOT/_build/default/bin/main.exe}"
OUT="$DIR/refine.txt"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }

mkdir -p "$DIR"
# Private HOME: ~/.cache/march is shared across worktrees (see the note above).
# Wiped per run so the stdlib blobs are always written by THIS worktree.
rm -rf "$DIR/home" "$DIR/cwd" "$DIR/parts"
mkdir -p "$DIR/home/.cache" "$DIR/cwd" "$DIR/parts"
export HOME="$DIR/home"
# The stdlib is pinned to the source tree, as the RELATIVE path `stdlib`
# through each cwd's symlink (see check_one).  Pinned, because a concurrent
# `dune build` restages _build/default/stdlib, which the compiler would
# otherwise read exe-relatively.  Relative, because the corpus includes
# stdlib/prelude.march itself: unless the fixture path and the loaded prelude
# are the same string, the checker sees two preludes and reports 11
# overlapping_impl errors of the prelude against itself.
JOBS="${MARCH_ORACLE_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 8)}"
export EXE ROOT DIR

check_one() {
  f="$1"
  # Namespace by parent dir: basenames can collide across the two corpora.
  tag="$(basename "$(dirname "$f")")_$(basename "$f" .march)"
  # Fresh every time, warm-up run included: a leftover .march/cas would be warm.
  # Fresh cwd per fixture (cold .march/cas), but the compiler must still be
  # handed the SAME relative path as from the repo root: rendered headers pad
  # with dashes to the path's length, and derive-generated spans hash the path,
  # so an absolute one makes the output depend on where the tree lives (a base
  # export vs this worktree) even after the prefix is stripped.  Symlinking the
  # corpus roots into the cwd gives the relative path without the shared cache.
  rm -rf "$DIR/cwd/$tag"; mkdir -p "$DIR/cwd/$tag"
  for t in test stdlib; do ln -s "$ROOT/$t" "$DIR/cwd/$tag/$t"; done
  # Normalise absolute paths so the manifest is machine- and worktree-
  # independent, then tag every line so a fixture that stops emitting shows up
  # as its lines disappearing rather than as a silent shift.
  # The second sed collapses any directory prefix on a stdlib path: the
  # compiler reaches prelude.march as either the staged `_build/default/bin/
  # ../stdlib/…` copy or the source tree, and which spelling appears is not a
  # property of the checker.
  (cd "$DIR/cwd/$tag" && MARCH_STDLIB=stdlib "$EXE" --check --refine-report "${f#$ROOT/}") 2>&1 \
    | sed "s|$DIR/cwd/$tag/||g" \
    | sed "s|$ROOT/||g" \
    | sed -E 's#[A-Za-z0-9_./-]*stdlib/#stdlib/#g' \
    | sed "s|^|$tag: |" > "$DIR/parts/$tag"
}
export -f check_one

ls "$ROOT"/test/native/*.march "$ROOT"/stdlib/*.march 2>/dev/null > "$DIR/fixtures.txt"
n=$(wc -l < "$DIR/fixtures.txt" | tr -d ' ')
# One serial run first so the private HOME's stdlib cache is written once
# rather than raced by every worker.
check_one "$(head -1 "$DIR/fixtures.txt")"
start_s=$(date +%s)
# NOT `xargs -I{}`: macOS xargs refuses a -I line over 255 bytes ("command
# line cannot be assembled, too long"), stops, and leaves a partial corpus.
# With -n 1 the path is appended as $1 instead.  Then demand one part per
# fixture, so a worker or xargs that died early is an error, not a short report.
tr '\n' '\0' < "$DIR/fixtures.txt" | xargs -0 -P "$JOBS" -n 1 bash -c 'check_one "$1"' _ \
  || { echo "FATAL: xargs failed; the sweep is incomplete"; exit 2; }
got=$(ls "$DIR/parts" | wc -l | tr -d ' ')
[ "$got" -eq "$n" ] || { echo "FATAL: $got of $n fixtures produced a result"; exit 2; }
cat "$DIR"/parts/* > "$DIR/run.tmp"
echo "jobs=$JOBS elapsed=$(( $(date +%s) - start_s ))s"

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
