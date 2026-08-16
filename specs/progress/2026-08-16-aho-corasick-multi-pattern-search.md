# `AhoCorasick` — multi-pattern string search stdlib module

**Status:** Landed (2026-08-16). Step 4 (second sub-item) of the search-module
sequencing in `specs/plans/2026-08-09-parsing-and-string-search.md` §10:
"SIMD literal scan first ..., then Aho-Corasick (which March-written lexers
want anyway), then the linear-worst-case engine". The linear-worst-case
`Regex` engine already shipped
(`specs/progress/2026-08-12-regex-linear-matcher.md`,
`2026-08-12-regex-find-family-still-backtracks.md` is the one still-open
piece of that). Aho-Corasick itself had never been built — this closes that
gap. `forge search "trie"` / `"Aho"` / `"Array.make"` before starting turned
up nothing reusable (Array's `TrieNode` is an unrelated 32-way persistent
vector, not a byte trie), so this is new, not a port of an existing internal
structure.

## What shipped

`stdlib/aho_corasick.march`, module `AhoCorasick`:

- `build(patterns : List(String)) : Automaton` — classic construction: insert
  each pattern into a byte trie, then BFS over the trie to compute failure
  links (the mismatch fallback edge) and merge output sets along the failure
  chain, so a match of a pattern that is a *suffix* of the trie path actually
  walked is still reported (the standard "he"/"she" example: scanning
  "ushers" walks the trie path for "she", but "he" — a suffix of "she" reached
  via the failure link — must also be reported as matching at the same end
  position).
- `find_all(automaton, haystack) : List(Match)` — every match in one linear
  pass. `Match = { start, stop, pattern_index, pattern }`, half-open byte
  range, ordered by end position ascending, same-end-position matches ordered
  longest-pattern-first.
- `find_first` / `matches` — short-circuiting variants.
- `pattern_at` / `pattern_count` — introspection over the pattern list passed
  to `build`.

Complexity: `build` is O(total pattern length); `find_all` (and friends) is
O(haystack length), independent of the number of patterns — the whole point
versus the naive alternative of N separate `String.index_of` scans, which is
O(N × haystack length). An empty pattern string is skipped during `build`
(documented in the module doc) rather than special-cased through the rest of
the module — it would otherwise match with zero width at every position.

### Representation

Nodes live in an `Array(AcNode)` (the stdlib's 32-way persistent-trie vector,
`stdlib/array.march`), indexed by node id (0 = root), giving O(log₃₂ n)
amortised access while the trie still grows one node at a time via
`Array.push` during insertion. `AcNode(children, fail, outputs)`:
`children` is a sparse `(byte, child_id)` assoc list (only bytes actually
present in some pattern get a trie edge — dense 256-way tables would waste
memory for the common case of a handful of ASCII keywords); `fail` is the
failure-link target; `outputs` is the pattern-index list already merged
along the failure chain at construction time, so scanning never needs to walk
the chain to collect matches, only to find the next transition (`scan_step`).
BFS-order failure-link computation (via `stdlib/queue.march`'s `Queue`) is
what makes the merge correct: a node's failure link is computed only after
every shallower node's failure link (and merged outputs) are already final,
which is the standard "goto defined recursively via already-computed fail
links of shallower nodes" construction — no dense per-byte transition table
is materialized.

Byte-oriented throughout, `string_byte_at` / `string_byte_length`, matching
`Regex` and `Json`'s convention — no per-byte allocation, and safe for UTF-8
input for the same reason those modules are (multibyte continuation bytes are
always `>= 0x80` and only ever match themselves).

## Two parser/syntax traps hit along the way (worth a general note)

1. **`doc "..."` only attaches to a following `fn`/`pfn` declaration in the
   grammar** (`parser.mly`: `DOC; s = STRING; d = fn_decl`) — it cannot
   precede a `type`/`ptype` declaration. `stdlib/regex.march`'s `RegexOpts`
   uses a plain `--` comment above its `type` declaration for exactly this
   reason; I had originally written `doc """ ... """` above `type Match =
   {...}` by analogy with the function docs elsewhere in the file and hit
   "I got stuck here" pointing at the type name itself. Fixed by switching to
   a `--` block comment, matching `RegexOpts`.
2. **`if cond do X else do Y end` needs an `end` for the `do`-block AND a
   separate `end` for the `if` itself** — confirmed against
   `stdlib/regex.march:512-523`'s `QOneOrMore` case, which has exactly this
   shape (`try_n(max_n) end` closing the `else do` block, then a further
   `end` on its own line closing the `if`). I under-counted this three times
   while writing nested nested-match/if bodies in `insert_pattern`,
   `find_all`, `find_first`, and `pattern_at`, each producing "I got stuck
   here" at a later, unrelated declaration (as CLAUDE.md warns for the
   related `else if` chain case) rather than at the actual missing `end`.

