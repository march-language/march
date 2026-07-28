# Changelog

All notable changes to March are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/); versions follow
[Semantic Versioning](https://semver.org/).

This file starts at the point March adopted a changelog (2026-07-21).
Implementer-level detail on every change — including everything that shipped
before this file existed — lives in `specs/progress.md` and `specs/todos.md`;
git log is authoritative for exact commits.

## [Unreleased]

### Fixed

- **`String.to_uppercase` / `to_lowercase` no longer depend on the process
  locale.** They used C's `tolower`/`toupper`, which are locale-sensitive: under
  a single-byte locale (measured: `en_US.ISO8859-1` on macOS) `tolower` rewrites
  `0xC3`, the lead byte of every 2-byte UTF-8 sequence, silently corrupting the
  encoding. March never calls `setlocale`, but any linked library or embedding
  application can. Behaviour is now fixed regardless of locale, and the same
  change made them **~30× faster** (0.60s → 0.02s on `bench/string_case`).
  Scope is unchanged — ASCII only, non-ASCII bytes pass through untouched.

### Documentation

- `stdlib/string.march` no longer claims the runtime has small-string
  optimisation. It had stated since 2026-03-19 that "strings of 15 bytes or
  fewer are stored inline without a heap allocation"; that was never true — every
  March string is a refcounted heap allocation with a 24-byte header. The header
  now also states plainly that `grapheme_count` counts *codepoints* despite its
  name, with the cases where the two differ.


### Changed

- **`Toml.parse` allocates ~10x fewer strings.** Same character-list-and-append
  pattern as `Json.parse` had, but worse — `Toml.parse` was allocating ~3.7
  heap strings per input byte, against JSON's 2.03 before its own rewrite. It
  is now a byte-index scanner, following the same template: bytes are
  inspected with `string_byte_at` (no allocation), tokens materialised with
  one `string_slice`. On a 340-byte document exercising tables, arrays, an
  inline table, and nested tables, compiled `--opt 2`: **allocs/byte 3.69 →
  0.37** (2,506,057 → 250,044 string allocations over 2,000 parses). Parsing
  is unchanged semantically; `TomlError` column numbers now count bytes
  rather than decoded characters, matching `Json.parse`'s precedent.

- **`Json.parse` allocates ~12x fewer strings and runs ~4.8x faster.** The
  parser used to begin with `string_split(src, "")`, exploding the document
  into one heap string per byte, so its cost scaled with the size of the input
  rather than with the number of strings in it — a 239-byte document holding
  ~20 strings cost 261 allocations per parse, 90% of them 7 bytes or smaller.
  It is now a byte-index scanner that inspects bytes with `string_byte_at` and
  takes one `string_slice` per token: **261 → 21 allocations per parse**, which
  is the number of strings the document actually contains. On a 1MB document
  holding 99,000 strings, one parse went from 1,100,041 string allocations to
  99,018 — allocation now tracks the document's string count rather than its
  byte size. `Json.to_string` got the same treatment (a string needing no
  escaping is now returned as-is, allocating nothing), taking a combined parse
  + serialize round trip from 486 to 58 allocations per iteration and 1.10s to
  0.24s over 20,000 iterations. Parsing is unchanged semantically; the only
  visible difference is that a non-ASCII character in an error message now
  prints correctly instead of as a single mangled byte.

- **String interpolation is ~1.45× faster** and allocates no intermediate list.
  `"a${x}b${y}c"` now desugars to a plain `++` chain at every length, which the
  compiler folds into three-way concats — where it previously switched to a
  `string_join` over a cons list past a size threshold. Measured at seven
  segments over 2M iterations: 519ms → 358ms, with the eight cons cells per
  interpolation dropping to zero.

- **…and interpolating a `String` no longer costs a refcount pair per operand**,
  which closes the rest of that gap. `"a${s}b"` goes through `to_string(s)`,
  which for a String resolves to an identity — but the identity call was only
  removed *after* reference counting had already bracketed it with an atomic
  increment/decrement, leaving the pair stranded around nothing. The call is now
  elided during lowering, so no pair is ever created, and interpolation compiles
  to exactly the same code as the equivalent hand-written `++` chain.
  Allocation counts are unchanged — this was refcount traffic, not allocation.


### Added

- **`string_byte_at(s, i)`** — reads the byte at a byte offset as `0..255`, or
  `-1` when out of range, allocating nothing. Before this, the only ways to
  look at one character of a string from March were `string_split(s, "")` and
  `string_slice(s, i, 1)`, both of which allocate a heap string per character
  inspected — so every hand-written scanner in the stdlib paid an allocation
  per input byte just to decide what the byte was.

- **`String.index_of_from(s, sub, start)`** — substring search from a byte
  offset, returning the index in `s`'s own coordinates so it can be fed
  straight back in when tokenizing. Without it, scanning for successive
  separators means slicing off the tail and searching again, which copies the
  remaining bytes at every step and makes a full tokenize O(n²).

- **`NativeArray.map2_int`/`map2_float`/`to_float_arr`** — a two-array
  zip-with primitive (`f(a_elem, b_elem) = out_elem`, panics on length
  mismatch) and Int→Float widening helper, for numeric ops over two
  `NativeArray`s at once. `DataFrame.col_add_col` (column-column arithmetic)
  now uses these instead of round-tripping through `List.zip`/`List.map`.

- **The docs site gained full-text search on ⌘K / Ctrl-K.** Every page on
  march-lang.org — the guides, the cookbook, and all 114 standard-library API
  pages — is now searchable from one box, opened with `⌘K`, `Ctrl+K`, `/`, or
  the Search button in the nav. Results are grouped by area (Guide, Cookbook,
  Stdlib) and include in-page heading links, so `↵` jumps straight to the
  relevant section rather than the top of the page. The index is built by
  [Pagefind](https://pagefind.app/) as a post-build step over the generated
  site, ships with it, and needs no search service at runtime.

  The same box also does **standard-library symbol lookup**, which previously
  worked only from inside the API reference itself. Typing a function or type
  name (`push`, `to_string`, `List.map`) puts a "Standard library" group above
  the prose results, each entry showing its kind and signature and linking
  directly to the definition's anchor — `Array.html#fn-push` rather than the
  top of the module page. Symbols are matched on name only, exactly or by
  prefix, so multi-word prose queries return prose results alone. The API
  reference pages keep their own `⌘K` for now.

  The index is committed at `docs/pagefind/` because march-lang.org is served
  by GitHub's own Jekyll running over `docs/`, which has no post-build hook —
  the same reason the generated stdlib API pages are committed. A CI check
  fails the build if a docs change lands without a regenerated index, since a
  stale index means the live search silently returns outdated results.

- **Session-type protocols gained a `stop` step to exit a `loop`.** A `loop
  do … end` protocol projects to the recursive µ-type `Rec X. S[X]` and,
  until now, had no way back out — every step inside the body, including
  every `choose` branch, looped back to the start, so a looping channel could
  only be abandoned, never actually `Chan.close`d. Writing `stop` inside a
  `loop` body (directly, or nested in a `choose` branch within one) exits the
  loop instead of repeating it, e.g.:
  ```march
  protocol Stream do
    loop do
      Prod -> Cons : Int
      choose by Cons:
        more -> Cons -> Prod : Bool
        done -> Cons -> Prod : Bool
                stop
      end
    end
  end
  ```
  `stop` is a contextual keyword (a plain identifier everywhere else, not
  reserved). `stop` written outside any `loop`, or steps written after a
  `stop`, are both compile errors.

- **`Bool` and `Float` refinement types are now enforced.** Both previously
  parsed and type-checked while checking nothing at all, so
  `fn needTrue(b : {Bool | _ == true})` accepted `needTrue(false)` and
  `fn sqrtish(x : {Float | _ >= 0.0})` accepted `sqrtish(0.0 -. 1.0)` in
  silence. `Bool` predicates now take the boolean operators against
  `true`/`false` (the bare-binder `{Bool | not _}` remains a parse error — write
  `{Bool | _ == false}`), and `Float` predicates take the comparisons `>= > <=
  < == !=` against float literals or another float value. Preconditions,
  postconditions, path-sensitive guards and postcondition propagation all work
  for both, and float literal arithmetic (`0.0 -. 1.0`) is constant-folded so a
  negative literal is recognised.

  Float obligations are discharged through Z3's **bit-precise IEEE-754
  FloatingPoint theory**, never by modelling floats as reals: over reals
  `not (x >= 0.0) && not (x <= 0.0)` is unsatisfiable, so a reals encoding would
  conclude the predicate can never hold and flag correct code, while over floats
  it is satisfiable (witness: `NaN`) and correctly stays silent. Equality is
  `fp.eq` rather than bitwise `=`, so `{Float | _ != 0.0}` rejects `-0.0` as
  well as `+0.0`. Symbolic float arithmetic in a predicate (`_ +. 1.0 > 0.0`),
  `Float` record fields and special-value predicates (`is_nan`) stay out of
  scope and are silently skipped rather than approximated.

- **Non-empty-collection preconditions, on 13 stdlib functions that panic on an
  empty argument.** `List.head`/`tail`/`last`/`minimum_int`/`maximum_int`, the
  `prelude` `head`/`tail`, `Stats.mean`/`min_val`/`max_val`, `Gen.element`/
  `one_of` and `Random.choice` now declare `{List(a) | len(_) > 0}`, so passing
  a literal empty list is a compile error instead of a runtime abort:
  ```march
  List.head([])       -- refinement violation: `len(_) > 0` cannot hold
  List.head([1, 2])   -- fine
  ```
  Each contract is derived from that function's own panic message, so none is
  stronger than the check the code already performed, and every `panic` remains
  as the runtime backstop for arguments the checker skips. A list whose contents
  the checker cannot see stays **unknown** and is skipped, never guessed. Note
  that an ordinary `List.length(xs) > 0` guard does not yet discharge the
  obligation — the runtime function and the `len` measure are not connected, so
  a guarded call is skipped rather than proved.

### Changed

- **Substring search is much faster.** `index_of`, `index_of_from`, `contains`,
  `split`, `replace` and `replace_all` now use a two-stage `memchr`+`memcmp`
  scan instead of testing every byte offset. Scanning a 1MB buffer for an absent
  needle went from ~809ms to ~21ms in `bench/string_scan` (roughly 0.5 GB/s to
  40 GB/s). `replace_all` additionally bulk-copies the spans between matches
  rather than one byte at a time.

- **Chained string concatenation allocates half as much.** `a ++ b ++ c` and
  longer chains are folded into three-way concats, so k parts cost
  `ceil((k-1)/2)` allocations instead of `k-1` and stop re-copying the growing
  prefix at every link. Measured 20% faster on a short-string building
  benchmark, with 23% less copying. Two-part `a ++ b` is unchanged.

- **`NativeArray.map2_int`/`map2_float` vectorize.** Extended the same
  compiler pass that lets `map_int`/`map_float` compile to real SIMD to also
  recognize `map2`'s two-array call shape — same eligibility bar, same
  boxing-free clone for a concrete-`Float` callback. Measured **~47x** on a
  5M-element benchmark (299 ms → 6.4 ms); previously slower than naive
  interpreted Python for the same operation, now beating hand-written OCaml.
  See `docs/simd-benchmarks.md`.

### Fixed

- **A measure over the refined value only worked under one of its three
  spellings.** In `{List(a) | len(_) > 0}` and `{v : List(a) | len(v) > 0}` the
  refined value reflected to a fresh unconstrained constant rather than to the
  call's actual argument, so the predicate was satisfiable at every call site,
  never a definite failure, and the contract silently checked nothing — while
  the third spelling, naming the parameter (`len(xs) > 0`), worked. Two
  consequences, both silent: the `_` form the documentation teaches gave no
  enforcement at all, and renaming a parameter unenforced a working contract
  with no diagnostic beyond an incidental unused-variable warning. All three
  spellings now resolve against the same actual, as the string and
  axiom-measure paths already did.

- **`Json.parse` rejected JSON numbers with a signed exponent.** `1e-5`,
  `2.5E+10` and `1e-308` all failed with `invalid number: 1e` — the number
  scanner accepted `+`/`-` only in the mantissa position, so it stopped at the
  sign after the exponent marker and handed a truncated `"1e"` to
  `string_to_float`. The scanner now follows RFC 8259's grammar
  (`["-"] int [frac] [exp]`), accepting a sign immediately after `e`/`E`.
  `1-2` still parses as `1` followed by a trailing-character error, as before.

- **`Json.parse` accepted number forms JSON does not allow.** Shape is now
  validated during the scan instead of being left to `string_to_float`
  (`strtod` / `float_of_string`), which is more permissive than JSON: `1.` and
  `01` previously parsed and are now rejected, joining `+1`, `Infinity`,
  `0x10` and `.5`. This is a behavior change for input that was never valid
  JSON — anything conforming to RFC 8259 parses as it did before.

- **A module-qualified constructor pattern could silently never match when
  compiled.** `match Json.parse(s) do Ok(Json.Array(_)) -> ... end` matched
  correctly interpreted but fell through to the catch-all arm in a compiled
  binary — no error, no warning, no crash, just the wrong branch. It affected
  any qualified pattern whose bare constructor name is declared by more than one
  module: in the standard library that is `Array` and `Null` (both
  `Json.JsonValue` and `Msgpack.Value` declare them), so `Json.Array(_)` and
  `Json.Null` were the visible casualties, while `Json.Object(_)` — a name
  unique to `JsonValue` — worked. Codegen identifies constructors by their
  *type* (`JsonValue.Array`), but the documented qualified-pattern syntax writes
  a *module* (`Json.Array`); when the two names differ the qualifier resolved to
  nothing and the pattern fell back to matching on the bare name, which then
  picked whichever module's constructor the compiler happened to enumerate
  first. The qualifier is now translated to its declaring type during lowering,
  so an explicitly qualified pattern resolves to exactly the constructor it
  names.

- **`Json.to_string` crashed on every JSON array and object under `--target js`.**
  It died with `TypeError: f._0 is not a function`, while the same program was
  correct interpreted and compiled native. The cause was not in `json.march`: a
  closure allocated inside a match arm whose scrutinee cell is dead gets
  rewritten by Perceus from `EAlloc` to `EReuse`, and the JS backend's `EReuse`
  and `EStackAlloc` cases were missing the rule `EAlloc` had — a closure's apply
  function lives in slot `_0` and must be emitted as the raw function, not as
  the `name$clo` wrapper *object*. Closure dispatch then did `f._0(f, x)` on a
  record instead of a function. This hit any lambda passed to a user-defined
  higher-order function from a reuse-eligible match arm, so `Json.to_string` was
  the symptom rather than the bug. The three allocation forms now share one
  emitter, so they cannot drift apart again.

- **`String.slice` returned the wrong text on the JS backend.** The JS runtime
  implemented `march_string_slice(s, start, len)` as `s.slice(start, len)`,
  treating the third argument as an END index rather than a LENGTH, so every
  slice with a non-zero start was wrong — `String.slice("abcdefgh", 5, 3)` gave
  `""` on JS against `"fgh"` interpreted and compiled. Negative arguments now
  clamp the way the C runtime clamps, instead of being read as offsets from the
  end of the string.

- **TIR pipeline stages are now inspectable as text.** `MARCH_DUMP_TXT=<stage>`
  prints the pretty-printed TIR at any pipeline checkpoint whose label contains
  the given substring (`all` for every stage). Previously only the very end of
  the pipeline was readable, via `--dump-tir`, which is too late to tell whether
  a pass created a construct or merely preserved one.

- **The SIMD Benchmarks results tables rendered as raw pipe characters.** The
  three tables under "Results" on
  [/docs/simd-benchmarks/](https://march-lang.org/docs/simd-benchmarks/) were
  wrapped in `<div style="overflow-x:auto">`. Kramdown does not parse markdown
  inside a raw HTML block unless the element carries `markdown="1"`, so each
  table was emitted verbatim as text. The wrapper was also redundant — the docs
  layout already sets `display:block; overflow-x:auto` on content tables, which
  is why the same page's other two tables were fine — so it is simply removed.

- **Discarding a container no longer leaks its contents.** March reclaimed an
  aggregate only by *destructuring* it; releasing one that was never pattern-
  matched freed the top cell alone and orphaned everything under it. This hit
  the ordinary way to consume a `String.split` result — passing it to a
  function that borrows it — so bulk text processing leaked in proportion to
  its input (a 60-iteration split/consume loop peaked at 585 MB, growing
  linearly; it now holds flat at 16 MB). It was never about how the container
  was traversed: a consumer that ignored its list argument entirely leaked
  just the same. Compiled targets only — the interpreter was unaffected.
  `bench/binary_trees.march` drops from 157 MB to 6 MB peak as a result.
- **A tail-recursive `Cons(_, t)` walk no longer strands a reference on every
  cell.** The self-TCO back-edge skipped *every* refcount op on a forwarded
  argument, to fix a use-after-free on a freshly allocated one. A list walk's
  tail is not freshly allocated — it is dup'd from the matched cell, and that
  dup's matching release was being skipped, leaving each cons cell pinned.

- **`DataFrame.eval_agg`'s `Min`/`Max`/`Std`/`Variance` no longer materialize
  a boxed `List(Float)` per call.** These aggregates previously converted the
  column's `NativeArray` into a linked list before folding over it, an O(n)
  allocation on top of the O(n) reduction that showed up as tens of
  milliseconds per call on large columns regardless of which aggregate ran.
  They now use dedicated native-array reduction builtins (mirroring `Sum`),
  bringing them roughly in line with the already-fast `Sum`/`Mean` path —
  60-80x faster at 500K rows in local measurement. `Median` still sorts and
  is unaffected by this fix.

- **Compiled string literals no longer leak once per evaluation.** A literal
  used as a direct operand — most commonly `acc ++ ", "` or `s ++ "\n"` inside
  a loop — allocated a fresh string every time it was evaluated, and nothing
  ever freed it, so ordinary string-building loops grew memory without bound
  (a 2M-iteration concat peaked at 64MB of RSS against 2.9MB for the same loop
  with both operands bound to variables). Each literal now allocates one shared
  string for the whole program, matching how the compiler's ownership analysis
  has always treated literals: as constants that no binding owns. Only the
  compiled backend was affected; the interpreter was always correct.
- **A bare `Bool` variable used as a guard no longer produces a malformed
  solver query.** `if j do … end` around a refined call reflected `j` as an
  integer constant and asserted it as a formula, which z3 rejects; the
  obligation was then silently undecidable. Such a variable is now declared at
  the `Bool` sort, and a Boolean-position well-sortedness guard drops anything
  that still is not a formula rather than emitting it.

- **The compiled-binary cache no longer serves a stale binary after a
  `runtime/*.c` edit.** The CAS key digested a runtime directory it resolved
  itself, searching the current directory *first*, while the compiler picks the
  sources it hands to clang exe-relative *first* ("independent of CWD"). Run
  from the repo root against `_build/default/bin/main.exe`, those are two
  different directories, so the key could be identical (or differ for reasons
  unrelated to what was built) while the compiled output differed — a runtime
  edit could print `compiled <out> (cached)` for a binary containing none of
  the new code. The driver now resolves the runtime directory once and
  registers it with the CAS, so the key always digests the sources actually
  compiled; `MARCH_RUNTIME_DIR` overrides the search, mirroring `MARCH_STDLIB`.
- **`MARCH_STRING_STATS=1`** — an opt-in profiling mode for compiled binaries.
  Set the environment variable and the program prints string-allocation
  statistics to stderr at exit: allocation count and bytes, a size histogram,
  bytes copied, frees, peak live bytes, and non-string heap allocations. Off by
  default and measured at −0.34% overhead when off. Intended for answering
  "where is this program's string cost going?" without a profiler.

- **String benchmark suite** — six benchmarks in `bench/` (`string_scan`,
  `string_case`, `string_split_large`, `string_slice_walk`,
  `string_small_churn`, `string_parallel_scan`), each isolating one cost, run
  by `bash bench/run_string_bench.sh` into `bench/STRING_RESULTS.md`. Documented
  in `specs/benchmarks.md`; findings in
  `specs/2026-07-26-string-performance-profile.md`.

### Changed

- String interpolation with many parts (`"${a}${b}${c}${d}"`) now desugars to
  a single `string_join` call over all parts instead of a left-deep chain of
  `++`, which re-copied the growing prefix on every append. This makes a
  k-part interpolation O(n) instead of O(k²) in total bytes copied, with no
  change in the resulting string value. Short interpolations (up to three
  segments, e.g. `"count: ${n}"`) keep the `++` chain, which measures faster
  at that size than materializing a list to join.
- Compiled `NativeArray.map_float` with a plain, concretely-typed
  callback (`fn x -> x *. 2.0 +. 1.0`, a captured scalar, or similar — no
  generic/unresolved types involved) no longer allocates at all for each
  element crossing the callback boundary, and the resulting loop can
  actually be vectorized by the backend compiler on suitable inputs. A
  callback whose type isn't fully known at this point still allocates one
  reusable cell per call (an earlier improvement over one per element) and
  is unaffected by this change. No observable behavior change either way.

- Compiled `NativeArray.map_float` now allocates one boxed-float cell per
  call and reuses it across all elements, instead of one per element. Cuts
  allocation traffic and GC pressure substantially for large arrays (a
  stress-test benchmark measured roughly 2x less wall-clock time); no
  observable behavior change.

- Native and WASM LLVM output now describes `march_alloc` as a fresh,
  non-null allocation whose argument is its allocation size, and marks
  generated closure ABI trampolines `alwaysinline`. This gives LLVM useful
  alias and call-boundary facts without changing TIR or ownership semantics.

- The TIR optimizer inlines a private top-level function's body at its call
  site when that function has exactly one direct, arity-correct reference
  anywhere in the module, even when the body is not pure. Ordinary pure-only
  inlining, the 50-node size limit, DCE-root/address-taken/hot-code-reload
  exclusions, and recursive-SCC detection (extended to cover bare/qualified
  name aliasing) all still apply; Perceus RC operations and their order are
  preserved unchanged. No runtime speedup was measured — this is a
  definition/call-site reduction in emitted LLVM, not a benchmarked
  optimization.

### Added

- **Refinement Tier 2: structural induction over recursive functions.** A
  relational postcondition on a structurally recursive function —
  `fn insert(t : Tree, x : Int) : {Tree | size(_) == size(t) + 1}` — is now
  *proven* at its definition and therefore propagates to call sites, instead of
  being silently skipped. Z3 still does no induction; the checker supplies the
  **induction hypothesis** at each self-recursive call whose argument is a
  proper component of the matched parameter, then discharges each `match` arm
  against the `@[measure]`'s recursion equations. Relational and closed
  predicates over a variant-ADT return both work, recursion may descend into
  any recursive component, and a growing accumulator parameter is fine.
  Unchanged and still silent: mutual recursion, the built-in `len` (declare a
  user `@[measure]` instead), a recursive call inside a lambda or behind a
  nested `match`, and any non-structural recursion — the hypothesis is gated by
  the same `structural_subvars` test that makes `@[measure]` axiomatisation
  sound, because an unsound hypothesis would manufacture false positives rather
  than merely fail to help. `Int`-returning postconditions are untouched. See
  `specs/lang/refinement-types.md` for the exact frontier, including the three
  stacked obstacles that still separate this from the stdlib HAMT.

- **Two higher-order refinement checks.** A call made *through* a refined
  function-typed parameter — `fn ap(f : ({Int | _ >= 0}) -> Int) : Int do
  f(-3) end` — is now rejected, and so is a call through a **local alias** of
  a named refined function — `let g = takepos  g(-3)`. Both previously fell
  through the checker's named-callee-only call resolution and were silently
  skipped. Single-argument callback types only; a callback parameter whose
  own declared type is unrefined is unaffected — see
  `specs/lang/refinement-types.md`'s Limitations section for the exact
  boundary.

- A **guard on a record field** now reaches the refinement checker. `if
  c.port >= 1 do serve(c)` discharges a `{v : Config | v.port >= 1}`
  precondition, and the contradictory `if c.port <= 0 do serve(c)` is reported
  as a definite failure. The variable needs no refinement of its own — a plain
  `c : Config` parameter works, since an unrefined record is modelled as an
  unconstrained value that the guard then decides. With no guard the call is
  still skipped. Field facts obey the same rebinding rule as tag and scalar
  facts: a `let`, `let?`, lambda parameter or `match` binder that rebinds the
  name retires the fact.

- An **unreflectable record field no longer hides its siblings** at a call
  site. `serve({ port: 0, name: n })` and `serve({ port: 0, history:
  Cons(1, Nil) })` used to be skipped whole, because a `String` field bound to a
  variable and a list literal with concrete elements cannot be placed at their
  declared SMT sorts. The offending field is now replaced by an unconstrained
  stand-in of the right sort, so `port` is checked and both calls are reported.
  Nothing may be concluded *about* the stand-in in either direction, and the
  return side keeps the conservative whole-record skip.

- Refinement checking now propagates **relational** return refinements — those
  that mention a parameter — by substituting the call's arguments for the
  callee's parameters. Given `fn below(n : Int) : {Int | _ < n}`, the call
  `takepos(below(0))` is a compile error because `_ < 0` can never satisfy
  `_ >= 0`, while `takepos(below(10))` stays silent. Arguments are matched
  positionally and substituted simultaneously, so `f(m, 1)` against
  `{Int | _ < n + m}` yields `_ < m + 1`, not `_ < 1 + 1`. As before, only a
  postcondition the definition side actually *proved* propagates, and
  instantiation is skipped entirely rather than done partially when an argument
  is missing, the predicate mentions an unknown name, or the callee takes a
  pattern parameter — correct code is still never flagged.

- As-patterns: `Some(x) as whole -> ...` binds a name to the entire matched
  value while the inner pattern continues to destructure it. Works in match
  arms, `let` bindings, and function parameters. `PatAs` had been implemented
  in the AST, interpreter, and typechecker since the beginning but had no
  grammar production.

- Record patterns: `match r do { x, y: b } -> ... end`, `let { x, y } = r`, and
  `fn area({ w, h })`. `{ x }` is shorthand for `{ x: x }`. `PatRecord` had
  existed in the AST and interpreter since the beginning but had no grammar
  production, and neither TIR lowering path handled it.

- Record patterns now take part in exhaustiveness and redundancy analysis.
  A match that handles only some values of a field — `match p do { code: 404 }
  -> ... end` — is reported non-exhaustive instead of typechecking clean and
  panicking at runtime, and a record arm already covered by an earlier one is
  reported unreachable. Previously the checker's internal pattern shape had no
  record case, so any arm containing a record pattern read as a wildcard.

- Record patterns nested inside a constructor payload may name a subset of the
  record's fields: `Some({ status: s })` against an `Option` of a two-field
  record now typechecks. The constructor's argument types were only linked to
  the scrutinee's payload *after* its sub-patterns were inferred, so a nested
  record pattern saw an unresolved type variable and fell back to requiring
  every field. The full-field form happened to unify anyway, which is why this
  went unnoticed.

- Record patterns in `let` and `let?` bindings may also name a subset of the
  record's fields — `let { code: c } = p` no longer requires naming every
  field of `p`. The binding's right-hand side supplies the expected type; it
  simply wasn't being passed to the pattern. Naming a field the record lacks
  now gives the same `unknown_record_field` error the `match` path gives,
  instead of a unification mismatch that leaked an internal type-variable
  name. A bare record pattern used directly as a function parameter stays
  closed — that position has no annotation to source a type from.

- Record patterns may mention a subset of a record's fields: `{ code: 404 }`
  matches any record with a `code` field equal to 404, whatever else it has.
  Naming a field the record does not have is a compile error.

- Or-patterns: `1 | 2 | 3 -> "small"` matches an arm against several
  alternatives. Alternatives may bind variables, provided every alternative
  binds the same names at the same types (`A(x) | B(x) -> x * 10`); they share
  one arm body which reaches those names as parameters, so `A(x) | B(y)` and a
  name bound at two different types are both compile errors. Exhaustiveness
  and redundancy checking see through or-patterns at any nesting depth.

- A refinement over a **record's fields** is now checked on **parameters**, not
  just return types. Given `fn serve(c : {v : Config | v.port >= 1})`, the call
  `serve({ port: 0 })` is a compile error. A record literal argument is a fact
  (fields are matched by name, so declaration order doesn't matter), and a
  variable holding a record-refined parameter carries its fields through, so
  forwarding to a same-shaped parameter verifies. An unrefined record, a record
  literal with an unknown field value, or a field outside the reflected
  fragment is skipped rather than guessed at — the definite-failure stance is
  unchanged, and correct code is never flagged.

- Refinement types now support `String`. `len` measures a String as well as a
  list, so `{String | len(_) > 0}` and `{String | _ != ""}` are checkable
  contracts and passing an empty string literal to a non-empty parameter is a
  compile error. `len` counts bytes, matching the `string_length` builtin.
  Which `len` applies is decided by the value's declared base type, so list and
  String uses coexist unambiguously. The encoding models `String` as an opaque
  sort and deliberately avoids SMT string theory, so there is no prefix/suffix/
  contains/regex reasoning, and an `s == ""` guard does not establish a length
  in the else-branch — see `specs/lang/refinement-types.md` for the full limits.

- Refinement checking now propagates a function's declared return refinement to
  its call sites, so passing a `{Int | _ < 0}` result into a `{Int | _ >= 0}`
  parameter is a compile error. Applies to both `takepos(neg())` and
  `let c = neg()` forms, and resolves across modules via `alias`/`use`.
  Only postconditions the definition side actually *proved* propagate — an
  unproven one stays legal but tells callers nothing, so a stale return
  refinement can never flag correct code. Postconditions that mention a
  parameter (relational) are not yet propagated.
- Refinement predicates can now constrain an ADT's **constructor tag**. Every
  constructor of every type — including the built-in `Option`, `Result` and
  `List` — gains an implicit `is_<Ctor>` tester, so `fn unwrap(o : {Option(Int)
  | is_Some(_)})` is a checkable contract: `unwrap(None)` is a compile error,
  and so is `unwrap(x)` written inside a `None ->` match arm, where the arm
  narrows the scrutinee's tag. Testers are exact-case (`is_some` is not
  `is_Some`). Narrowing is skipped for a non-variable scrutinee, for an `as`
  pattern, for an arm that rebinds the scrutinee's name, and for a constructor
  name shared by two ADTs — in each case the checker stays silent rather than
  guessing. A fact is recorded against a *name*, so any inner `let`, `let?`,
  lambda parameter or nested `match` binder that rebinds that name retires it.
- Refinement predicates that call an unknown function now produce a warning
  instead of being silently ignored. `{Int | totally_bogus_fn(_) > 0}` compiled
  clean and enforced nothing; it now says so. The supported vocabulary is the
  comparison/arithmetic/boolean operators, `len`, and `@[measure]` functions.

### Fixed

- `DataFrame`'s `Sum`/`Mean` aggregations (compiled builds) now compute
  directly over the column's underlying array instead of first converting
  the whole column to a list. Purely a missed-optimization fix — same
  results, less work per call. `Min`/`Max`/`Std`/`Variance`/`Median` are
  unaffected (no equivalent fast path yet).

- **Compiled `NativeArray.map_int`/`map_float` now inlines closures that
  capture a variable**, not just plain `fn x -> ...` lambdas — e.g.
  `fn x -> x +. f` or `fn x -> x *. f`, the exact shape
  `DataFrame`'s `col +. scalar` / `col *. scalar` use. Previously any
  captured variable disqualified the closure from the Phase 2 (P10)
  inlining optimization entirely, so this was a real, already-shipping
  workload getting none of the benefit. Purely a missed-optimization fix;
  behavior was already correct, just slower than it should have been.
- **Refinement checker no longer flags correct code when a local reuses a
  refined function's name.** A `let`, `let?`, lambda parameter, local-`fn`
  name or parameter, `match` arm binder, or function parameter that happened
  to share a name with a module-level refined function had its calls checked
  against that function's precondition — even though the local is what
  actually runs. `let takepos = fn n -> n` followed by `takepos(-3)` reported
  a bogus violation. Callee resolution now obeys the same shadow discipline as
  every other fact channel: a name an enclosing binder introduced never
  resolves to a global function.

- **`{T | size(_) < 0}` is now checked, like its named form `{v : T | size(v)
  < 0}`.** The anonymous binder — the spelling the reference teaches — was
  emitted verbatim as an SMT symbol when it appeared inside a measure
  application. `_` is a reserved SMT-LIB token, so the solver rejected the
  query and the predicate was silently never decided: the documented idiom
  checked nothing while the named spelling worked. Both spellings now reflect
  to one canonical symbol and produce identical verdicts.

- **Compiled `NativeArray.map_int`/`map_float` now inlines even when the
  mapped array is reused afterward.** The Phase 2 closure-inlining
  optimization (P10) silently never fired whenever code used the array
  again after mapping it — e.g. a self-recursive loop that maps `arr` and
  then passes `arr` on to its own tail call — because an unrelated Perceus
  reference-count operation sitting between the closure allocation and its
  alias binding made the pass bail out and fall back to the slower,
  unoptimized closure-call path. That "map an array you're about to use
  again" shape is extremely common, so this covered the large majority of
  real `map` call sites. Purely a missed-optimization fix; behavior was
  already correct, just slower than it should have been.

- `march --compile` no longer fails with "cannot find runtime/march_runtime.c"
  when invoked from a working directory other than the project root. Six
  independent lookups for files under `runtime/` were each missing an
  exe-relative candidate that resolves the actual dune build layout, so any
  invocation outside the repo root (or a `_build/default/bin/main.exe` build)
  fell through to a dead CWD-relative fallback.

- **The compiled-artifact cache could return a different program's binary.**
  It stored the *path* the compiler wrote to rather than the binary itself, so
  nothing owned that file. Compiling one program, then another to the same
  `-o` path, then the first again to a new path served the second program's
  binary — reported as `(cached)`, with no error:

      march --compile a.march -o /tmp/x    # cached: key(a) -> "/tmp/x"  (AAA)
      march --compile b.march -o /tmp/x    # cached: key(b) -> "/tmp/x"  (BBB)
      march --compile a.march -o /tmp/y    # -> BBB

  Reusing one `-o` across several sources is ordinary in build scripts and
  test harnesses, so this was reachable in normal use. Artifacts are now
  copied into the cache by content and served from there; deleting or
  overwriting a compiled output can no longer affect what the cache returns.
  Cache entries live in a new directory, so stale entries from the old scheme
  are ignored rather than misread.

- Refinement checking: a **named return binder** that collides with a parameter
  no longer misattributes the guards reaching a return. `fn f(v : Int, k : Int)
  : {v : Int | v > 0} do if v < 0 do k else 1 end end` was reported as a
  violation with the counterexample `k = -1` — the guard `v < 0` is about the
  *parameter*, but the path conditions were translated with the resolver in
  which `v` denotes the *return value*, so it became `k < 0`. Path conditions
  now resolve in the function body's namespace; only the return predicate reads
  the binder as the return value. The same conflation also suppressed genuine
  violations, which are now reported.

- `NativeArray.map_float` (compiled builds) no longer segfaults, and
  `NativeArray.map_int` (compiled builds) no longer silently returns wrong
  results. Both called a closure through the wrong calling convention — a
  native `int64_t`/`double` C signature instead of the tagged/boxed `ptr` ABI
  every March closure actually uses. Floats landed in the wrong CPU register
  class entirely (crash); ints happened to land in the right register but
  skipped the tag/untag step (wrong answer for every element).

- `NativeArray.sum_float` (compiled builds) now vectorizes. Strict IEEE 754
  float semantics were silently blocking clang's auto-vectorizer on this
  reduction loop — it emitted vector loads but scalar adds. Scoping float
  reassociation to just this loop (not a program-wide `-ffast-math`) restores
  SIMD summation; results match prior output to the last bit of rounding,
  roughly 3x less CPU time on large arrays.

- **`String.from_codepoint` and `String.to_codepoints` now work in compiled
  programs.** They were interpreter-only builtin wrappers — the underlying
  `string_from_codepoint`/`string_to_codepoints` have no native
  implementation — so *any* compiled program calling them failed at link time
  with `Undefined symbols: _string_from_codepoint`. Both are now pure-March
  UTF-8 codecs built on `Bytes` and the integer bitwise builtins: one
  definition for every backend, with no interpreter-vs-compiled divergence.
  Encoding rejects negative values, values above U+10FFFF, and UTF-16
  surrogates.

- **`IOList.to_string`/`byte_size`/`is_empty` no longer overflow the stack on
  deep segment trees.** All three walked the tree with non-tail recursion, so
  a deque of appends — `IOList.append(acc, x)` in a loop builds a left spine
  one level deeper per append — crashed with SIGBUS past roughly 15–20k
  depth, despite the module documenting flattening as stack-safe. Rewritten
  as tail-recursive explicit-worklist traversals that keep the frame stack on
  the heap, so depth and branching are bounded only by memory.
  `bench/iolist_template.march` and `bench/string_pipeline.march` both crashed
  on this and now run clean.

- **A `Deque` element popped in compiled code came back as a garbage
  pointer.** `deque.march` was missing from the compiler's eagerly-loaded
  stdlib list, so it loaded lazily — signatures only, no body typecheck. That
  left callers' bindings as unresolved type variables, monomorphization could
  not specialize the generic `pop_front : Deque(a) -> (Option(a), Deque(a))`,
  and the generic body's *boxed* `Some` was decoded by the concrete caller as
  a *niche* `Option(Int)` — yielding the box's heap address instead of the
  value. `bench/deque_ops.march` printed a pointer and then looped forever
  draining a deque whose elements never matched. Fixed by loading `Deque`
  eagerly; the underlying hazard — lazy loading changing representation
  decisions — is tracked separately.

- `NativeArray.map_int`/`map_float` (compiled builds) no longer allocate a
  closure or call it indirectly when the mapped function is a plain,
  non-capturing `fn x -> ...`: the compiler now calls it directly, which
  clang can then inline and, for arithmetic-heavy element functions,
  vectorize. A capturing closure is unaffected. Workloads whose map step is
  dominated by array read/write bandwidth (the common case) won't see a
  wall-clock difference — the win is in the per-element compute cost.

- `typed_array_map`/`typed_array_fold` (compiled builds) no longer segfault.
  `call_closure_1`/`call_closure_2` read a closure's function pointer at byte
  offset +8 of the closure object — the object's `tag` field (plus 4 bytes of
  padding), not the fn pointer, which actually lives at offset +16. This broke
  every DataFrame boolean-column negation/is-not-null check compiled (e.g.
  `typed_array_map(data, fn b -> !b)` in `stdlib/dataframe.march`). New
  regression test `test/native/typed_array_map_closure_abi.march`.
- Session types: steps that follow a `choose ... end` block are no longer
  dropped from every role's projection. Both roles previously lost the
  protocol's tail consistently enough that duality still passed and the
  trailing message went silently unenforced; in multi-party protocols a
  legal choice-then-message protocol could even be rejected with a spurious
  role-mismatch error. A program that closes a session channel instead of
  driving the post-choice steps is now correctly rejected.

- Session types: `loop do ... end` protocols now genuinely loop. The
  projection previously substituted the post-loop continuation into the
  recursion point, so a `loop` was silently one unrolled iteration — a
  second send/recv round was rejected with `` channel is at `End` ``. `loop`
  now projects to the standard recursive µ-type, so a channel may run the
  loop body any number of times. Since such a loop never exits, a protocol
  step written after a `loop` block is now a compile error instead of
  unreachable, silently-accepted dead code.

- Session types: `Chan.new` on a protocol with more than two roles is now a
  compile error instead of silently handing back the first two roles'
  (non-dual) endpoints as a pair. `Chan.new` is the binary-only channel
  constructor; `MPST.new` already existed for 3+-role protocols but nothing
  stopped `Chan.new` from being called on one too. The error names the
  protocol's actual role count and points at `MPST.new`.

- **Session types: an unrefined `Chan.offer` continuation is no longer a live
  soundness hole.** `match`-ing the label `Chan.offer` returns already refined
  the paired channel's type per arm, but only when such a `match` existed —
  driving the channel without one still typed it at the FIRST branch's
  continuation, an unsound guess whenever the branches continue differently.
  Interpreted, that guess could die with a dynamic type error; **compiled, it
  was silent type confusion** — a peer that chose the other branch and sent a
  `String` had that value's heap pointer read as an `Int`. A `Chan.offer`
  whose branches continue identically is unaffected and still needs no
  `match` to drive. `specs/lang/types/accept/t43_choose_offer_roundtrip.march`
  and `specs/lang/golden/g39_chan_choose_offer.march`, both of which relied on
  the old guess, are migrated to match on the label first (`g39`'s printed
  output is unchanged).

- **Session types: the `Chan.offer` fix above was also bypassable by
  unification** — an ordinary type annotation was enough. The compiler marks
  the exact channel `Chan.offer` hands back and rejects operations on it by
  identity, but unifying two channel types only compared their protocol
  states, never linked them. So `let ch : Chan(Role, Proto) = offered` — or an
  `if`/`match` join with another channel, a record field, or passing the
  channel to a function with an annotated parameter — produced a *different*,
  unmarked channel at the same state, and every later check passed. The
  annotation form typechecked clean and, compiled, printed the other branch's
  `String` payload as an `Int`. Unifying an unrefined `Chan.offer`
  continuation with any other channel type is now itself an error; only a
  `match` on the paired label can make the channel usable. Reported at the
  unification rather than propagating the mark, so the function-parameter form
  is caught at the call site, where the mistake is.

- **Lambda and nested-`fn` parameter type annotations are now enforced.** A
  parameter annotation on a `fn ... -> ...` lambda — or on a named `fn`
  declared inside a function body — was checked against nothing at all: the
  lambda's function type was built from fresh type variables that were never
  reconciled with the annotations, so the body was checked against the
  annotation while every call site checked its argument against the unrelated
  variable. `fn (x : String) -> ...` applied to `42` typechecked. For session
  types this was the last soundness hole *found* in the `Chan.offer` fixes
  above (the enforced routes are enumerated, not proved — see
  `specs/lang/session-types.md`):
  passing an unrefined continuation to `fn (c : Chan(Role, Proto)) -> ...`
  reached neither the per-operation check nor the unification check, and the
  compiled program read one branch's `String` payload as the other's `Int`.
  Both are now rejected. Top-level `fn` parameters were never affected. If
  this newly rejects code you had, the annotation and the actual argument type
  genuinely disagree — the annotation was simply not being checked before.

- **Session types: the `Chan.offer` fix above was itself bypassable by
  shadowing the offer's label variable.** Rebinding the label name
  (`let lbl = :ok`) after `let (lbl, ch) = Chan.offer(...)` left the OLD
  name→channel linkage reachable, so `match`-ing the shadowed name still
  refined (and un-marked) the original channel as if the peer had returned
  that label — reopening the identical type-confusion hole through a
  shadowed name instead of a missing `match`. Rebinding a name — via a plain
  `let`, a lambda/`fn` parameter, or a `match` pattern — now always retires
  any stale linkage for that name first.

- **Session types: `match`-ing the label `Chan.offer` returns now checks
  exhaustiveness against the protocol's actual branches, not the open `Atom`
  universe.** A `match` handling every branch the peer could choose used to
  warn `` missing case: _ `` anyway (`Atom` is open, so the checker could
  never see the label as fully covered) — and a `match` that genuinely
  omitted a branch produced the exact same warning, never an error. The one
  signal meant to catch "you forgot a protocol branch" was indistinguishable
  noise either way. Covering every branch (with or without a catch-all) is
  now silent; a missing branch with no catch-all is a compile error naming
  the branch. A `match` arm naming a label the protocol does *not* offer
  (`:okk` alongside `:ok`) used to be accepted in silence and could never be
  taken; it is now a warning naming the unknown label and the valid set —
  a warning, not an error, since a redundant arm is dead code rather than a
  soundness problem.

- Session types: driving an unrefined `Chan.offer` channel from inside a `_`
  catch-all arm no longer advises "Match on the label first", which read as
  plainly wrong to anyone who had just written a `match`. The message now
  explains the real problem: a catch-all does not identify which branch the
  peer chose, so every label needs its own arm.

- Session types: a `choose` branch that ends in a `loop` is now rejected when
  the protocol continues after the `choose`. Those trailing steps are
  projected into every branch, so in a branch that loops forever they can
  never run — the same unreachable-step defect already rejected when the
  steps are written directly after a `loop`, but reached through the
  post-`choose` tail instead.

- Session types: a protocol role that isn't also a declared type or actor no
  longer produces a "not a known actor or type" hint. Roles are their own
  namespace, so the hint was wrong by construction — it fired on the
  reference chapter's own `Echo` example, and the conformance corpus worked
  around it by declaring dummy `type` aliases for every role. Separately,
  `MPST.choose`/`MPST.offer` (multi-party branching, not yet implemented) no
  longer fall through to a misleading `` Unknown module `MPST` `` error;
  the diagnostic now names the real problem and lists the supported
  `Chan.*`/`MPST.*` operations.

- Refinement verdicts of `unknown` are no longer cached. An `unknown` is the
  absence of an answer, not an answer: the solver runs under a wall-clock
  timeout, so a loaded machine could turn a decidable check into `unknown` and
  the cache would freeze that accident into every later build. A malformed
  query also yields `unknown`, so caching one made a compiler bug's
  silently-unchecked result outlive the fix for that bug — which is how a warm
  cache masked two refinement regression tests. Caches written before this
  change self-heal, and real verdicts are still cached.

- **The `task_await` missed-wakeup deadlock is fixed** — fork-join workloads
  (`task_spawn` + `task_await`) hung roughly once every 20 runs, and the same
  race intermittently hung CI's test step. It was a memory-ordering bug, not a
  logic bug: the waiter's register-then-recheck and the completer's
  publish-then-read-waiter form a classic store-buffering (Dekker) pair, and
  release/acquire ordering does not prevent a store from being reordered after
  a later load of a different address. On Apple Silicon the compiler emits an
  RCpc acquire load (`ldapr`) that may complete before an earlier release
  store drains, so both sides could read stale values at once: the task
  completed, the completer saw no registered waiter and woke nobody, and the
  waiter — having read a stale "not done" — parked forever. Upgraded both
  sides of the pair to sequentially-consistent ordering (24 hangs/500 runs →
  1/1000), and closed the residual window — a wake arriving after the
  waiter's final recheck but before it finishes parking was dropped — with a
  wake-permit handshake in the scheduler (0 hangs/3000 runs). The
  `task_burst_await` regression test is back in the default test suite after
  being quarantined as un-runnably flaky; actor mailbox delivery never had
  either bug (its check-and-park runs under the mailbox lock).

- A single malformed verification condition no longer disables refinement
  checking for the rest of a compilation. z3 emits an `(error …)` line and then
  still answers the query, but that line was read as the verdict; the solver was
  killed, respawned, hit the same error, and z3 was then marked unavailable for
  the whole run — so every later call site was silently left unchecked with no
  diagnostic. Error lines are now skipped, and a query that produced one is
  reported as unproven rather than trusted.

- **A z3 error message spanning more than one line no longer shifts every later
  verdict by one.** The fix above skipped a single `(error …)` *line*, but a
  sort mismatch prints the offending term and then a second line naming the
  declaration it violates; the continuation stayed in the pipe and was consumed
  as the *next* query's answer. Under the definite-failure stance that is worse
  than an unchecked call — a later, unrelated, **correct** call inherits some
  other query's `unsat` and is reported as a violation. The whole error
  s-expression is now consumed, counting parens only outside its quoted
  message.

- **A record argument holding a list literal with concrete elements is now
  skipped instead of building a malformed query.** `{ history: Cons(1, Nil) }`
  puts a well-sorted `List` constructor at a `List` field, but the built-in
  `List` is generic so its element sort is opaque, and the integer `1` does not
  fit there. The field sort-check only looked at the top-level term, so the
  mismatch reached z3 — the exact multi-line error above. The check now
  recurses into a constructor's arguments.

- **A refinement path fact survived a rebinding of the name it was about**, so
  correct code could be flagged. After `if x < 0 do`, a `let x = 5` inside the
  branch left `x < 0` attached to the *new* `x`, and a call needing `{Int | _ >=
  0}` was reported as a definite violation. Facts are now retired by every
  binding construct that rebinds a name they mention — `let`, `let?`, lambda and
  local-`fn` parameters, and `match` arm binders — in both the call-site and the
  return-position checks.

- **Scalar tagging now carries `nsw`, letting LLVM fold the tag/untag round
  trip away entirely.** The `(v << 1) | 1` immediate-scalar tag was emitted
  as a plain `shl`, so LLVM could not assume the shift preserved the sign and
  a sign-truncating `sbfx` survived on every scalar round trip — and, worse,
  that residue blocked accumulator tail-recursion elimination on recursive
  functions whose result feeds the tag. With `shl nsw` (asserting exactly the
  63-bit-losslessness the tagging convention already assumes), `fib(40)`
  compiles to an accumulator loop with a single recursive call — with the
  preemption check still inside the loop — and drops from 465 ms to ~390 ms.
  Trade-off, made deliberately: an `Int` outside [-2^62, 2^62) passed through
  a generic/erased slot was *already* silently corrupted by the round trip;
  under `nsw` that same out-of-convention value is poison rather than a
  deterministic wrong value. The full differential-oracle sweep (141
  programs) is unchanged: 100 MATCH, 0 divergences.

- **Compiled code no longer pays a thread-local-storage resolver call on every
  function entry.** Each compiled function began by loading, decrementing and
  storing the `_Thread_local` scheduler reduction counter. Thread-local access
  is not a plain load on either supported platform: on Darwin/arm64 the symbol
  is a TLV descriptor and each access compiles to `adrp; ldr; blr` — an
  indirect call into the resolver — and on Linux/arm64 PIE it goes through a
  TLSDESC call. A non-inlinable call on every entry also forces a stack frame
  and register spills. Compiled code now reads a plain (non-thread-local)
  `march_preempt_request` flag instead, which the preemption handler sets once
  per quantum; the hot path is a single load and a predictable branch, and it
  is read-only, so the cache line stays shared across scheduler threads rather
  than ping-ponging on a per-call store.

  `fib(40)` 640 ms → 465 ms, `tree-transform` 852 ms → 579 ms, `binary-trees`
  177 ms → 165 ms. Preemption latency is unchanged in wall-clock terms (still
  driven by the 1 ms quantum); what is gone is the *count*-based trigger that
  also fired every 4000 calls, which on call-dense code fired within
  microseconds — far more often than the quantum required, for no benefit.
  Because the flag is process-wide rather than per-thread, a given scheduler
  thread is now preempted on average every (threads × quantum) rather than
  every quantum.

- **`MARCH_NUM_SCHEDULERS=1` had no timer preemption at all.**
  `march_sched_run`'s single-scheduler fast path returned without ever
  starting the preemption daemon, so in the configuration used for
  deterministic, race-free runs the *only* thing that ever preempted a
  CPU-bound green thread was the per-call reduction counter. A tail-recursive
  loop could otherwise monopolise the scheduler indefinitely. The daemon is
  now started (and stopped) on that path too. Found by a new starvation test
  that runs a CPU-bound task alongside a short one on a single scheduler
  thread — the only configuration in which such a test measures preemption
  rather than parallelism.

- **Perceus FBIP in-place reuse was silently disabled program-wide**, making
  every "functional but in-place" rewrite a heap free + fresh allocation
  instead. `bench/tree_transform.march` (the FBIP showcase) ran at 3842 ms
  against 513 ms in the last published benchmark table, and
  `bench/list_ops.march` at 143 ms against 68 ms.

  Cause: once `join_points` began lifting a `match`'s panic default arm into
  a `$jp_clo` closure, every real arm carried a `dec_rc $jp_clo` between its
  `let` chain and its tail allocation. `try_fbip_sink` only traversed `ELet`
  nodes, so the scrutinee's own `dec_rc` could never reach the allocation and
  no `EReuse` was ever produced. `try_fbip_sink` now also hops `ESeq` heads
  that are RC operations on a *different* variable — sound because RC ops
  neither read fields nor observe ordering, delaying a `dec` can only delay
  (never hasten) a free, and the aliasing corner is caught by `EReuse`'s
  runtime RC==1 uniqueness branch, which sends shared cells down the
  fresh-allocation path. A fail-loudly full-overwrite guard at the generic
  `EReuse` emission site rejects a reuse whose argument count doesn't match
  the resolved constructor's declared field count, which would otherwise leak
  the reused cell's stale trailing fields.

  After the fix: tree-transform 852 ms, list-ops 67 ms (the latter exactly
  matching the pre-regression figure). Note that `fib(40)` — which allocates
  nothing and is therefore unaffected by FBIP — remains ~2.2x slower than the
  same published table, an unrelated and still-open regression.

  This restores work that existed and was verified on the
  `docs/core-march-types-skeleton` line but never reached `main`; the TIR
  golden snapshot `fbip_dead_binding_reuse` had the starved `dec_rc` + `alloc`
  shape pinned in as its expected output, so the one test written to catch
  this regression was certifying it instead.

- `bench/run_benchmarks.sh` invoked `dune exec march` without `--root .`.
  Run from a git worktree (which lives under the parent checkout), dune
  resolved its root to the *parent* repository and benchmarked that
  compiler rather than the one under test — silently reporting the wrong
  binary's numbers, with no error.

### Fixed

- A record refinement whose record had a field of a non-`Int` type bound to a
  variable (e.g. `{ port: 8080, name: n }` where `name : String`) could
  silently disable refinement checking for the **rest of the file**. The
  reflection placed the variable at the wrong solver sort, the solver rejected
  the malformed query, and the error desynchronised the long-lived solver
  session, so every later check — including plain `Int` ones in unrelated
  functions — came back inconclusive and reported nothing. Such a record is now
  skipped instead of mis-reflected.

### Changed

- `dune runtest` no longer runs `test/test_properties.exe`. That one binary
  was ~86% of the suite's wall-clock (652s of 756s measured in CI) because its
  QCheck property groups push generated programs through the whole compiler
  pipeline hundreds of times each, and alcotest runs cases sequentially with
  no parallelism to offer. CI now runs it as its own parallel, sharded job.
  It is still built (so compile errors there still fail the build); run it
  locally with `dune build @test/property_tests`, or a subset with
  `./_build/default/test/test_properties.exe test '<group-regex>'`.

- `march --compile` no longer recompiles the whole C runtime from source on
  every invocation. The ~20 `runtime/*.c` files are now compiled once per
  (runtime-source, C-toolchain, compile-flags) combination, cached under
  `~/.march/cache/runtime-objs/`, and reused on subsequent builds — only the
  generated LLVM IR for your own program is compiled per invocation. Measured
  locally, this cuts the clang portion of a small program's build from ~1.5s
  to ~0.3s (a ~5x reduction on that step; ~45% off end-to-end, the remainder
  now being March's own frontend). The saving compounds anywhere many
  programs are compiled in sequence — test suites, the differential oracle,
  `forge build` over a multi-file project.

  The cache key covers the runtime sources' content, the C compiler's own
  version, and the full compile-flag string, so editing a runtime `.c`/`.h`,
  bumping clang, or switching optimization/sanitizer/debug flags each get
  their own object set rather than silently reusing a stale one. Builds that
  bake per-invocation defines into the runtime — cross-compilation,
  `--compile-so`, `--hot-reload` with `--signing-pubkey`, and
  `MARCH_HTTP_EVLOOP=1` — automatically fall back to the previous
  single-command compile. `MARCH_NO_RUNTIME_CACHE=1` forces that fallback.

### Fixed

- A record type-mismatch note stated its two sides backwards: a field present
  in the value you passed but absent from the expected type was reported as
  "present in the expected type but missing in the found type". The note now
  names the two sides in words, and the reverse case (a field the expected
  type requires but the value lacks) is reported too, where before it was
  silent.

- Unreachable match arms are now reported inside functions with a declared
  return type. `check_redundant_arms` ran only on the type-inference path, so
  any `match` in checking position — which is every `match` in a function with
  a return annotation, i.e. most of them — silently skipped the analysis.

### Documentation

- Migrated 14 language-reference chapters (Type System, Pattern Matching,
  Modules, Interfaces, Linear Types, Refinement Types, Capabilities, Safety
  by Construction, Memory Model, Actors, Parallel Collections, Supervision,
  Session Types, Clustering) from `specs/lang/` into real, styled pages on
  march-lang.org (`/docs/<topic>/`). These previously rendered as blank,
  unstyled `/<topic>.html` stub pages ("this topic has moved") that every
  site page linking to them — the homepage, the language tour, Getting
  Started, the stdlib guide, the FFI guide, and the "coming from X" guides —
  pointed at. Content was adapted for a general-programmer reader rather
  than copied verbatim: `specs/lang/` keeps the full conformance-ledger
  detail (source citations, golden-test IDs, dated findings) for compiler
  contributors, while the published pages state each caveat once, in plain
  language, without implementation citations.

- The session-types reference chapters (`specs/lang/session-types.md`,
  `specs/lang/core-march-types.md`, `specs/lang/core-march.md`) are
  reconciled with the correctness fixes above. Most notably, the claim that
  every `MPST.*` program segfaults compiled (exit 139) is corrected: a
  3-role and a 4-role protocol both compile, run, and print output
  identical to the interpreter, exit 0 — what remains genuinely
  unimplemented is multiparty `choose`/`offer`, and MPST still has no
  golden conformance witness. Also documented: `Chan.new(Proto)` returns
  its endpoint pair ordered by alphabetically-sorted role name (not
  declaration order), and `loop do ... end` projects to a genuine
  recursive session type and must be a protocol's last step.

## [0.2.0] - 2026-07-23

### Fixed

- A module could not reference a same-name-prefixed sibling module in a
  multi-file project — e.g. entry `mod MyApp` calling into a sibling
  `mod MyApp.Router` declared in its own file (the documented
  "one mod per file" multi-file convention), via `MyApp.Router.dispatch(...)`,
  `use MyApp.Router` + bare `Router.dispatch(...)`, or (previously the only
  working spelling) `alias MyApp.Router as R`. The first two failed with
  `Unknown module \`Router\`.` — the entry-module-self-qualification stripping
  pass matched by string prefix only, so `MyApp.Router.dispatch` (which
  merely starts with the entry's own name, `MyApp.`) was wrongly mangled to
  `Router.dispatch` as if `Router` were one of the entry's own members. A
  related gap in `use`/`alias` resolution (taking only the first segment of a
  dotted import path) and in `use`'s bare-name binding for dotted paths are
  also fixed. Referencing an unrelated-named sibling module always worked and
  still does.

- Fork-join workloads using `task_spawn`/`task_await`/`task_await_unwrap`
  under high task concurrency (thousands of simultaneously in-flight tasks)
  could hit a severe performance cliff — `bench/par_fib.march`
  (`par_fib(40, 20)`) went from a fraction of a second to 54+ minutes past a
  certain task-count threshold. An earlier pass bounded the worst case with
  a spin-then-sleep backoff (cutting wasted CPU) but the workload still
  didn't complete; `task_await` now parks the awaiting green thread and
  wakes it explicitly on completion (mirroring the existing actor-mailbox
  park/wake pattern), which eliminates both the wasted context-switch
  overhead and a LIFO dispatch-starvation interaction that was compounding
  it. The scheduler's separate internal wake-on-parked-proc spin also keeps
  its own generous-grace-period sleep fallback from the earlier pass, so
  neither wait can peg an OS thread at 100% CPU forever with no possibility
  of self-recovery. Compiled `--compile` programs only; the interpreter was
  unaffected.

- Compiled `Csv.read_all`/`Csv.each_row_with_header` could crash
  (nondeterministic SIGBUS/SIGSEGV) or silently return zero rows. A
  builtin-call argument coercion added to fix an unrelated tagging bug
  (`Some((top, _)) -> int_to_string(top)` printing `7` instead of `3`) was
  incorrectly tagging opaque native-pointer handles — Csv/File/Tcp handles
  are represented as plain `Int` in March's type system by convention, but
  are raw C pointers at runtime — whenever they were passed to a builtin
  whose C signature declares the parameter as `ptr`. Restricted the
  coercion to the direction it was actually meant for.

- Refinement checking's return-refinement propagation could false-positive
  through a `let? p = e` binding: the continuation after `let? c = ok5()`
  still saw an outer refined local named `c` instead of the newly-bound one,
  so a subsequent correct use of `c` could be wrongly flagged. `let?` now
  shadows its bound names before checking its continuation, matching every
  other binding construct (`let`, lambda params, `match` binders). Also
  reworded refinement counterexamples from `f() returns v` to
  `f() can return v` — the solver's model is a witness satisfying `f`'s
  postcondition, not necessarily `f`'s actual return value.

- The browser cookbook/playground REPL's bundled stdlib was missing
  `Vault` — the docs/cookbook/vault.md examples errored with `no member
  'new' in module 'Vault'` because `vault.march` wasn't in either
  `js/march_browser.ml`'s `browser_stdlib_files` load-list or
  `scripts/gen-browser-stdlib.py`'s `FILES` list used to generate
  `docs/assets/march_stdlib.js`. Added it to both and regenerated the
  bundled assets.

### Documentation

- The "sandboxed plugin runner" example in docs/cookbook/capabilities.md
  called a `sandbox_eval` function that never existed anywhere in the
  compiler or stdlib — it was illustrative pseudocode, so running the
  example in the cookbook REPL errored with `unbound variable:
  sandbox_eval`. Replaced it with a trivial inline stub so the snippet
  actually compiles and runs; the example's real point (the `PluginCap`
  gate) is unaffected.

- A qualified call to a real module's genuinely nonexistent member (e.g.
  `String.length(...)` — `String` has no `length`; the real API is
  `byte_size`/`codepoint_count`/`grapheme_count`) silently fell through to an
  unrelated same-named binding elsewhere (e.g. the prelude's generic
  `List.length`) instead of reporting "Module `String` does not export
  `length`". The EVar dot-suffix fallback — meant only to resolve
  multi-component local/app-module paths like `Conduit.Storage.workflow_load`
  down to `Storage.workflow_load` — didn't distinguish that case from a
  qualifier that is already a confirmed, loaded stdlib module. Now, once the
  qualifier's first component resolves to a real registered module, a missing
  member always reports the clean "does not export" diagnostic instead of
  falling through to the bare-name search.
- A user-defined interface impl with a compositional `when` constraint (e.g.
  `impl MyEq(Wrap(a)) when MyEq(a) do fn eq(w1, w2) do ... eq(x, y) ... end
  end` — the same shape as the stdlib's own `Eq(List(a)) when Eq(a)`) whose
  body recursively called its own method name on the constrained inner value
  dispatched incorrectly. Interpreted, the recursive call re-entered the SAME
  impl instead of the inner type's impl, producing a wrong answer (or a
  non-exhaustive-match panic). Compiled, it crashed with an internal compiler
  error ("has no runtime-tag rows") whenever the constrained type happened to
  share a method name with an unrelated interface. Both are fixed: the
  recursive call now dispatches by the runtime type of its own arguments on
  both backends, regardless of impl declaration order or nesting depth.
- `root_cap()` — calling the root capability like a function instead of
  referencing it bare (`root_cap`) — typechecked cleanly with `--check` and
  then crashed at runtime: `applied non-function value` interpreted, or an
  `Undefined symbols ... _root_cap` link error compiled. `root_cap` is a
  plain value, not a function; calling it with `()` is now rejected at
  check/compile time with a diagnostic explaining why.
- `File.read` and related I/O builtins (`file_write/append/delete/copy/rename/stat/open`,
  `Dir.list/mkdir/mkdir_p/rmdir/rm_rf`, `Csv.open`, and the TCP/TLS/HTTP/process
  builtins) had their `Result` error type registered as fully polymorphic, so a
  function declaring an incompatible error type (e.g. `Result(_, String)` for
  `File.read`, whose real error is `FileError`) typechecked with zero
  diagnostics and then panicked at runtime the moment the error value was used
  as the wrong type. These builtins' error types are now pinned to their real
  concrete type, so a mismatched declaration is now a compile-time error
  instead of a runtime panic.
- `Actor.call`'s reply value was silently corrupted when compiled: an `Int`
  (or `Bool`/`Unit`) reply came back as its raw tagged-immediate bit pattern
  instead of the real value (e.g. a handler replying with `5` was observed as
  `11` by the caller). `int_to_string`/`bool_to_string`/`float_to_string` are
  the only scalar-consuming builtins that had no dedicated argument coercion,
  so a value arriving through `Actor.call`'s necessarily type-erased reply
  channel was passed straight through with a declared-signature mismatch
  instead of being untagged first.
- The same underlying gap — builtin call arguments never coerced to the
  builtin's own declared native parameter type, only to a user-defined
  function's — also reached compiled output through an unrelated path: a
  scalar bound by a tuple or constructor pattern (e.g. `Some((top, rest)) ->
  int_to_string(top)`, or even a plain top-level `(top, rest) ->
  int_to_string(top)`) passed to any compiler builtin with a native scalar
  parameter (`math_sqrt`, `float_abs`, and ~50 more beyond the three fixed
  above) printed the raw internal tagged-integer encoding instead of the real
  value (`7` instead of `3` for the example above). Call-argument coercion
  now also derives each builtin's declared parameter types directly from its
  own preamble `declare` signature, so every builtin gets the same coercion
  user-defined functions already had — not just the three fixed individually
  above.
- `self()` inside an actor handler was typechecked as a plain `Int` instead
  of that actor's own `Pid`, so passing it anywhere a `Pid` was expected
  (`is_alive(self())`, a typed `Pid` message field) failed to typecheck with
  "expected `Pid` but got `Int`" even though it is a valid `Pid` at runtime.
  `self()` now resolves to the same `Pid[state]` type `spawn` produces for
  that actor.
- A general user interface implemented by two same-short-name types declared
  in different modules (e.g. `NA.Thing` and `NB.Thing` both `impl
  Speak(Thing)`) could have an ambiguous call site resolved, at compile time,
  to whichever impl happened to be declared first — a latent miscompile risk
  rather than an always-reproducing bug, since an unrelated dispatch guard
  happened to mask it for most call shapes. Interface dispatch on same-named
  colliding types is now always deferred to the collision-aware runtime
  dispatch added for this feature, with no first-match shortcut.
- An all-caps acronym stdlib module name (e.g. `RRB`, declared in
  `rrb_vec.march`) failed to resolve in a type annotation with "Unknown module
  `RRB`", even though its functions worked fine as values. The lazy
  qualified-name resolver guessed a module's filename by inserting `_` before
  every uppercase letter (`ConsistentHash` -> `consistent_hash.march`), which
  mangles an acronym into a filename that doesn't exist (`r_r_b.march`).
  Falls back to a lazily-built index of the stdlib directory keyed by each
  file's real declared module name when the naming-convention guess misses.
  Fixing this exposed a second, related bug: a qualified reference to an
  opaque type (`RRB.Vec(Int)`) failed to unify with real values of that type
  (`expected 'RRB.Vec(Int)' but got 'Vec(r3)'`) because the qualified name
  wasn't canonicalized to its bare form when the type's module was being
  loaded for the first time. Both are fixed together.
- `let x : T = e` type annotations silently accepted ANY resolution failure
  in `T` and fell back to inferring the type from `e` alone with zero
  diagnostics — e.g. `let e : Vec(Int) = "not a vec"` typechecked cleanly.
  This was meant to tolerate a phantom/typestate tag used in type position
  (`let h : Handle(Open) = ...`, where `Open` is a data constructor, not a
  type name) but was too broad, silently discarding genuinely broken
  annotations (an unresolvable module, a typo'd or renamed type) too.
  Narrowed to only tolerate the phantom-tag case (an unresolved name that IS
  a known data constructor); any other resolution failure now surfaces as a
  real diagnostic.
- An inline lambda passed directly as a call argument (e.g. `Dom.on_frame(fn _
  -> ...)`) failed to parse if its body had a plain statement (not a `let`
  binding) immediately followed by another expression — e.g. a function call
  followed by an `if`/`else` — even though the identical body worked fine as a
  named function or a lambda wrapped in `do...end`. Symptom: `I got stuck here`
  at the following token. Inline lambda call arguments now accept bare
  statements before the final expression, matching `do...end` block bodies.
- A linear or `always_linear`-typed value *acquired* through `let? p = e` or
  `with Ok(p) <- e do ... end` — rather than bound by a plain `let` or a
  function parameter — was never tracked as linear at all, so consuming it
  twice (e.g. passing the same handle to two separate calls, each behind its
  own `let?`) went completely undetected. The identical double-use was
  already correctly rejected when the value came from an ordinary `let` or a
  function parameter. Affects any code acquiring a linear resource through a
  Result-returning `let?`/`with` chain.
- A self-tail-recursive function forwarding a freshly-built value as its own
  next argument (e.g. an accumulator built via `String.join`/`String.split`)
  could silently corrupt that value in compiled programs — freed one
  instruction before it was reused for the next iteration. Symptom: wrong
  answers with no crash or error, e.g. `stdlib/toml.march`'s integer parsing
  (`Toml.get_int` on `"port = 9000"`) returned `9` instead of `9000` compiled
  while the interpreter was correct. Affects any compiled program using this
  accumulator-recursion shape over a value not extracted from an
  already-borrowed container (a list/tree traversal passing along an existing
  field, e.g. `Cons(_, t) -> go(t, ...)`, was unaffected).
- Interfaces implemented separately for two same-short-name types declared in
  different modules (e.g. two modules each with their own `impl Speak(Thing)`)
  now dispatch to the correct implementation at runtime, in both the
  interpreter and the native backend. Previously the wrong implementation's
  body could run silently: the interpreter took whichever impl was registered
  last regardless of the value's actual type, and native code could miscompile
  via colliding constructor tags or value representation. Built-in interfaces
  (`Eq`, `Ord`, `Show`, `Hash`) were already correct and are unaffected. (#57)
- `string_to_float` and `String.to_float` crashed (segfault) in compiled
  programs whenever the parsed `Float` was actually used — e.g.
  `match string_to_float(s) do Some(f) -> ... end`. Fine in the interpreter;
  native code stored the parsed value in a representation the rest of the
  compiler didn't expect. Affects any compiled program parsing floats from
  strings, including `stdlib/toml.march`'s float handling.
- `Html.raw(...)` content silently disappeared when interpolated into a `~H`
  sigil in compiled programs — e.g. `~H"<button>${Html.raw("hi")}</button>"`
  rendered `<button></button>`. Fine in the interpreter. Affects the
  documented layout/partial-nesting pattern
  (`~H"<body>${Html.raw(IOList.to_string(body))}</body>"`) as well.
- `Option.or_else` and `Option.unwrap_or_else` crashed at runtime
  (`arity mismatch: expected 0 args, got 1`) when called with a genuine
  zero-argument callback — `fn -> ...`, the natural spelling for their
  declared `() -> a` parameter. Both functions invoked the callback as
  `f(())` (passing an explicit unit value) instead of `f()`, which only
  matched a 1-arg-discard closure (`fn _ -> ...`). Fixed to call `f()`;
  affects both the interpreter and compiled programs.
- `pfn` (private function) visibility could be silently bypassed when a
  same-file nested module's private function shared its bare name with an
  unrelated global (e.g. a function named `hash`, colliding with the `Hash`
  interface's built-in method). The call typechecked without error, ran
  correctly in the interpreter, and produced a garbage value in compiled
  programs — a privacy violation that also corrupted the result, not just a
  missing diagnostic. Now correctly rejected at `--check` and `--compile`
  with the same "is private to module" error other privacy violations
  already produced.
- `RRB.push`/`Array.push` crashed compiled on the second `Float` element
  pushed (`RRB.push(RRB.push(RRB.empty(), 1.5), 2.5)`). A discarded
  (wildcard-matched) field of a list cell never got the special-casing a
  *named* field already had, so the compiler treated it as reference-counted
  even when the concrete element type (`Float`) doesn't need that — freeing
  memory that was never actually heap-allocated. (Reading a pushed `Float`
  back out — `Array.get`/`RRB.get` — had a separate, sibling bug; see below.)
- `task_spawn`/`Task.async` with a `Float`-returning callback, followed by
  `task_await_unwrap`/`Task.await_unwrap`/`Task.await`, failed to compile
  with an internal LLVM type error. Affects `Parallel.preduce`/`psum_float`,
  which spawn one task per worker chunk.
- A tail-recursive function combining a `Float` accumulator with a
  heap-value parameter (e.g. an `Array`/`List`) — the shape `RRB.fold`'s
  internal loop uses — returned a wrong answer or crashed
  (`RC underflow (rc was 0)`) in compiled programs, blocking
  `Parallel.preduce`/`psum_float`'s worked example
  (`docs/cookbook/parallel-data.md`) end-to-end even after the task-boundary
  fix above. Two independent causes: a constructor field discarded via a
  wildcard pattern (`Cons(_, t)`) kept an internal type placeholder that
  made the compiler treat an unboxed `Float` as a heap pointer needing
  reference counting, corrupting memory; and a value read out of a generic
  container field was passed to some function calls without converting it
  to that function's expected native representation, so the callee silently
  read `0.0` instead of the real value. Both fixed. Affects any compiled
  program building or reading a `List`/`Array` of `Float` through a generic
  helper (`Array.from_list`, `Array.get`, and therefore `RRB`'s `Float`
  operations) or wildcard-discarding an element of a `Float` container.
- `Dom.clone`, `Dom.first_child`, and `Dom.last_child` were declared as
  extern runtime builtins but never got a public stdlib wrapper, like every
  other DOM function — so they were unreachable from March code
  ("Module `Dom` does not export ...") despite being documented.
- `fn main(cap : Cap(IO)) : ()` — the documented pattern for receiving the
  initial IO capability — never actually worked: in the interpreter it
  silently no-oped (the program appeared to exit successfully having done
  nothing), and compiled programs crashed (SIGBUS) on startup. Both backends
  now run it correctly; any other `main` arity or parameter type is now
  rejected at compile time with a clear error instead of misbehaving.
- WebSocket connections in the interpreter (`forge run`, plain `march
  file.march`, and any tool built on it, including `forge scroll.serve`)
  disconnected almost immediately whenever the client went quiet — an open
  connection would flip to closed within milliseconds of the server having
  nothing to read, sometimes before the client's very first message was even
  processed. A raw handshake with no further traffic got an instant
  server-initiated close. The server's WebSocket handler was reading from a
  socket still configured for the (unrelated) HTTP accept loop's internal
  bookkeeping, which made an ordinary "no data yet" condition look
  indistinguishable from the client disconnecting. Compiled (`--compile`)
  WebSocket servers had a milder version of the same bug: an idle connection
  would be dropped after 10 seconds instead of staying open. Both are fixed;
  idle WebSocket connections now stay open as expected in both backends.
- `Vault.update` crashed (segfault) in compiled programs, for both an inline
  lambda and a named function callback — e.g.
  `Vault.update(store, "hits", fn n -> n + 1)`. Fine in the interpreter.
  Affects the documented atomic-update pattern and the rate-limiter cookbook
  example.
- Corrected stale claims and two tutorial code blocks in the top-level
  `README.md` that no longer matched the compiler: linear/affine types and
  `kill`/`is_alive` are fully supported (were marked "in progress" /
  "interpreter only"); the higher-order-function and actor examples now
  typecheck and run as written; the project-layout map now lists `stdlib/`,
  `forge/`, `lsp/`, and `test/`, previously omitted entirely.
- Corrected the `install.sh` `MARCH_VERSION` pin-example comment.
- Audited every March code example across the docs site (guides, the
  language tour, the cookbook, and the stdlib reference) against the current
  compiler and fixed everything that no longer typechecked, ran, or matched
  its claimed output — including a large number of stale API references in
  `docs/stdlib.md` (wrong module names, argument order, arity, or return
  types across `String`, `Math`, `JSON`, `HTTP`, `Vault`, `URI`, `Dom`, and
  more), the REPL transcript in `docs/getting-started.md` (real prompt is
  numbered, `= value` output by default), and dozens of smaller fixes across
  `docs/cookbook/*`. Several real compiler/stdlib bugs surfaced along the way
  (silent wrong answers and crashes, mostly compiled-only) that are outside a
  docs fix's scope and were filed separately rather than papered over in the
  docs.
- `docs/cookbook/linear-types.md`'s Typestate section and its "safe socket
  lifecycle" example — left unfixed by the docs audit above pending a design
  decision — didn't compile as written and were internally inconsistent
  (`via` transition functions shown returning `Result`/tuples, an acquisition
  function listed as a transition despite not taking a handle, a socket type
  missing its state parameter). Rewritten so each resource's lifecycle splits
  into an ordinary Result-returning acquisition function outside
  `transitions` plus pure `Handle -> Handle` transitions declared inside it,
  matching the working pattern in `specs/lang/capabilities.md`. Every code
  block was verified against the compiler, including that a wrong-order
  transition call is correctly rejected.
- Audited every March code example across `specs/lang/` (the authoritative
  language reference, ~341 code blocks across 21 files) against the current
  compiler, the same way as the docs/ sweep above. Several sections described
  an interface-dispatch architecture superseded by the impl-coherence and FQN
  dispatch-identity work that landed 2026-07-17 through 2026-07-21 (rewritten
  with live-verified current behavior); the Operator Reference table in
  `type-system.md` had `+ - * /` and the dotted `+. -. *. /.` operators
  backwards (the plain operators are the polymorphic Int/Float ones, not the
  dotted ones); several "known limitation" notes across `pattern-matching.md`
  and `session-types.md` described parser/linearity gaps already fixed. Around
  70 real example/prose bugs fixed in total. `specs/lang/grammar.md`'s
  `parser.mly`/`token_filter.ml` line citations have drifted (~15 of ~294
  fixed; the rest need a dedicated re-grep pass). Several real compiler bugs
  surfaced along the way and were filed separately, most notably a
  currently-live regression where compiled `Actor.call`/`Actor.reply` returns
  the raw tagged value instead of untagging it — it breaks an existing pinned
  golden test wired into `dune runtest`, just not caught because the fast
  test runner bypasses that lane.

## [0.1.1] - 2026-07-21

First tagged release.

### Added

- **Type system**: Hindley-Milner inference with bidirectional checking at
  function boundaries; algebraic data types and pattern matching; records
  with functional update (`{ r with field: value }`); polymorphic functions
  monomorphized at compile time; linear and affine types for ownership, safe
  mutation, and actor message-passing isolation; interfaces (`interface`/
  `impl`) with default methods and conditional impls (`when` constraints);
  type-level naturals for dimension-checked `Vector`/`Matrix`/`NDArray`;
  refinement types (`{T | predicate}`) with a Z3-backed verification bridge
  (in progress).
- **Memory management**: Perceus reference counting (deterministic, no GC
  pauses) with FBIP (Functional But In-Place) — pattern-matched values with
  a unique reference count are rewritten in place instead of freed and
  reallocated; escape analysis promotes allocations to the stack where
  possible; defunctionalization compiles closures to structs with no
  indirect-call overhead.
- **Concurrency**: actor model with share-nothing message passing, `spawn`,
  `send`, capability-secured references, location-transparent `Pid`;
  supervision trees and a distributed/clustering layer with node discovery;
  structured concurrency via `Task` (`async`/`await`/`race`/`any`/
  `all_settled`/`scope`, cancellation tokens); `Future` and `Stream`.
- **Backends**: native compilation via LLVM/clang, including cross-compilation
  to Linux (amd64/arm64) from any host via `zig cc`; `--target wasm64-wasi`
  for WebAssembly and a JS backend; a tree-walking interpreter and a
  JIT-backed REPL.
- **Tooling**: `forge` package manager and build tool (`new`, `build`, `run`,
  `test`, `deps`, `publish`, `watch`, `bench`, ...) with content-addressed
  dependency versioning; an LSP server (diagnostics, hover, goto-definition,
  completions, code actions); a 111-module standard library (collections,
  `BigInt`/`Decimal`/`Ratio`, HTTP client/server, JSON/MessagePack/TOML,
  crypto, DataFrame, distributed-OTP actors, and more); FFI for C interop,
  hot code reload, and a `--check-json` machine-readable diagnostics mode.

[Unreleased]: https://github.com/march-language/march/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/march-language/march/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/march-language/march/releases/tag/v0.1.1
