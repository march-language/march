# `NativeArray.sort_int` — ipnsort-style in-place sort in the C runtime

Landed 2026-09-16. Design, measurements and the remaining four element widths:
`specs/progress/2026-09-25-native-array-sort-narrow-widths.md`.

## What landed

`NativeArray.sort_int` (i64 only). Unstable, in place when the array is
uniquely owned, no scratch allocation. Implemented as `native_int_arr_sort` in
`runtime/march_runtime.c` with no comparator crossing the closure boundary.

Before this, NativeArray had no sort at all, and the only sorts in the tree
were `stdlib/sort.march`'s list sorts over cons cells — which do not apply to a
flat numeric array.

Four pieces carry the speed, and the input patterns in the test map one-to-one
onto them:

- a top-level full-run scan, so sorted and reversed input are O(n);
- an equal-partition when a chosen pivot equals its ancestor, so
  low-cardinality input is near-linear;
- branchless Lomuto partitioning, which clang lowers to `csel`;
- an 8-element sorting network as the small-sort base case, below n = 32
  (`nsort_net8`, a classic Knuth 5.3.4 network written from the technique, not
  a port of Rust's more elaborate `small_sort_network`; verified exhaustively
  by the 0-1 principle, 0/256 failures).

A heapsort fallback at depth `2·log2(n)` bounds the worst case.

## Measurements

Harness `bench/c/native_sort_bench.c` (four sorts × eight patterns × three
sizes; every timed run is `memcmp`'d against libc `qsort`). At n = 5,000,000 the
ipnsort-style sort beats libc `qsort` 5–30x on seven of eight patterns and a
naive introsort 2.5–35x. Sorted input 15.3 → 1.4 ms, reversed 68.4 → 2.3 ms,
ten distinct values 56.1 → 9.2 ms, random 431 → 71 ms. The full tables are in
the todo.

## Two things worth keeping

**Fixed-stride pivot sampling is defeated by periodic input.** The first
prototype took 337 ms on `i % 1000` at 5M: the period divides the `n/8` sample
stride, so all nine samples read the same value, every pivot was the segment
minimum, and the depth limit dumped the whole array into heapsort. pdqsort's
pattern-breaking step (on a lopsided partition, swap four elements at the
sample positions with xorshift-chosen positions) brought it to 38–97 ms. The
seed is derived from the length rather than a clock, so a given input always
takes the same path.

**A runtime perturbation test can be vacuous and report green.** Verifying the
aliasing case meant forcing the in-place path unconditionally and expecting the
test to redden. It did not — because `dune build --root . bin/main.exe` does
**not** restage `_build/default/runtime`, which is the tree the driver actually
compiles, so the perturbation was never in the build. After restaging via a
rule with a runtime dep, the `alias original intact` line flipped to false and
nothing else moved, which is what makes that case non-vacuous. Confirm the
staged copy changed before believing any perturbation result.

## Ownership

`native_int_arr_sort` follows `native_int_arr_set`'s FBIP/COW contract exactly:
the argument is owned and consumed, so at `rc == 1` it sorts in place and
returns the same pointer, and at `rc > 1` it sorts a fresh copy and releases
its own reference. `test/native/native_arr_sort.march`'s `alias original
intact` line is the only case that fails if the `rc > 1` branch is dropped.

## Sites touched

`runtime/march_runtime.c`, `lib/typecheck/typecheck_builtins.ml`,
`lib/eval/eval_builtins.ml`, `lib/tir/llvm_builtins.ml` (table entry **and**
the `PDeclare` list), `lib/tir/defun.ml`, `lib/tir/borrow.ml`
(`extern_owned_builtins`), `lib/tir/alloc_contract.ml`,
`stdlib/native_array.march`, `test/test_codegen.ml` (the byte-identical golden
preamble, which the new `PDeclare` reddens in a suite unrelated to the change),
`test/dune` + `test/native/native_arr_sort.{march,expected}`.

## Not done

The other four widths (f64, f32, i32, u8). f64 and f32 need the NaN decision
recorded in the todo: compare by IEEE 754 `totalOrder` key so the i64 path is
reused verbatim and NaN placement is identical between the interpreter and the
compiled backend. u8 should be a counting sort rather than a quicksort.
