#!/usr/bin/env bash
# Typecheck diagnostic + inference oracle — proves a typecheck.ml refactor
# changed neither an inferred type nor a diagnostic byte.
#
# `lib/typecheck/typecheck.ml` produces two observable things, and NEITHER of
# the pre-existing harnesses pins both:
#
#   * `dune build @types-check` is a conformance gate, not a pin.  For the
#     reject/ corpus it asserts only that the output CONTAINS the one substring
#     in the fixture's `-- EXPECT-ERROR:` annotation, and for accept/ only that
#     the exit code is 0.  A refactor that reworded every hint, dropped every
#     reason chain and moved every span by a column still passes it.  (It is
#     also VACUOUS without `--force`: it exits 0 with a zero-byte log.)
#   * `scripts/ir-oracle.sh` sees inference RESULTS (TIR lowering consumes
#     type_map), but only on the accept path, and a change that moved only a
#     diagnostic does not move a byte of IR.
#
# Hence two tiers, which are complementary and neither of which subsumes the
# other (measured 2026-08-26):
#
#   Tier 1 — `--emit-core-ast`.  One JSON document per fixture: verdict,
#     diagnostics, the desugared module with `resolved_ty` on every node, plus
#     `schemes`, `instantiations` and `module_caps`.  This is the whole
#     checker's RESULT, and it is the only tier that says anything at all on
#     the accept path (`--check` on an accepting program prints zero bytes).
#     Stored as one sha256 per fixture — a full-JSON manifest over ~600
#     fixtures is ~10 MB and unreadable as a diff — and on a mismatch the
#     offending fixtures' JSON is re-emitted into the diff directory so the
#     change is actually investigable.
#
#   Tier 2 — plain `--check` text.  The JSON `diagnostics` array keeps only the
#     FIRST LINE of each message.  Measured on reject/t01_int_vs_string.march:
#     the JSON gives `expected `Int` but got `String`.` and nothing more, while
#     the text additionally carries the source excerpt, the
#     `This is the declared return type of `f`.` provenance line, the
#     `the expected type comes from here:` reason chain and the
#     `Use `int_to_string(x)` to convert…` hint — all of it produced by
#     pp_ty / message_part / render_parts.  Stored as full text, tagged per
#     fixture and sorted.  This is the tier whose diff you read.
#
# Warnings (exhaustiveness, redundant arms, unused linear bindings) are
# Tier 2-only: `@types-check` does not assert on them at all.  If Tier 2 moves
# while Tier 1 does not, you changed a MESSAGE; that is a semantic change, not
# code motion.
#
#   scripts/types-oracle.sh baseline /tmp/types-base-<slug>   # record
#   scripts/types-oracle.sh check    /tmp/types-base-<slug>   # compare
#
# Suffix <slug> with your worktree name: /tmp is shared across every march
# worktree on this box, and a collided baseline presents as an inexplicable
# diagnostic diff — precisely the failure this oracle exists to rule out.
#
# ~/.cache/march holds the Marshal'd stdlib AST and typecheck env, shared by
# every worktree on the box, and its spans carry the POPULATING worktree's
# absolute paths (14 phantom diff lines naming another agent's worktree,
# measured during Phase 3).  The sweep therefore runs under a private HOME
# inside <dir>, and paths are normalised below as well.  Note the `.cache`
# subdirectory is created too: the compiler's cache-save mkdir is not
# recursive, so with only `home` present every fixture's output gains 177 bytes
# of `[warn] could not save the stdlib typecheck cache` noise AND the stdlib is
# re-typechecked on every invocation.  (Filed as
# specs/todos/2026-08-26-stdlib-cache-mkdir-not-recursive.md — worked around
# here, not fixed here.)
#
# See specs/plans/2026-08-19-compiler-file-decomposition.md (Phase 6, Task 6.1).
set -uo pipefail

# NB: the ${x:?msg} message must contain no `}` — bash ends the expansion at
# the first one, so a "{baseline|check}" in the message silently sets the
# variable to the tail of the message and every invocation dies with
# "unknown mode" before touching a fixture.  Two drafts in this plan shipped
# exactly that bug.
USAGE='usage: types-oracle.sh baseline|check <dir>'
MODE="${1:?$USAGE}"
DIR="${2:?$USAGE}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXE="$ROOT/_build/default/bin/main.exe"
MANIFEST="$DIR/core_ast.sha256"
REPORT="$DIR/diagnostics.txt"

[ -x "$EXE" ] || { echo "FATAL: $EXE not built. Run: dune build --root . bin/main.exe"; exit 2; }

# --check is not the compile path, but --emit-core-ast shares plumbing with it;
# clearing costs nothing and rules the class out.  Do NOT clear .march/cas/vc —
# that is the refinement oracle's concern and clearing it here only slows the
# run.
rm -rf "$ROOT/.march/cas/artifacts-v2"

