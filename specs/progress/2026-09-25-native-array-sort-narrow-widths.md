# `NativeArray.sort_*`: in-place sorts for all five flat numeric widths

Logged 2026-09-16 as a `[P2]` todo. **Completed 2026-09-25** with the three
narrow widths. All five widths now have a sort:

| width | function | C entry | algorithm | landed |
|---|---|---|---|---|
| i64 | `sort_int` | `native_int_arr_sort` | ipnsort-style core (`nsort_i64`) | 2026-09-16, `specs/progress/2026-09-16-native-array-sort-int-ipnsort.md` |
| f64 | `sort_float` | `native_float_arr_sort` | i64 core on 64-bit totalOrder keys | 2026-09-24, `specs/progress/2026-09-24-native-array-sort-f64.md` |
| i32 | `sort_i32` | `native_i32_arr_sort` | the same core at `int32_t` (`nsort_i32`) | 2026-09-25, this file |
| f32 | `sort_f32` | `native_f32_arr_sort` | i32 core on 32-bit totalOrder keys | 2026-09-25, this file |
| u8 | `sort_u8` | `native_u8_arr_sort` | counting sort, 256 buckets | 2026-09-25, this file |

The sections from "Why" down are the original design record, kept because
`runtime/march_runtime.c` and the tests point here. The follow-ups that were
listed as out of scope are now their own todo files (see the end). The helper
names in that record (`nsort_heap`, `nsort_net8`, `nsort_rec`) now carry a
width suffix (`nsort_heap_i64`, `nsort_heap_i32`, ...).

## What landed on 2026-09-25

### One core, two instantiations

The i64 core was written against `int64_t` directly. It is now a macro,
`NSORT_DEFINE_CORE(W, T)`, instantiated as `NSORT_DEFINE_CORE(i64, int64_t)`
and `NSORT_DEFINE_CORE(i32, int32_t)`. Every helper gets a width suffix
(`nsort_heap_i64`, `nsort_net8_i32`, ...). The two width-free pieces, the
xorshift rng and the `nsort_forced_limit` test hook, are shared. So the i32
width has the same full-run scan, equal-partition, branchless Lomuto,
`nsort_net8` network, pattern-breaking step and heapsort fallback, and it
honours `MARCH_TEST_NSORT_DEPTH_LIMIT` the same way. No part of it was copied.

The refactor does not change the i64 or f64 machine code. `runtime/march_runtime.c`
from origin/main and from this branch were compiled with clang `-O2
-fno-strict-aliasing -fwrapv` (arm64). The assembly of `nsort_i64`,
`nsort_rec`, `nsort_small`, `nsort_break_patterns`, `native_int_arr_sort` and
`native_float_arr_sort` is instruction-for-instruction identical once
comments, label numbers and the `_i64` name suffix are normalised away.

### f32: the f64 decision on 32-bit keys

    key(bits) = bits ^ (((int32_t)bits >> 31) & 0x7FFFFFFF)

compared as a signed i32 is binary32 totalOrder. Like the 64-bit key it
leaves the sign bit alone, so it is an involution. `nsort_f32` transforms in
place, runs `nsort_i32`, and transforms back. It does not widen to f64: that
would need a scratch array twice the size, and the i32 core had to exist for
`sort_i32` anyway. Placement is the same as `sort_float`:
`-NaN < -Inf < ... < -0.0 < +0.0 < ... < +Inf < +NaN`.

### u8: counting sort

With only 256 possible values, a histogram and one fill pass (`memset` per
bucket) is O(n + 256). It uses no comparisons, has no data-dependent
branches, and needs a 2 KiB stack table. The comparison core's best case on
this data is its equal-partition path, which is still O(n log k) with k = 256
and moves every element several times. Measured at n = 1M: `sort_u8` takes
0.30 ms on every pattern, against 1.8 ms for `sort_i32` on
10-distinct-value input and 12.8 ms on random input. A counting sort has no
recursion, so it has no depth limit and no heapsort fallback. The
`MARCH_TEST_NSORT_DEPTH_LIMIT` hook does not apply to it, and the u8 lines of
the golden are unchanged under the forced-heapsort run. At `rc > 1` it
counts straight from the shared original into the fresh array, with no
`memcpy` first.

### Ownership, wiring, interpreter

The ownership contract is identical to `sort_int`: the argument is owned and
consumed, sorted in place at `rc == 1`, and copied, sorted and released at
`rc > 1`. Sites touched, mirroring `sort_float`: `runtime/march_runtime.c`,
`lib/typecheck/typecheck_builtins.ml`, `lib/eval/eval_builtins.ml`,
`lib/tir/llvm_builtins.ml` (table rows and `PDeclare`), `lib/tir/defun.ml`,
`lib/tir/borrow.ml` (`extern_owned_builtins`), `lib/tir/alloc_contract.ml`,
`stdlib/native_array.march` (`sort_i32`, `sort_f32`, `sort_u8` with
doctests), `test/test_codegen.ml` (preamble golden),
`test/snapshots/{lower,perceus}/array_read_tco_loop.expected` (fn count
63 → 66), `test/dune`, `test/native/native_arr_sort_narrow.*` and
`test/refine_audit/corpus.baseline` (its two lines). `lib/tir/purity.ml` is
unchanged, because builtins are pure by default. No JIT/REPL finalizer lists
these builtins, and neither the i64 nor the f64 landing touched one.