## Cross-module opaque-type-annotation gotcha (real, but NOT this module's problem to fix)

`stdlib/array.march` declares its persistent vector as `ptype PVec(a)`, but
every other stdlib module that stores one — `stdlib/rrb_vec.march`'s
`Vec(a) = Vec(Array(a))` and this module's `Automaton(Array(AcNode),
Array(String))` — writes the *field type* as `Array(a)`, which is a
separately-registered compiler builtin generic name
(`lib/typecheck/typecheck.ml`'s `builtin_types`, alongside `List`/`Option`/
`Set`/`Seq`), not literally `PVec`. Running `march --check` on
`stdlib/array.march`-dependent files **in isolation** (single file, no
surrounding program) reports a spurious `expected Array(a) but got PVec(a)`
type error at every `Array.get`/`Array.set`/`Array.push` call site —
reproduced identically on the already-shipped, already-tested
`stdlib/rrb_vec.march` (`march --check stdlib/rrb_vec.march` fails the same
way). A real program that merely *uses* `RRB`/`AhoCorasick` (e.g.
`dune exec march -- some_program.march`, or the actual test drivers) does
not hit this — whatever mechanism resolves the `Array` alias only engages
when the file is loaded as a dependency of something else, not when it is
the direct `--check` target. Net: **`march --check <single stdlib file>` is
not a reliable diagnostic for a file that stores an `Array(a)` — verify
through `scripts/run-tests.sh` or a full program compile instead.** Not filing
a todo for this since it never affects a real build, only a debugging
shortcut; noting it here so the next person hitting the same false-positive
error doesn't waste time on it.

## Tests

`test/stdlib/test_aho_corasick.march` (16 tests, mirrors
`test/stdlib/test_regex.march`'s `describe`/`test`/`assert` structure),
registered in `test/test_stdlib_march.ml` (`"aho_corasick.march"` added to
the file-load list right after `"queue.march"` — `AhoCorasick` is the first
stdlib module to depend on `Queue`, which was not previously in that test
driver's own dependency list at all) and in `lib/modules/stdlib_manifest.ml`
(the list a compiler test asserts is exhaustive over `stdlib/*.march` —
`Stdlib_manifest_test` in `test/test_compiler.ml`).

Coverage: empty pattern list (`build(Nil)`, matches nothing, `find_first`
returns `None`), an empty *string* pattern mixed with a real one (skipped,
doesn't affect the real pattern's matches or the reported `pattern_count`),
single pattern (single and repeated non-overlapping occurrences), no matches,
empty haystack, a pattern longer than the haystack, patterns that are
prefixes of one another (`["a", "ab", "abc"]` against `"abc"` — all three
must fire, at increasing end positions), overlapping matches (the "he"/"she"
inside "ushers" case, plus prefix patterns overlapping at the *same* start
position), and case sensitivity (byte-oriented, no folding).

Matches are compared as 4-tuples (`(start, stop, pattern_index, pattern)`)
rather than via record `==`, sidestepping any question about whether record
structural equality is exercised elsewhere in the suite — tuples definitely
are (`Regex`'s own internal `(match_start, match_end)` pairs).

## Verification

- `./_build/default/test/test_stdlib_march.exe test aho_corasick` — 16/16
  pass (`[OK] aho_corasick 0 AhoCorasick module.`).
- `scripts/run-tests.sh` (full suite, not `-q`) — green; see commit for the
  exact count via a fresh run (`CLAUDE.md`: don't hand-maintain a running
  test count here).

## Not done / left for later

- No benchmark file added under `bench/` comparing N-separate-`index_of`
  scans against one `AhoCorasick` pass. The module doc and this file state
  the asymptotic argument; a benchmark quantifying it on a realistic
  multi-keyword haystack (e.g. a lexer's keyword table) would be a reasonable
  follow-up per `specs/benchmarks.md`'s convention, but wasn't required to
  land this and risked scope creep on a first cut.
- `docs/docs/stdlib/*.html` (the generated per-module API reference site) was
  **not** regenerated — that requires cloning the external `march_doc` tool
  (`scripts/gen-stdlib-docs.sh`, network access) and is normally done as a
  separate maintenance pass (see `dbc57200 docs(stdlib): regenerate API docs
  from stdlib source` for precedent). `docs/stdlib.md` (the hand-written
  tour) and the stdlib-module-count references in `CLAUDE.md`, `README.md`,
  and `docs/stdlib.md` itself (115 → 116) were updated in this commit.
