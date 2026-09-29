# `[P3]` `NativeArray.sort_int`: LSD radix sort behind a size threshold (CLOSED, measured, not adopted, 2026-09-28)

**Filed:** 2026-09-25 as `specs/todos/2026-09-25-native-sort-int-radix-threshold.md`
(split out of `specs/progress/2026-09-25-native-array-sort-narrow-widths.md`,
finding 4). **Closed:** 2026-09-28 without a runtime change.

## Question

Radix measured 1.8x faster than the shipped ipnsort-style core on random input
at n = 5M, and much slower on ordered input. Is there a size threshold above
which switching to radix, after the full-run scan has already ruled out wholly
sorted and wholly descending input, wins on random input with **no loss on any
other pattern**?

## What was measured (`bench/c/native_sort_bench.c`)

The harness's `radix` recomputes a histogram per digit: eight read passes before
the first scatter, which is most of why it lost so badly on ordered and
low-cardinality input. A new `radix1` builds all eight 256-bucket histograms in
one read pass and scatters only the non-trivial digits (a digit every key
shares moves nothing): a 10-distinct-value input costs one read and one
scatter. Its scratch is n words plus 16 KiB of counts; `radix1_i64` returns
false on allocation failure, and `sort_radix1` then falls back to the in-place
sort.

`nsb sweep` (new) times `radix1` against the shipped `ipn` on every pattern that
survives the full-run scan (sorted, reversed and equal never reach the
sort), at 14 sizes, alternating order, min of max(3, 2e7/n) reps (capped at
3000). Ratio radix1 / ipn, below 1 = radix faster; 14-core Mac, load average
9-11:

| n | random | nearly | dist10 | sawtooth | organ |
|---:|---:|---:|---:|---:|---:|
| 256 | 2.00 | 1.00 | inf | inf | 1.00 |
| 512 | 2.00 | 1.00 | 2.00 | inf | 1.00 |
| 1,024 | 1.20 | 0.80 | 1.50 | 0.60 | 0.67 |
| 2,048 | 1.00 | 0.46 | 1.67 | 0.43 | 0.50 |
| 4,096 | 0.74 | 0.41 | 1.57 | 0.39 | 0.40 |
| 8,192 | 0.78 | 0.42 | 1.83 | 0.41 | 0.39 |
| 16,384 | 0.74 | 0.41 | 1.73 | 0.52 | 0.40 |
| 32,768 | 0.62 | 0.49 | 1.57 | 0.57 | 0.51 |
| 65,536 | 0.57 | 0.54 | 1.54 | 0.64 | 0.63 |
| 131,072 | 0.52 | 0.98 | 1.57 | 0.65 | 0.89 |
| 262,144 | 0.49 | 1.02 | 1.39 | 0.68 | 1.10 |
| 524,288 | 0.52 | 1.23 | 1.53 | 0.69 | 1.26 |
| 1,048,576 | 0.48 | 1.38 | 1.60 | 0.69 | 1.24 |
| 5,000,000 | 0.45 | 0.96 | 1.49 | 0.38 | 0.86 |

("inf" / tiny sizes: ipn measured 0.000 ms.) The default table at 5M, absolute
ms: random ipn 70.9 / radix1 34.5; dist10 9.3 / 14.4; nearly 60.7 / 58.3;
organ 65.2 / 55.6; sawtooth 38.6 / 17.0.

## Verdict: not adopted

- **dist10 loses at every size** (1.39x-1.83x). ipn's equal-partition step turns
  a k-distinct-value array into roughly O(n log k); radix pays at least one full
  read, one scatter, a copy-back and the scratch allocation's first-touch page
  faults, which is more than that at every n measured. No threshold avoids it,
  and this does not depend on the key width, so i32/f32 were not pursued.
- nearly-sorted and organ-pipe also lose between 131k and 1M (up to 1.38x),
  once the scatter's 256 output streams fall out of cache.

A version gated on a cardinality or presortedness estimate could avoid those
cases, but that is a second heuristic on top of the threshold, and each cost
it adds would itself need measuring. Nothing in the runtime changed.
`radix1` and `nsb sweep` stay in the harness so the question can be re-asked
cheaply.