The interpreter's f32 arm sorts on the same 32-bit key: `Int32.bits_of_float`
(exact, because the elements are already binary32 values), key,
`Int32.compare`, key back, `Int32.float_of_bits`. The i32 and u8 arms use
`Int.compare`, which is the C order on values already wrapped to their range.

## Tests (red first)

`test/native/native_arr_sort_narrow.march` mirrors `native_arr_sort.march`.
It covers the eight patterns at 13 sizes for each width: signed inputs for
i32, signed quarter-steps for f32 and the values mod 256 for u8. Each is
checked against `List.sort_by`. It adds an i32 full-range pattern that
starts at exactly -2^31, an i32 extremes line, and an u8 extremes line. For
f32 it has the specials line, `nan last`, mixed specials at 9 to 5000
elements (expected order built from kinds), and an aliasing case per width.
NaNs are named by bit pattern against the two NaNs as they come back out of
an f32 array, not against `float_nan()` itself. A binary32 round trip can
drop NaN payload bits, so `float_nan()`'s own bits are not a reliable
reference, while the sign check stays explicit this way. `test/dune` runs the file
compiled, compiled with `MARCH_TEST_NSORT_DEPTH_LIMIT=0`, and interpreted,
all against one golden.

Red evidence, all with the runtime restaged through the rule and a
`PERTURB` marker grepped in `_build/default/runtime`:

- **Before this change** the file fails at `unbound variable`, because the
  builtins do not exist.
- **All three entry points always sort in place, and `nsort_heap_*` is a
  no-op for 4-byte elements.** The plain compiled run fails on exactly the
  three `alias original intact` lines. The forced-heapsort run also fails 12
  more lines: dist10, sawtooth, organ, random and nearly for both i32 and
  f32, plus i32 full range and f32 mixed specials (1 of 5).
- **The f32 key is the identity** (raw bits compared as int32). Both
  compiled runs fail 8 f32 lines (sorted, reversed, dist10, sawtooth,
  organ, nearly, specials, mixed specials). Specials come out as
  `-0. -1. -inf -nan 0. 1. inf +nan`.
- **The interpreter's f32 arm uses OCaml `compare`.** Only the interpreted
  run goes red, on 3 lines: specials give `-nan +nan -inf ...`, `nan last`
  gives `+nan -1. 1.`, and mixed specials score 2 of 5.

After the perturbations were reverted, all six runs matched their goldens
(`native_arr_sort` and `native_arr_sort_narrow`, three ways each).

## Measurements (2026-09-25)

These come from a compiled `--opt 2` scratch program with n = 1,000,000. It
builds each width from the same list, times the sort alone, and prints the
first element as a sanity check. The box is arm64 with load average ~7. Times
are in ms; the random row is min of 3.

| pattern | `sort_int` | `sort_i32` | `sort_float` | `sort_f32` | `sort_u8` |
|---|---:|---:|---:|---:|---:|
| random | 13.2 | 12.8 | 13.5 | 12.8 | 0.29 |
| sorted | 0.29 | 0.28 | 0.70 | 0.41 | 0.30 |
| reversed | 0.48 | 0.43 | 0.85 | 0.56 | 0.30 |
| 10 distinct | 2.0 | 1.8 | 2.6 | 2.1 | 0.49 |
| sawtooth (i % 1000) | 10.1 | 9.3 | 10.5 | 9.5 | 0.30 |

i32 is only 3-10% ahead of i64. At 1M elements the core is bound by compare
and partition work, not by memory bandwidth, so halving the element size buys
little. f32 matches i32 except on the already-linear patterns, where its two
key-transform passes are most of the runtime, as with f64.
`bench/c/native_sort_bench.c` was not extended: it measures its own copy of
the algorithm, and the i32/f32 widths run the same instantiated code.

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

## Follow-ups (filed as their own todos on 2026-09-25)

These were the "out of scope" list of the original todo:

- `specs/todos/2026-09-25-native-sort-int-radix-threshold.md`: LSD radix
  behind a size threshold for random input at large n (finding 4).
- `specs/todos/2026-09-25-native-sort-natural-run-merging.md`: nearly-sorted
  input, where ipnsort is 2x behind a merge-based sort (finding 3).
- `specs/todos/2026-09-25-native-sort-rust-small-sort-network.md`: port
  Rust's `small_sort_network` for all widths at once and re-measure.
- `specs/todos/2026-09-25-array-sort-by-driftsort.md`: the stable,
  allocating sibling for `Array.sort_by` / `RRB.Vec`, plus `sort_by_key`.
