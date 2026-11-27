`[P4]` Standard-library and compiler performance ideas from an AI Mode review (2026-11-26)

A Google AI Mode conversation (shared link https://share.google/aimode/DXwsLHemeGSJLNjHI,
read 2026-11-26) suggested performance work for March after reading the README, the getting-started
docs and the stdlib index. It is model output: the papers it cites (several dated 2026) and its
claims about March were not checked except where noted. This file lists the candidates so each
can be measured before anyone builds it; split an item into its own todo when someone takes it.

Not a plan: benchmark first (`specs/benchmarks.md`), and drop anything March already does.

## Checked against the repo (2026-11-26) and still true

- `OrderedMap` and `SortedSet` are AVL trees (`stdlib/ordered_map.march`, `stdlib/sorted_set.march`).
  Suggestion: a persistent B-tree with small inline node arrays (8 or 16 keys), so Perceus reuse
  updates a leaf in place and the tree is 3 to 4 times shallower.
- `Queue` is a two-list deque (`stdlib/queue.march`). Suggestion: incremental (banker's) reversal
  or fixed-size chunks, to remove the O(n) `List.reverse` spike when the front empties.
- `Seq` is church-encoded (`stdlib/seq.march`). Suggestion: step streams
  (`Yield(a, s) | Skip(s) | Done`), which compose `zip`, `take` and early exit without a closure per
  element.
- `Stats` takes `List(Float)` (`stdlib/stats.march`), and a `Float` in a generic field is boxed
  (`specs/lang/memory-model.md`). Suggestion: `NativeArray(Float)` fast paths using `Simd.F64x2`
  (vectorised pairwise or Welford summation).
- A nullary constructor of a variant with payload cases (`Nil`) is a heap cell
  (`specs/lang/memory-model.md`). Suggestion: encode nullary constructors as tagged immediates and
  skip RC on them. Check against the current niche and representation work before starting.

## Claims about March not yet checked

- `Regex` and `AhoCorasick` step through map-based states. Suggestion: flat `NativeArray(Int)`
  transition tables (`state * 256 + byte`) plus `Simd.U8x16` prefiltering of candidate start
  bytes (Teddy-style, as in Rust's `aho-corasick`).
- `Csv` and `Base64` are scalar. Suggestion: `Simd.U8x16` delimiter masks and 16-byte chunked
  encode and decode.
- `Map`: a small-map inline form (at most 8 pairs in a flat array) before the HAMT, since most maps
  and JSON objects are small. `Map` is already a HAMT (30-bit hash mask).
- `Json`: a structural tape over the input with lazy views (the simdjson approach) instead of
  building the whole tree up front. `JsonStream` exists; compare with it first.
- `String`: slice views for zero-copy parsing (HTTP headers), and a builder that allocates once on
  `build()`. `IOList` exists; compare with it first.
- `DataFrame`: columnar `NativeArray` columns with validity bitmaps instead of `Option(Float)`, and
  selection vectors for late materialisation.

## Compiler and runtime suggestions

- Atomic RC on thread-local data (`specs/atomic-rc-design.md`): biased reference counting (Choi et
  al., PACT 2018), or a thread-local vs shared lattice in the escape analysis so Perceus emits
  non-atomic RC for values that never reach `send`, `spawn` or `pmap`.
- Size-class allocation: thread-local size-class pages, with `llvm_emit` calling size-specialised
  `march_alloc_N` / free entry points, since constructor sizes are known at compile time. Check what
  `runtime/march_heap.c` already does first.
- `lib/tir/mono`: share one emitted function between instances whose types have the same runtime
  layout and RC behaviour (pointer-sized types), to cut emitted IR and clang time.
- `lib/tir/fusion`: step-based stream fusion for `List` / `Array` pipelines that the current rules
  do not fuse (`zip`, `take`, mixed `filter` chains). See also
  `todos/2026-09-28-nativearray-fusion.md`.
- Borrow inference across non-escaping call chains and recursive spines; inline the `rc == 1` fast
  path in drop. Measure against `bench/tree_transform.march` and `bench/list_ops.march`.
- Query-based incremental compilation (the Salsa / rustc query model) and caching refinement queries
  by a structural hash. Compare with the existing CAS and VC cache first.

## Not applicable or already done

- TRMC for `List.map` / `filter` (TRMC is on by default), a HAMT `Map`, AlphaDev sorting networks
  in `Sort`, `NativeArray` auto-vectorisation: the review lists these itself as present.
