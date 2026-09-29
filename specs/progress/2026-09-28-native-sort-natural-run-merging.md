# `[P3]` `NativeArray.sort_*`: nearly-sorted and two-run input (DONE, adopted, 2026-09-28)

**Filed:** 2026-09-25 as `specs/todos/2026-09-25-native-sort-natural-run-merging.md`
(split out of `specs/progress/2026-09-25-native-array-sort-narrow-widths.md`,
finding 3: nearly-sorted input at 5M took 61 ms, a naive introsort 40 ms).
**Closed:** 2026-09-28.

## What was tried, in order (`bench/c/native_sort_bench.c`)

1. **General natural-run merging (`ipnrun`, kept in the harness).** Split the
   array into its natural runs and, if they average at least `RUN_MIN_AVG`
   elements, merge them bottom-up through an n-word buffer (each merge trimmed:
   the prefix/suffix already in place is copied). It won organ-pipe (4x) but
   **lost** badly where the todo wanted a win: the "nearly" pattern (1% random
   swaps) has natural runs of ~25 elements, so the merge has ~18 levels
   (2.1x-2.5x slower than ipn), and sawtooth's 1000-long runs interleave
   completely (2.5x-3.2x slower). Not adopted.
2. **Presorted front end (`ipnpre`, adopted).** Two cheap checks after the
   existing full-run scan, for n >= 1024:
   - **two runs**: if the rest of the array after the first run (the scan
     already found where it ends) is one more run, ascending or strictly
     descending, merge the two in place: trim the prefix of the left run
     that is <= the right's head and the suffix of the right run that is >=
     the left's tail, then merge the overlap through a buffer the size of the
     smaller trimmed run (<= n/2). More runs than two were measured (up to 16)
     and lost on sawtooth (1.29x at 10k with 10 runs).
   - **nearly sorted**: if the first 64 elements have at most 4 descents,
     stream the array once, keeping a sorted main sequence compacted in place
     and moving each element that breaks it into a buffer of at most n/16.
     A large value can be kept by mistake when the element after it is itself
     out of place; every later element would then look low. So when an
     element is below the last kept one but fits after up to 8 kept elements
     are dropped (and its successor fits after it), those are evicted
     instead. The first version without eviction gave up on the real
     "nearly" pattern at 100k and 5M; with single eviction it still cascaded
     when two misfits were adjacent. The pass gives up as soon as the outlier
     rate passes 1/16 after 256 elements, writing the moved elements back
     into the gap they left (exactly k slots for k moved), so the array is
     still a permutation and the quicksort sorts it. On success the outliers
     are sorted and merged back from the end in O(n).
   - anything else, or an allocation failure: the unchanged quicksort.

## Measurements (`nsb pre`: ipnpre / ipn, alternating, min of 21 / 15 / 9 reps; small n batched)

Load average 15-19 (other sessions); noise floor about +-3% (sorted/reversed
never reach the new code and read 0.97-1.00x).

| n | random | sorted | reversed | nearly | dist10 | sawtooth | organ | equal |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 256 | 1.00 | 0.98 | 0.98 | 1.00 | 0.99 | 0.98 | 1.01 | 0.99 |
| 1,000 | 1.00 | 1.00 | 0.97 | 1.00 | 1.01 | 1.00 | 1.00 | 0.99 |
| 10,000 | 1.00 | 1.00 | 0.99 | **0.20** | 1.00 | 1.02 | **0.32** | 0.99 |
| 100,000 | 1.00 | 0.99 | 0.99 | **0.17** | 1.00 | 1.00 | **0.25** | 1.00 |
| 1,000,000 | 1.00 | 1.00 | 1.00 | **0.15** | 0.99 | 1.00 | **0.21** | 1.00 |
| 5,000,000 | 1.00 | 1.00 | 0.99 | **0.14** | 0.99 | 1.02 | **0.19** | 1.01 |

At 5M the nearly-sorted case goes from ~60 ms to ~8 ms, now well ahead of the
naive introsort's 40 ms that motivated the todo.

End to end through the shipped builtin (`NativeArray.sort_int`, compiled
`--opt 2`, n = 1M, same compiler with `MARCH_RUNTIME_DIR` at an origin/main copy
of `runtime/` vs this one, min of 15): nearly-sorted 11,629 -> 1,736 us (0.15x),
organ 12,044 -> 2,569 us (0.21x), random 12,948 -> 12,836 us.
`bench/array_sort.march` (min of 3): random 13,087 / 13,244, sorted 295 / 283,
reversed 486 / 478, equal 279 / 280, dist10 1,976 / 2,012, sawtooth 10,266 /
10,390 us (base / new; all within 2%).

## Scratch

Two runs: at most the smaller trimmed run (<= n/2 elements); nearly sorted: at
most n/16 elements. Both are `malloc`, freed before returning, and a failed
allocation falls back to the in-place quicksort, so the result never depends
on it. Every other input allocates nothing, as before.

## Tests

- Harness: `verify` now also runs `verify_pre` (two interleaved ascending
  halves, descending+descending, descending+ascending, a single far outlier,
  duplicate-heavy nearly-sorted, at sizes 1024-100000), plus the existing sweep
  of every sort against qsort.
- New fixture `test/native/native_arr_sort_presorted.march`: 10 shapes x 4 sizes
  (1024-5000; the new code starts at 1024, beyond native_arr_sort's sizes)
  x all four widths against `List.sort_by`, compiled, at depth limit 0 and
  interpreted. Perturbing `nsort_merge2` (drop the left-over copy) fails it
  24/40; perturbing the eviction (move one element too few) fails it 34/40.
  Sizes stay at or below 5000: at 20,000 the fixture's own March-side
  reference code overflows the green-thread stack compiled, on origin/main's
  runtime too.
- `native_arr_sort` and `native_arr_sort_narrow` goldens still match compiled,
  at depth limit 0 and interpreted.