mkdir -p "$DIR/json"
rm -f "$DIR"/json/*.json
rm -rf "$DIR/home"
mkdir -p "$DIR/home/.cache"      # NOT just $DIR/home — see the note above
export HOME="$DIR/home"
: > "$DIR/sha.tmp"
: > "$DIR/diag.tmp"

cd "$ROOT" || exit 2

# Serially typecheck ONE fixture first, to populate the private HOME's stdlib
# cache before the parallel sweep: several hundred processes racing to write
# that Marshal blob is not a race worth taking, and the warm cache is also what
# makes the parallel sweep fast.
"$EXE" --check "$ROOT/specs/lang/types/accept/t01_literals.march" > /dev/null 2>&1 || true

# One fixture per worker.  Output is per-fixture and tagged, and both manifests
# are SORTED below, so interleaving across workers cannot move a byte — the
# same property check_types.sh relies on.  Never parallelise without the sort.
export EXE ROOT DIR
sweep_one() {
  f="$1"
  # Namespace by parent dir: basenames collide across the four corpora.
  tag="$(basename "$(dirname "$f")")_$(basename "$f" .march)"
  # Normalise: strip the repo root, then collapse any directory prefix on a
  # stdlib/ path — the compiler reaches prelude.march as either the staged
  # `_build/default/bin/../stdlib/…` copy or the source tree, and which
  # spelling appears is not a property of the checker.
  # Tier 1: the checker's whole result, hashed.  The JSON is kept on disk so a
  # mismatch can be diffed rather than merely reported.
  "$EXE" --emit-core-ast "$f" 2>&1 \
    | sed "s|$ROOT/||g" | sed -E 's#[A-Za-z0-9_./-]*stdlib/#stdlib/#g' \
    > "$DIR/json/$tag.json"
  printf '%s  %s\n' "$(shasum -a 256 < "$DIR/json/$tag.json" | cut -d' ' -f1)" "$tag" \
    >> "$DIR/sha.parts/$tag"
  # Tier 2: the rendered diagnostic text, tagged so a fixture that stops
  # emitting shows up as its lines disappearing rather than as a silent shift.
  "$EXE" --check "$f" 2>&1 \
    | sed "s|$ROOT/||g" | sed -E 's#[A-Za-z0-9_./-]*stdlib/#stdlib/#g' \
    | sed "s|^|$tag: |" >> "$DIR/diag.parts/$tag"
}
export -f sweep_one

rm -rf "$DIR/sha.parts" "$DIR/diag.parts"
mkdir -p "$DIR/sha.parts" "$DIR/diag.parts"
ls "$ROOT"/specs/lang/types/accept/*.march \
   "$ROOT"/specs/lang/types/reject/*.march \
   "$ROOT"/test/native/*.march \
   "$ROOT"/stdlib/*.march 2>/dev/null > "$DIR/fixtures.txt"
n=$(wc -l < "$DIR/fixtures.txt" | tr -d ' ')
xargs -P 8 -n 1 -I{} bash -c 'sweep_one "$@"' _ {} < "$DIR/fixtures.txt"

cat "$DIR/sha.parts"/*  > "$DIR/sha.tmp"  2>/dev/null
cat "$DIR/diag.parts"/* > "$DIR/diag.tmp" 2>/dev/null

sort "$DIR/sha.tmp"  > "$DIR/sha.sorted"
sort "$DIR/diag.tmp" > "$DIR/diag.sorted"
lines=$(wc -l < "$DIR/diag.sorted" | tr -d ' ')
echo "fixtures=$n report_lines=$lines"

# Non-vacuity guards.  Deliberately inequalities, not equalities — the corpora
# grow.  A guard firing means investigate, not lower the guard.
if [ "$n" -lt 400 ] || [ "$lines" -lt 500 ]; then
  echo "FATAL: $n fixtures / $lines report lines — the typechecker is not being"
  echo "exercised (stale build? wrong exe? corpus missing?).  Refusing to"
  echo "record a vacuous baseline."
  exit 2
fi

case "$MODE" in
  baseline)
    cp "$DIR/sha.sorted"  "$MANIFEST"
    cp "$DIR/diag.sorted" "$REPORT"
    rm -rf "$DIR/json_base"
    cp -R "$DIR/json" "$DIR/json_base"
    echo "baseline recorded: $MANIFEST + $REPORT ($lines lines over $n fixtures)"
    ;;
  check)
    [ -f "$MANIFEST" ] || { echo "FATAL: no baseline at $MANIFEST"; exit 2; }
    [ -f "$REPORT" ]   || { echo "FATAL: no baseline at $REPORT"; exit 2; }
    rc=0
    if diff -u "$MANIFEST" "$DIR/sha.sorted" > "$DIR/core_ast.diff"; then
      echo "TIER1 CORE-AST IDENTICAL ($n fixtures)"
    else
      rc=1
      changed=$(grep '^[+-][^+-]' "$DIR/core_ast.diff" | awk '{print $NF}' | sort -u)
      echo "TIER1 CORE-AST CHANGED — $(echo "$changed" | wc -l | tr -d ' ') fixtures:"
      echo "$changed" | head -20
      # Re-emit the offending fixtures' JSON diffs so the change is
      # investigable rather than merely reported.
      : > "$DIR/core_ast_json.diff"
      for t in $changed; do
        [ -f "$DIR/json_base/$t.json" ] || continue
        diff -u "$DIR/json_base/$t.json" "$DIR/json/$t.json" >> "$DIR/core_ast_json.diff"
      done
      echo "(fixture hashes: $DIR/core_ast.diff ; JSON diffs: $DIR/core_ast_json.diff)"
    fi
    if diff -u "$REPORT" "$DIR/diag.sorted" > "$DIR/diagnostics.diff"; then
      echo "TIER2 DIAGNOSTICS IDENTICAL ($lines lines over $n fixtures)"
    else
      rc=1
      echo "TIER2 DIAGNOSTICS CHANGED — $(grep -c '^[+-][^+-]' "$DIR/diagnostics.diff") differing lines:"
      head -40 "$DIR/diagnostics.diff"
      echo "(full diff: $DIR/diagnostics.diff)"
    fi
    exit $rc
    ;;
  *) echo "unknown mode: $MODE"; exit 2 ;;
esac
