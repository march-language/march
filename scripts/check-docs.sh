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
    find docs -type f -name '*.md' 2>/dev/null || true
    find specs/features -type f -name '*.md' 2>/dev/null || true
    find specs/lang -type f -name '*.md' 2>/dev/null || true
    find specs/impl -type f -name '*.md' 2>/dev/null || true
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

actual=$(find stdlib -maxdepth 1 -type f -name '*.march' | wc -l | tr -d ' ')

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
gr_parse="specs/lang/grammar/parse"
gr_reject="specs/lang/grammar/reject"
gr_index="specs/lang/grammar/INDEX.md"

g_actual=$(find "$g_dir" -maxdepth 1 -type f -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
ta_actual=$(find "$t_accept" -maxdepth 1 -type f -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
tr_actual=$(find "$t_reject" -maxdepth 1 -type f -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
tt_actual=$((ta_actual + tr_actual))
grp_actual=$(find "$gr_parse" -maxdepth 1 -type f -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
grr_actual=$(find "$gr_reject" -maxdepth 1 -type f -name '*.march' 2>/dev/null | wc -l | tr -d ' ')
grt_actual=$((grp_actual + grr_actual))

echo "== Check C: conformance-corpus INDEX counts (golden: $g_actual; types: $tt_actual = $ta_actual accept + $tr_actual reject; grammar: $grt_actual = $grp_actual parse + $grr_actual reject) =="
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

# grammar: parse/ + reject/ corpus (pNN/rNN naming, its own INDEX). Three
# authoritative count sites, all of which have drifted before this guard
# existed: the title range-ends, the `currently N/N — A parse, B reject` run
# line, and the `N programs total (A parse, B reject)` footer.
if [ -f "$gr_index" ]; then
  # Title: `# Grammar corpus index (p01–p24 parse, r01–r14 reject; …)`.
  grt_line=$(grep -niE '^#[^#].*p[0-9]+[^0-9]+parse' "$gr_index" | head -1)
  if [ -n "$grt_line" ]; then
    ln=${grt_line%%:*}; txt=$(line_text "$gr_index" "$ln")
    # The only `pNN…parse` / `rNN…reject` substrings in the title are its own
    # range-ends; the parenthetical task-history uses `pNN–pMM/rKK` forms with
    # no trailing `parse`/`reject`, so a plain grep + last-number is safe (do
    # NOT strip the `(…)` — the ranges live inside it). `|| true` guards the
    # grep-returns-1 case under the script's error mode.
    np=$( { echo "$txt" | grep -oiE 'p[0-9]+[^0-9]+parse' | grep -oE '[0-9]+' | tail -1; } || true )
    nr=$( { echo "$txt" | grep -oiE 'r[0-9]+[^0-9]+reject' | grep -oE '[0-9]+' | tail -1; } || true )
    check_line "$gr_index" "$ln" "$txt" "$np" "$grp_actual" "grammar title parse"
    check_line "$gr_index" "$ln" "$txt" "$nr" "$grr_actual" "grammar title reject"
  fi
  # Run line: `… currently N/N — A parse, B reject …`.
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    ln=${m%%:*}; txt=$(line_text "$gr_index" "$ln")
    nxt=$(line_text "$gr_index" "$((ln + 1))")
    joined="$txt $nxt"
    tot=$(echo "$txt" | grep -oiE 'currently +[0-9]+ */ *[0-9]+' | grep -oE '[0-9]+' | head -1)
    np=$(echo "$joined" | grep -oiE '[0-9]+ +parse' | grep -oE '[0-9]+' | head -1)
    nr=$(echo "$joined" | grep -oiE '[0-9]+ +reject' | grep -oE '[0-9]+' | head -1)
    check_line "$gr_index" "$ln" "$txt" "$tot" "$grt_actual" "grammar currently total"
    check_line "$gr_index" "$ln" "$txt" "$np" "$grp_actual" "grammar currently parse"
    check_line "$gr_index" "$ln" "$txt" "$nr" "$grr_actual" "grammar currently reject"
  done < <(grep -niE 'currently +[0-9]+ */ *[0-9]+' "$gr_index")
  # Footer: `N programs total (A parse, B reject)`.
  while IFS= read -r m; do
    [ -z "$m" ] && continue
    ln=${m%%:*}; txt=$(line_text "$gr_index" "$ln")
    tot=$(echo "$txt" | grep -oiE '[0-9]+ +programs +total' | grep -oE '[0-9]+' | head -1)
    np=$(echo "$txt" | grep -oiE '[0-9]+ +.?parse' | grep -oE '[0-9]+' | head -1)
    nr=$(echo "$txt" | grep -oiE '[0-9]+ +.?reject' | grep -oE '[0-9]+' | head -1)
    check_line "$gr_index" "$ln" "$txt" "$tot" "$grt_actual" "grammar total"
    check_line "$gr_index" "$ln" "$txt" "$np" "$grp_actual" "grammar total parse"
    check_line "$gr_index" "$ln" "$txt" "$nr" "$grr_actual" "grammar total reject"
  done < <(grep -niE '[0-9]+ +programs +total' "$gr_index")
else
  echo "  note: $gr_index not found — skipping grammar corpus"
fi
[ "$c_problems" -eq 0 ] && echo "  ok — corpus INDEX counts match on-disk file counts"

# ─── Check D: generated stdlib pages carry every public symbol ───────────────
#
# gen-stdlib-docs.yml regenerates docs/docs/stdlib/ on main and the nightly diffs
# generator output against the committed pages — both compare the GENERATOR to
# itself. Neither sees a generator that runs and emits LESS than the source
# declares (the fold_f32 / mem_peak_bytes omission in
# specs/todos/2026-09-08-ci-check-generated-stdlib-html-in-sync.md). This reads
# each page back against its module: every top-level public `fn` and `type`
# must have its anchor (`id="fn-<name>"`, `id="type-<Name>"`) on the page named
# after the `mod` declaration (Js.Audio.html, not audio.html).
#
# Gated by CHECK_STDLIB_HTML=1: on a stdlib PR the pages are red BY DESIGN until
# the bot regenerates them after merge, so this runs where the pages are
# supposed to be fresh — gen-stdlib-docs.yml before its push, and the nightly.

if [ "${CHECK_STDLIB_HTML:-0}" = "1" ]; then
echo "== Check D: generated stdlib pages vs stdlib/*.march public symbols =="
d_problems=0
d_checked=0
for src in stdlib/*.march; do
  modname=$(grep -m1 -E '^mod +[A-Za-z0-9_.]+' "$src" | awk '{print $2}')
  [ -z "$modname" ] && continue
  page="docs/docs/stdlib/$modname.html"
  if [ ! -f "$page" ]; then
    echo "  MISSING PAGE: $src declares mod $modname but $page does not exist"
    d_problems=$((d_problems + 1)); fail=1; continue
  fi
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    d_checked=$((d_checked + 1))
    grep -q "id=\"fn-$name\"" "$page" \
      || { echo "  MISSING SYMBOL: $page has no anchor for fn $name (declared in $src)"; d_problems=$((d_problems + 1)); fail=1; }
  done < <(grep -oE '^  fn +[a-z_][A-Za-z0-9_?!]*' "$src" | awk '{print $2}' | sort -u)
  while IFS= read -r name; do
    [ -z "$name" ] && continue
    d_checked=$((d_checked + 1))
    grep -q "id=\"type-$name\"" "$page" \
      || { echo "  MISSING SYMBOL: $page has no anchor for type $name (declared in $src)"; d_problems=$((d_problems + 1)); fail=1; }
  done < <(grep -oE '^  type +[A-Z][A-Za-z0-9_]*' "$src" | awk '{print $2}' | sort -u)
done
[ "$d_problems" -eq 0 ] && echo "  ok — $d_checked public symbols all anchored on their module page"
else
echo "== Check D: generated stdlib pages (skipped; set CHECK_STDLIB_HTML=1 where the pages are expected fresh) =="
fi

# ─── Check E: quarantine aliases match the quarantine inventory ──────────────
#
# A quarantined test is one whose dune rule is on a `<name>_quarantined` alias
# instead of `runtest`, so it is dark until the nightly runs it. The inventory
# of what that leaves unverified is the todo below; the nightly loop derives its
# alias list from the dune files. Both rot silently (the loop once named three
# aliases deleted two weeks earlier), so: the set of `*_quarantined` aliases in
# test/dune + forge/test/dune must equal the inventory's live (non-struck)
# rows, and no quarantine comment may point at a file that does not exist.

inventory="specs/todos/2026-07-24-quarantined-tests-coverage-that-is-currently-dark-inventory-2026.md"
echo "== Check E: quarantine aliases vs $inventory =="
e_problems=0
if [ -f "$inventory" ]; then
  defined=$(grep -hoE '\(alias +[A-Za-z0-9_]+_quarantined\)' test/dune forge/test/dune 2>/dev/null \
              | sed -E 's/\(alias +//; s/\)//' | sort -u)
  # Live rows: `| `test/<alias>` | ...` with no ~~strike~~ on the alias cell.
  listed=$(grep -E '^\| *`(test|forge/test)/[A-Za-z0-9_]+_quarantined`' "$inventory" \
             | sed -E 's/^\| *`[a-z/]*\/([A-Za-z0-9_]+_quarantined)`.*/\1/' | sort -u)
  for a in $defined; do
    grep -qx "$a" <<<"$listed" \
      || { echo "  UNLISTED ALIAS: $a is defined in a dune file but has no live row in the inventory"; e_problems=$((e_problems + 1)); fail=1; }
  done
  for a in $listed; do
    grep -qx "$a" <<<"$defined" \
      || { echo "  STALE ROW: inventory lists $a as live but no dune file defines that alias (strike the row or restore the alias)"; e_problems=$((e_problems + 1)); fail=1; }
  done
  while IFS= read -r hit; do
    [ -z "$hit" ] && continue
    echo "  DEAD POINTER: $hit (specs/todos.md no longer exists; point at $inventory)"
    e_problems=$((e_problems + 1)); fail=1
  done < <(grep -n 'specs/todos\.md' test/dune forge/test/dune 2>/dev/null || true)
  [ "$e_problems" -eq 0 ] && echo "  ok — $(echo "$defined" | grep -c . ) quarantine alias(es), inventory in sync"
else
  echo "  note: $inventory not found — skipping"
fi

echo
if [ "$fail" -ne 0 ]; then
  echo "doc-lint FAILED — fix the references above, or add a doc-lint:ignore-* marker"
  echo "for intentionally historical content. Counts/pointers should track the code."
  exit 1
fi
echo "doc-lint passed"
