# `NativeArray.sort_*`: in-place ipnsort-style sort for flat numeric arrays

Logged 2026-09-16. `[P2]`

**Status: the i64 width landed 2026-09-16** (`NativeArray.sort_int`); see
`specs/progress/2026-09-16-native-array-sort-int-ipnsort.md`. What remains open
here is the other four widths (f64, f32, i32, u8) and the follow-ups at the
bottom. The Design and Wiring sections below are the record of how the i64 one
was built; follow them for the rest.

## Why

`stdlib/native_array.march` has five flat, mutable, contiguous element widths
(i64, f64, f32, i32, u8) and no sort at all. The list sorts in
`stdlib/sort.march` (timsort / introsort / comparison networks over cons cells)
do not apply: NativeArray's whole point is cache-friendly sequential memory, and
a sort should live in the C runtime next to `native_int_arr_sum` and friends.

This is exactly the niche Rust 1.81's `sort_unstable` (ipnsort) was built for.
Stability is meaningless for bare scalars, so the unstable/in-place/no-scratch
design is free here. Driftsort (the stable one) is the right shape for
`Array.sort_by` on the persistent trie, where elements carry payloads and a user
comparator; that is a separate item and is *not* this one.

## Measurements (2026-09-16, arm64 Apple clang 17, runtime flags `-O2 -fno-strict-aliasing -fwrapv`)

Harness: `bench/c/native_sort_bench.c`. Four i64 sorts, eight input patterns,
three sizes, every timed run `memcmp`'d against libc `qsort`'s output (verify
sweep over 21 sizes × 8 patterns × 3 reps passed with 0 mismatches). Load
average was ~5.7 throughout, so treat absolute ms loosely and ratios as the
signal. Min-of-N ms.

| n=5,000,000 | qsort | naive introsort | ipnsort-style | LSD radix |
|---|---|---|---|---|
| random | 431 | 273 | **71** | 39 |
| sorted | 15.3 | 32.2 | **1.4** | 63.9 |
| reversed | 68.4 | 33.7 | **2.3** | 64.2 |
| nearly (1% swaps) | 116 | 39.6 | 60.8 | 63.1 |
| 10 distinct | 56.1 | 88.7 | **9.2** | 18.8 |
| sawtooth (i % 1000) | 106 | 112 | 38–97 † | 21.2 |
| organ pipe | 172 | 204 | **64.9** | 61.5 |
| all equal | 6.8 | 48.6 | **1.4** | 13.3 |

| n=100,000 | qsort | naive introsort | ipnsort-style | LSD radix |
|---|---|---|---|---|
| random | 6.14 | 4.03 | 1.06 | 0.70 |
| sorted | 0.29 | 0.44 | 0.03 | 0.88 |
| reversed | 1.37 | 0.48 | 0.04 | 0.85 |
| nearly | 1.62 | 0.52 | 0.91 | 0.85 |
| 10 distinct | 1.02 | 1.34 | 0.17 | 0.39 |
| sawtooth | 1.85 | 2.05 | 0.48 | 0.55 |
| organ pipe | 2.57 | 2.58 | 0.96 | 0.87 |
| all equal | 0.13 | 0.67 | 0.03 | 0.22 |

† randomized pattern-breaking; see finding 2.

What the numbers say:

1. **ipnsort-style beats qsort 5–30x and a naive introsort 2.5–35x** on every
   pattern except nearly-sorted. The wins are not from one trick: the full-run
   scan gives sorted/reversed, equal-partition gives low-cardinality and
   all-equal, branchless Lomuto + network small-sort gives random.
2. **Pseudo-median-of-9 at a fixed `n/8` stride is defeated by periodic input.**
   The first prototype took 337 ms on sawtooth at 5M: the period (1000) divides
   the stride (625,000), so all nine samples had the same value, every pivot was
   the minimum, and the depth limit tripped into heapsort on the whole array.
   pdqsort's pattern-breaking step (on a partition with either side < n/8, swap
   four elements at the sample positions with xorshift-chosen positions) brought
   it to 38–97 ms. **The implementation must include this step**; ipnsort-in-Rust
   is not immune to it either and does the same. The residual variance is the
   randomization; a deterministic xorshift seed keeps it reproducible.
3. **Nearly-sorted is the one pattern where a merge-based sort would win** (naive
   introsort 40 ms vs 61 ms only because Hoare partitioning happens to like it;
   driftsort/timsort-style natural runs would be ~O(n)). ipnsort only detects a
   run spanning the *entire* array. Accepting this: it is 2x behind, not 30x,
   and adding natural-run merging means scratch memory. Documented, not fixed.
