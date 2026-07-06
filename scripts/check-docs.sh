#!/usr/bin/env bash
# Documentation freshness lint.
#
# Catches the two ways the *current-truth* docs silently rot against the code:
#
#   A. Dead source pointers — a doc cites a compiler-source file (lib/…, runtime/…,
#      bin/…, lsp/…, forge/…, test/…) that no longer exists. This is how
#      test/test_march.ml kept being referenced after the suite was split into
#      run_*.ml, and how specs/features/lsp-server.md pointed at lib/… paths that
#      actually live under lsp/lib/….
#
#   B. Stdlib module-count drift — a doc asserts "N stdlib modules" with an N that
#      disagrees with the actual count of stdlib/*.march.
#
# SCOPE: only docs that are supposed to describe the code *as it is now* — the
# top-level guides, the published site docs, the per-feature specs, and the agent
# skill reference. The historical corpus (specs/plans/, dated design specs, the
# append-only progress.md / todos.md) is intentionally NOT linted: those are
# point-in-time records and may reference since-deleted files by design.
#
# Conceptual prose (true across refactors) is never checked — only concrete
# file pointers and counts, which must track the code.
#
# Usage:
#   scripts/check-docs.sh          # report problems, exit 1 if any
#
# Suppression:
#   - `<!-- doc-lint:ignore-count -->` on a line exempts one count assertion.
#   - `<!-- doc-lint:ignore-file -->` anywhere in a doc skips path checks for it.
#   - `.march` paths are not checked (tutorial placeholders dominate); add the
#     module to stdlib/ and reference it by name in prose instead.

set -euo pipefail

cd "$(dirname "$0")/.."

fail=0

# Current-truth docs: an explicit allowlist, not a glob over all of specs/.
# New dated design specs land in specs/ over time and are historical by nature;
# keeping this list explicit is what stops the check from drowning in them.
lint_docs() {
  {
    echo README.md
    echo CLAUDE.md
    echo syntax_reference.md
    echo specs/perceus-invariants.md
    find docs -name '*.md' 2>/dev/null || true
    find specs/features -name '*.md' 2>/dev/null || true
    find specs/lang -name '*.md' 2>/dev/null || true
    echo .claude/skills/march-lang/SKILL.md
  } | while IFS= read -r f; do [ -f "$f" ] && echo "$f"; done \
    | grep -vE '/plans/|/superpowers/'   # historical/plan corpora & vendored plugin docs are not current-truth
}

# ─── Check A: dead source pointers ───────────────────────────────────────────
#
# Compiler-source paths only: a known code dir + a source extension. `.march`
# is deliberately excluded (docs use lib/foo.march, lib/my_app.march, etc. as
# illustrative placeholders). C headers are limited to runtime/ and lib/.
#
# Matches are bracketed by non-path boundaries so that "stdlib/List.html" does
# NOT yield a phantom "lib/List.h" (left "lib" is mid-word; ".html" ≠ ".h"). A
# line that explicitly documents a path's removal ("no longer exists") is left
# alone — describing dead files is correct, not rot.

OCAML_RE='(lib|runtime|bin|forge|lsp|test)/[A-Za-z0-9_./-]+\.(ml|mli|mll|mly)'
C_RE='(runtime|lib)/[A-Za-z0-9_./-]+\.(c|h)'
BOUNDED="(^|[^A-Za-z0-9.])($OCAML_RE|$C_RE)([^A-Za-z0-9]|\$)"

echo "== Check A: source pointers in current docs =="
a_problems=0
while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  grep -q 'doc-lint:ignore-file' "$doc" 2>/dev/null && continue
  while IFS= read -r ref; do
    [ -z "$ref" ] && continue
    if [ ! -e "$ref" ]; then
      echo "  DEAD PATH: $doc references missing '$ref'"
      a_problems=$((a_problems + 1))
      fail=1
    fi
  # Drop lines that say the path is gone, then re-extract the clean token from
  # each boundary-bracketed match.
  done < <(grep -vE 'no longer exists|removed|renamed|deleted|doc-lint:ignore' "$doc" 2>/dev/null \
             | grep -hoE "$BOUNDED" 2>/dev/null \
             | grep -hoE "$OCAML_RE|$C_RE" 2>/dev/null | sort -u)
done < <(lint_docs)
[ "$a_problems" -eq 0 ] && echo "  ok — all cited source paths exist"

# ─── Check B: stdlib module-count drift ──────────────────────────────────────
#
# The actual count is the source of truth. Extract the number immediately
# preceding "modules" (not the first number on the line) so phrases like
# "Phase 1 ... 57 stdlib modules" compare 57, not 1.

actual=$(find stdlib -maxdepth 1 -name '*.march' | wc -l | tr -d ' ')

echo "== Check B: stdlib module count (actual: $actual) =="
b_problems=0
while IFS= read -r doc; do
  [ -z "$doc" ] && continue
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    lineno=${line%%:*}
    text=${line#*:}
    echo "$text" | grep -q 'doc-lint:ignore-count' && continue
    # The integer directly before "stdlib modules" / "modules".
    n=$(echo "$text" | grep -oiE '[0-9]+ (March )?(stdlib )?modules' | grep -oE '[0-9]+' | head -1)
    if [ -n "$n" ] && [ "$n" != "$actual" ]; then
      echo "  COUNT DRIFT: $doc:$lineno claims $n, actual is $actual"
      echo "    > $(echo "$text" | sed 's/^[[:space:]]*//' | cut -c1-90)"
      b_problems=$((b_problems + 1))
      fail=1
    fi
  done < <(grep -niE '[0-9]+ (March )?(stdlib )?modules' "$doc" 2>/dev/null || true)
done < <(lint_docs)
[ "$b_problems" -eq 0 ] && echo "  ok — no stale stdlib counts"

echo
if [ "$fail" -ne 0 ]; then
  echo "doc-lint FAILED — fix the references above, or add a doc-lint:ignore-* marker"
  echo "for intentionally historical content. Counts/pointers should track the code."
  exit 1
fi
echo "doc-lint passed"
