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
    find specs/impl -name '*.md' 2>/dev/null || true
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

# ─── Check C: conformance-corpus INDEX count consistency ─────────────────────
#
# Each conformance corpus ships an INDEX.md that states, in a few well-known
# AUTHORITATIVE forms, the total program count that is supposed to equal the
# number of `.march` files on disk. Human review missed a stale count three
# times running; this lint kills the class.
#
#   golden: actual = #(specs/lang/golden/*.march). Authoritative sites in
#           specs/lang/golden/INDEX.md:
#             - the `# … (g01–gNN)` title range-end,
#             - the `N/N MATCH` run-instructions count.
#   types:  actual accept = #(specs/lang/types/accept/*.march),
#           actual reject = #(specs/lang/types/reject/*.march), total = sum.
#           Authoritative sites in specs/lang/types/INDEX.md:
#             - the `# … (t01–tAA accept, t01–tRR reject)` title range-ends,
#             - the `currently T/T — A accept, B reject` run line,
#             - the `**Result: T / T (A accept, B reject).**` footer.
#
# DELIBERATELY narrow: only these two INDEX files, only their total-count sites.
# Reference docs elsewhere in specs/ carry illustrative/partial/historical
# `N/N` numbers that are NOT the full corpus total — linting them all would be a
# false-positive machine. A count line bearing `doc-lint:ignore-count` opts out
# (e.g. a deliberately-partial illustrative table), same marker as Check B.
#
# emit_mismatch FILE LINENO CLAIMED ACTUAL LABEL — records one failure.
emit_mismatch() {
  echo "  COUNT MISMATCH: $1:$2 claims $5=$3, actual is $4"
  c_problems=$((c_problems + 1))
  fail=1
}
# check_line FILE LINENO TEXT CLAIMED ACTUAL LABEL — compare unless suppressed.
check_line() {
  echo "$3" | grep -q 'doc-lint:ignore-count' && return 0
  [ -n "$4" ] && [ "$4" != "$5" ] && emit_mismatch "$1" "$2" "$4" "$5" "$6"
  return 0
}
# num_at FILE LINENO — the raw text of one line (for suppression + extraction).
line_text() { sed -n "${2}p" "$1" 2>/dev/null; }

g_dir="specs/lang/golden"
g_index="$g_dir/INDEX.md"
t_accept="specs/lang/types/accept"
t_reject="specs/lang/types/reject"
t_index="specs/lang/types/INDEX.md"

