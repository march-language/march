# `[P3]` `Array.sort_by` / `RRB.Vec` sort: a stable sort, and `sort_by_key` (DONE, 2026-09-28)

**Filed:** 2026-09-25 as `specs/todos/2026-09-25-array-sort-by-driftsort.md`
(split out of `specs/progress/2026-09-25-native-array-sort-narrow-widths.md`).
**Closed:** 2026-09-28.

## What landed

New API, all stable, all with `List.sort_by`'s comparator contract (`le(a, b)`
true when `a` may come before `b`; equal elements keep their input order for a
`<=`-style comparator; with a strict `<` the order of ties is unspecified, as
for `List.sort_by`):

- `Array.sort_by(v, le)`, `Array.sort_by_key(v, key : a -> Int)`
- `RRB.sort_by(v, le)`, `RRB.sort_by_key(v, key)` (delegate to `Array`)

backed by two runtime builtins over lists, `list_stable_sort_by` and
`list_sort_by_int_key` (C symbols `march_list_stable_sort_by` /
`march_list_sort_by_int_key` in runtime/march_runtime.c, prototypes in
march_runtime.h; wired through typecheck, eval, llvm_builtins rows with
`c_name` + PDeclare, defun, borrow (list borrowed, closure owned), js_emit +
march_runtime.mjs, and the native preamble golden in test_codegen.ml).

### The sort

An adaptive stable merge sort over a flat buffer of the list's elements
(`SSORT_DEFINE`, instantiated for closure comparisons and for key/index
comparisons): natural runs (ascending, or strictly descending and reversed),
short runs extended to 16 by binary insertion, then bottom-up merges of
adjacent runs, each trimmed by binary search to the part that actually
overlaps and done in place through a buffer of the smaller part (<= n/2).
Presorted or reversed input costs n - 1 comparisons.

It is not driftsort. Driftsort adds lazy "unsorted chunk + stable quicksort"
handling, which makes more comparisons for fewer moves; that trade suits
Rust's inlined comparators, while here every comparison is a closure call, so
the design minimises comparisons instead. Driftsort's run detection, run
extension and trimmed merges are what this keeps.

`sort_by_key` calls the key closure once per element (not per comparison),
then sorts element indices by key with an inline `<=`, so equal keys keep input
order; this is the "extract keys once" shape the todo asked for.

Two things the first compiled run found:
- A closure call OWNS its arguments (Borrow pins every apply-function
  parameter owned; a comparator that destructures a tuple releases it), so the
  sort hands the comparator a fresh reference to each element per call. The
  first version passed borrowed elements: strings survived by luck, tuples
  crashed.
- The list is BORROWED by the builtin (the runtime's `march_decrc` frees a list
  cell shallowly), and a fresh list is built holding one new reference per
  element.

### Bulk `Array.from_list`

`Array.from_list` pushed one element at a time, and each push copied the
up-to-32-element tail list: ~540 ns per element, which dominated a sort
(sorting 100k presorted pairs took 64 ms, 54 ms of it rebuilding). It now
builds the trie in bulk: the last 1..32 elements become the tail, the rest
32-element leaves, grouped 32 at a time into branches until one root remains,
5 shift bits per level. That is exactly the shape push builds; a new
`Array.debug_same_shape` test hook checks it against
`Array.debug_from_list_by_push` for every n in 0..2000 (all equal), and get,
set and push keep working on the result.

## Measurements

Compiled `--opt 2`, (Int, Int) pairs sorted by the first field, min of 5; the
"before" is what a program writes today, `Array.from_list(List.sort_by(
Array.to_list(a), le))`, on origin/main's stdlib. Load average 11-15.

| input | n | before (origin/main round trip) | `Array.sort_by` | `Array.sort_by_key` |
|---|---:|---:|---:|---:|
| random | 100k | 250 ms | 47-52 ms | 23-25 ms |
| presorted | 100k | 159 ms | 13-14 ms | 12.6-12.7 ms |
| 100 distinct keys | 100k | 243 ms | 48-50 ms | 23 ms |
| random | 1M | 3,156 ms | 1,092 ms | 509 ms |
| presorted | 1M | 1,743 ms | 145 ms | 131 ms |
| 100 distinct keys | 1M | 3,148 ms | 945 ms | 410 ms |

`Array.from_list` alone: 54 ms -> 6.6 ms at 100k, 568 ms -> 74 ms at 1M.

## Tests

- `test/native/array_sort_by.march` (dune rule, one golden for the compiled and
  the interpreted run, which is the parity check between the C sort and the
  interpreter's OCaml `List.stable_sort`): all four functions over 66 cases
  (11 sizes 0..5000 x 6 key patterns with heavy duplication, presorted,
  reversed, all-equal, organ), checking ordered-and-stable, agreement with
  `List.sort_by`, and a fingerprint; plus float, string-by-key and descending
  string sorts. A runtime whose merge takes the right element on ties fails it
  (56/66).
- The JS target: the same four functions on a small program under node agree
  with the native output (the big fixture itself overflows the JS stack in its
  own list-building recursion, which has no tail calls there).
- `Array.from_list` shape: 2001/2001 against push, interpreted and compiled.

## ASAN

Linux container (arm64), `MARCH_SANITIZE=1`: the fixture and a small program
covering all four functions (tuples, floats, strings) run with **0 ASAN
errors**. LeakSanitizer does report leaks, and they are the `Array` values: a
loop that builds and drops an `Array` leaks its trie on origin/main too (~1.6
allocations per element per build; ~2.1 with the bulk `from_list`, which leaks
the same structure in a different mix). The sort builtins add nothing beyond
the second `Array` a sort builds. Filed as
`specs/todos/2026-09-28-array-built-then-dropped-leaks-trie.md`.

## Found in passing (not fixed here)

Compiled `to_string` of a `List((Int, String))` that went through `Array`
prints `#<tag:0>` for each tuple (the interpreter prints the tuples); the same
on origin/main, without any sort involved.