4. **LSD radix wins random and low-cardinality at 5M (1.8x and 2x) but loses
   badly on every ordered pattern (up to 46x)** and needs an O(n) scratch
   buffer plus a signed→unsigned key transform per width. It is the right
   *second* algorithm to add for `sort_int` on random data at large n, behind
   a size threshold, but not the baseline. Not in scope for the first landing;
   noted so nobody re-derives the comparison.

## Design

One C function per width in `runtime/march_runtime.c`, no comparator crossing
the closure boundary:

```c
void *native_int_arr_sort(void *arr);     /* i64 */
void *native_float_arr_sort(void *arr);   /* f64 */
void *native_f32_arr_sort(void *arr);
void *native_i32_arr_sort(void *arr);
void *native_u8_arr_sort(void *arr);      /* counting sort, 256 buckets */
```

**Ownership/FBIP contract: identical to `native_int_arr_set`** (see its comment
block at the definition). `arr` is owned/consumed (absent from
`borrow.ml`'s `extern_borrow_table`); at `rc == 1` sort in place and return the
same pointer; at `rc > 1` allocate a copy, sort that, `march_decrc(arr)`, return
the copy. This keeps `let a = NativeArray.sort_int(a)` allocation-free and
preserves copy-on-write for aliases. Surface API returns the array, never unit,
so the interpreter (OCaml `Array.sort` on the wrapped array; parity is the
contract) and the compiled backend agree.

Algorithm, per width, shared through a macro or `_Generic` over the element
type (the u8 width is a counting sort instead):

1. `n < 2` → return. `n <= 32` → small-sort.
2. **Top-level full-run scan.** Strictly descending run of length n → reverse
   in place, done. Non-descending run of length n → done. (Only at the top
   level, as ipnsort does.)
3. **Quicksort loop** with depth limit `2·⌊log₂ n⌋`:
   - `n <= 32` → small-sort; limit exhausted → heapsort.
   - Pivot: pseudo-median-of-9 (median of three medians of three at stride
     `n/8`) for `n >= 64`, median-of-3 below.
   - **Equal-partition:** if the segment has an ancestor pivot and the chosen
     pivot is not greater than it, every element `<= pivot` equals the ancestor;
     partition them out with a `<=` predicate and continue on the remainder
     with no ancestor. This is the whole low-cardinality story.
   - Otherwise branchless Lomuto with `<`: unconditional swap of `v[i]` and
     `v[j]`, `j += (v[i] < pivot)`. Clang emits cmov/csel for this shape; do
     not "optimize" it into a branch.
   - **Pattern-breaking** when either side is smaller than `n/8` (finding 2).
   - Recurse on the left, loop on the right with the pivot as ancestor.
4. **Small-sort:** apply the optimal 19-comparator 8-element network
   (branchless compare-exchange) to each aligned block of 8, then one
   insertion pass.

   What the i64 width actually shipped is a classic Knuth 5.3.4 network, NOT a
   port of Rust's `small_sort_network` — follow `nsort_net8` in
   `runtime/march_runtime.c` for the remaining widths so they agree, or port
   Rust's more elaborate layer for all five at once and re-measure. Do not mix
   the two. Rust's small-sort is the bigger of the two and is where a chunk of
   ipnsort's random-input lead lives, so switching is a legitimate follow-up —
   but it is a change to measure, not a free upgrade.

   Verify any replacement network by the **0-1 principle** (a comparator
   network sorts all inputs iff it sorts every 0/1 input), which is 2^8 = 256
   exhaustive cases for an 8-element network. `nsort_net8` was checked that way
   on 2026-09-16: 0/256 failures. Random and patterned inputs are suggestive
   but not decisive for a fixed network — a wrong comparator can survive them.

   Either way `stdlib/sort.march`'s per-arity cons-cell matches are the wrong
   source: on a flat array the network is a fixed swap sequence over indices,
   which is both smaller and faster.
5. **Heapsort fallback:** standard sift-down. Needs its own direct test (force
   it with a tiny depth limit under a test hook), given the list heapsort's
   flake history in `specs/progress/`.

### Floats

`<` on doubles is not a total order because of NaN, and a quicksort with an
inconsistent comparator can corrupt its own invariants (Rust panics; a C loop
just reads out of bounds). Decision for `sort_float`/`sort_f32`: **compare by
IEEE 754 `totalOrder` key**, i.e. sort on
`key = bits ^ (((int64_t)bits >> 63) & 0x7FFFFFFFFFFFFFFF)` as a signed
integer (negative floats get their magnitude bits flipped; the sign bit is
kept, so signed `<` on the key is `totalOrder`). It is branchless, puts `-NaN < -Inf < … < -0 < +0 < … <
+Inf < +NaN`, and reuses the i64 code path verbatim on the transformed keys
(transform in, sort, transform out; or compare through the key on the fly,
which costs two xors per compare). `-0.0` sorts before `+0.0`, which
`Float.compare` semantics elsewhere in stdlib should be checked against.

Alternative considered and rejected: refuse arrays containing NaN via a
refinement precondition `no_nan(arr)`. It's expressible in refinecheck and
would be nice for callers who can prove it, but as the *only* mode it makes
`sort_float` unusable on real data columns. Offer it later as a tighter
wrapper if wanted.

### Interpreter

`Array.sort` / `Array.stable_sort` on the OCaml backing array with
`compare` for ints and the same totalOrder key for floats, so the two
backends produce identical output (the NaN placement must match too; OCaml's
`compare` on floats treats NaN as less than everything, which is *not*
totalOrder, so use the key).

## Wiring checklist

The usual nine-plus sites (memory: adding one builtin touches nine sites),
concretely for `native_int_arr_sort`, copying `native_int_arr_min`'s entries:

- `lib/typecheck/typecheck_builtins.ml` — signature `NativeIntArr -> NativeIntArr`
- `lib/eval/eval_builtins.ml` — interpreter arm
- `runtime/march_runtime.c` — the sort; `runtime/sources.list` unchanged (no new file)
- `lib/tir/llvm_builtins.ml` — table entry **and** the `PDeclare` list
- `lib/tir/defun.ml` `builtin_names`
- `lib/tir/borrow.ml` — add to **`extern_owned_builtins`** (owned/consumed, like
  `native_int_arr_set`). Not merely "absent from `extern_borrow_table`": every
  `in_is_builtin` row with a `ptr` parameter must appear in exactly one of
  `extern_borrow_table`, `all_args_borrowed_builtins` or `extern_owned_builtins`,
  and `test_builtin_borrow_classification` fails on an unlisted name.
- `lib/tir/alloc_contract.ml` — same list `native_int_arr_min` is in
- `lib/tir/purity.ml` — pure (deterministic given input; the pattern-breaking rng is a fixed-seed local)
- `test/test_codegen.ml` golden preamble — will redden on the new `PDeclare`
- `stdlib/native_array.march` — `sort_int` / `sort_float` / … wrappers with doctests
- `test/native/` — a compiled golden covering every pattern in the harness at
  a few sizes, plus the forced-heapsort case, plus NaN/-0.0 placement for floats

## Tests that must go red before green

Two different instruments, and it matters which one answers which question.

**Correctness** is `test/native/native_arr_sort.march` (dune rule
`native_arr_sort`). The load-bearing case is `alias original intact`: forcing
the in-place path unconditionally flips that line, and only that line, to
false. Verified 2026-09-16 — but note the trap it exposed first. A perturbation
to `runtime/*.c` followed by `dune build --root . bin/main.exe` does **not**
restage `_build/default/runtime`, which is the tree the driver actually
compiles, so the first perturbation run was vacuous and reported green. Build a
target with a runtime dep (e.g. `dune build --root . test/native_arr_fold`) and
confirm the staged copy changed before believing any perturbation result.

**Performance** claims are the harness's job (`bench/c/native_sort_bench.c`),
not the suite's — a correctness test cannot see a 3x regression. Each of these
was measured by removing the feature from the harness:

- Remove the pattern-breaking step: sawtooth at 5M regresses ~3.5x (97 → 337 ms).
- Remove equal-partition: all-equal and dist10 lose their near-linear behaviour.
- Break the full-run scan: sorted/reversed fall back to the quicksort path.
- Force `limit = 0`: output must still be sorted (heapsort path exercised).

## Out of scope, filed here so they aren't re-derived

- Radix sort behind a size threshold for `sort_int` (finding 4).
- Natural-run merging for nearly-sorted input (finding 3).
- `Array.sort_by` / `RRB.Vec` sort via unpack → driftsort with closure
  comparator → bulk rebuild; that is the stable, allocating sibling of this.
- `sort_by_key` with a closure: closure calls through `clo_call_int_int_int`
  per compare would erase most of the win; key-extract once into a parallel
  array, then sort (index, key) pairs.
