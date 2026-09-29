# `[P3]` `NativeArray.sort_*`: Rust's small-sort network replaces `nsort_net8` + insertion (DONE, adopted, 2026-09-28)

**Filed:** 2026-09-25 as `specs/todos/2026-09-25-native-sort-rust-small-sort-network.md`
(split out of `specs/progress/2026-09-25-native-array-sort-narrow-widths.md`).
**Closed:** 2026-09-28.

## What changed

`nsort_small_W` in `NSORT_DEFINE_CORE` (`runtime/march_runtime.c`), the n <= 32
base case shared by `sort_int`, `sort_float`, `sort_i32` and `sort_f32`, used to
run `nsort_net8` on every aligned block of 8 and then one insertion pass. It now
follows Rust's `small_sort_network` (core::slice::sort::shared::smallsort):

- below 18 elements the slice is one region, otherwise each half is;
- a region is presorted by an optimal network on its first 13 elements
  (`nsort_net13`, 45 comparators) or 9 (`nsort_net9`, 25), or 8 (`nsort_net8`,
  19), then extended by insertion;
- two halves are merged branchlessly from both ends at once into a 32-slot
  stack buffer and copied back;
- below 8 elements it is plain insertion, as before.

Two deviations from Rust, both measured: Rust's 8-element region is plain
insertion, which was 5.9x slower than `net8` at n = 8 (42.0 vs 7.2 ns), so an
8-element region uses `net8`; and Rust's region setup cost 0-57% at n = 2..6
with no work to show for it, so below 8 it goes straight to insertion.

The scratch is a fixed `T buf[32]` on the stack; no heap allocation, so the
in-place contract is unchanged, and the heapsort fallback
(`MARCH_TEST_NSORT_DEPTH_LIMIT=0`) is untouched.

## Verification

In `bench/c/native_sort_bench.c`: the 0-1 principle over every 0/1 input for
the 9-network (512) and the 13-network (8192), and, because the whole routine
is not a network, every 0/1 input of `rs_small` for each n in 0..22 (both the
one-region and the two-region paths); plus the existing sweep of every sort
against qsort on 8 patterns at 30 sizes, now including 12-20 and 25-27. A new
fixture, `test/native/native_arr_sort_small.march`, checks every n in 0..40 on
five patterns for all four widths against `List.sort_by`, compiled, at depth
limit 0 and interpreted; a one-comparator perturbation of `nsort_net13` makes it
fail (199-201/205).

## Measurements (14-core Mac, load average 11-18 from other sessions)

`bench/c/native_sort_bench.c small`: each small-sort alone on random input,
~2M elements as independent n-element arrays, min of 15 alternating batches.
Summed over n = 2..32: **2753 -> 1325 ns (0.48x)**. Per n: 0.89-1.05x for
n = 2..8, 0.46-0.74x for 9..12, 0.22-0.42x at 13-15, 0.31-0.71x above.

`bench/c/native_sort_bench.c` (i64, whole sort, min of 2000/30/3 reps), ipn with
the new base case vs the shipped one:

| pattern | n = 1k | n = 100k | n = 5M |
|---|---:|---:|---:|
| random | 0.80x | 0.74x | 0.80x |
| sorted | (0 ms) | 0.96x | 0.98x |
| reversed | (0 ms) | 0.81x | 0.81x |
| nearly | 1.00x | 0.94x | 0.95x |
| dist10 | 1.00x | 0.99x | 1.01x |
| sawtooth | (0 ms) | 0.99x | 0.96x |
| organ | 0.83x | 0.85x | 0.89x |
| equal | (0 ms) | 1.00x | 0.99x |

End to end through the shipped builtin (`bench/array_sort.march`, n = 1M,
compiled `--opt 2`, same compiler with `MARCH_RUNTIME_DIR` at an origin/main copy
of `runtime/` vs this one, min of 3): random 13015 -> 10796 us (0.83x); sorted
1.00x, reversed 0.98x, equal 0.99x, dist10 0.99x, sawtooth 1.01x.

No pattern regressed, so it is adopted.