g_actual=$(find "$g_dir" -maxdepth 1 -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
ta_actual=$(find "$t_accept" -maxdepth 1 -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
tr_actual=$(find "$t_reject" -maxdepth 1 -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
tt_actual=$((ta_actual + tr_actual))

echo "== Check C: conformance-corpus INDEX counts (golden: $g_actual; types: $tt_actual = $ta_actual accept + $tr_actual reject) =="
c_problems=0

if [ -f "$g_index" ]; then
  # Title: `# Golden corpus index (g01–g37)` — trailing gNN is the count.
  gt_line=$(grep -niE '^#[^#].*\(g[0-9]+' "$g_index" | head -1)
  if [ -n "$gt_line" ]; then
    ln=${gt_line%%:*}; txt=$(line_text "$g_index" "$ln")
    n=$(echo "$txt" | grep -oiE 'g[0-9]+' | tail -1 | grep -oE '[0-9]+')
    check_line "$g_index" "$ln" "$txt" "$n" "$g_actual" "golden total"
  fi
  # Run line: `… (N/N MATCH …)` — both numbers must equal the golden count.
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    ln=${m%%:*}; txt=$(line_text "$g_index" "$ln")
    a=$(echo "$txt" | grep -oiE '[0-9]+ */ *[0-9]+ +MATCH' | grep -oE '[0-9]+' | head -1)
    b=$(echo "$txt" | grep -oiE '[0-9]+ */ *[0-9]+ +MATCH' | grep -oE '[0-9]+' | sed -n 2p)
    check_line "$g_index" "$ln" "$txt" "$a" "$g_actual" "golden MATCH (lhs)"
    check_line "$g_index" "$ln" "$txt" "$b" "$g_actual" "golden MATCH (rhs)"
  done < <(grep -niE '[0-9]+ */ *[0-9]+ +MATCH' "$g_index")
else
  echo "  note: $g_index not found — skipping golden corpus"
fi

if [ -f "$t_index" ]; then
  # Title: `# Typing corpus index (t01–t40 accept, t01–t29 reject)`.
  tt_line=$(grep -niE '^#[^#].*t[0-9]+[^0-9]+accept' "$t_index" | head -1)
  if [ -n "$tt_line" ]; then
    ln=${tt_line%%:*}; txt=$(line_text "$t_index" "$ln")
    na=$(echo "$txt" | grep -oiE 't[0-9]+[^0-9]+accept' | grep -oE '[0-9]+' | tail -1)
    nr=$(echo "$txt" | grep -oiE 't[0-9]+[^0-9]+reject' | grep -oE '[0-9]+' | tail -1)
    check_line "$t_index" "$ln" "$txt" "$na" "$ta_actual" "types title accept"
    check_line "$t_index" "$ln" "$txt" "$nr" "$tr_actual" "types title reject"
  fi
  # Run line: `… currently N/N — A accept, B reject …` (may wrap; A/B may be on
  # the next physical line, so read the run line plus its continuation).
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    ln=${m%%:*}; txt=$(line_text "$t_index" "$ln")
    nxt=$(line_text "$t_index" "$((ln + 1))")
    joined="$txt $nxt"
    tot=$(echo "$txt" | grep -oiE 'currently +[0-9]+ */ *[0-9]+' | grep -oE '[0-9]+' | head -1)
    na=$(echo "$joined" | grep -oiE '[0-9]+ +accept' | grep -oE '[0-9]+' | head -1)
    nr=$(echo "$joined" | grep -oiE '[0-9]+ +reject' | grep -oE '[0-9]+' | head -1)
    check_line "$t_index" "$ln" "$txt" "$tot" "$tt_actual" "types currently total"
    check_line "$t_index" "$ln" "$txt" "$na" "$ta_actual" "types currently accept"
    check_line "$t_index" "$ln" "$txt" "$nr" "$tr_actual" "types currently reject"
  done < <(grep -niE 'currently +[0-9]+ */ *[0-9]+' "$t_index")
  # Footer: `**Result: N / N (A accept, B reject).**`.
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    ln=${m%%:*}; txt=$(line_text "$t_index" "$ln")
    tot=$(echo "$txt" | grep -oiE 'result: *[0-9]+ */ *[0-9]+' | grep -oE '[0-9]+' | head -1)
    na=$(echo "$txt" | grep -oiE '[0-9]+ +accept' | grep -oE '[0-9]+' | head -1)
    nr=$(echo "$txt" | grep -oiE '[0-9]+ +reject' | grep -oE '[0-9]+' | head -1)
    check_line "$t_index" "$ln" "$txt" "$tot" "$tt_actual" "types Result total"
    check_line "$t_index" "$ln" "$txt" "$na" "$ta_actual" "types Result accept"
    check_line "$t_index" "$ln" "$txt" "$nr" "$tr_actual" "types Result reject"
  done < <(grep -niE '\*\*result: *[0-9]+ */ *[0-9]+' "$t_index")
else
  echo "  note: $t_index not found — skipping types corpus"
fi
[ "$c_problems" -eq 0 ] && echo "  ok — corpus INDEX counts match on-disk file counts"

echo
if [ "$fail" -ne 0 ]; then
  echo "doc-lint FAILED — fix the references above, or add a doc-lint:ignore-* marker"
  echo "for intentionally historical content. Counts/pointers should track the code."
  exit 1
fi
echo "doc-lint passed"
