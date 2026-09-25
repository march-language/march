# `[P3]` `NativeArray.sort_int`: LSD radix sort behind a size threshold

Logged 2026-09-25, split out of the completed
`specs/progress/2026-09-25-native-array-sort-narrow-widths.md` (finding 4).

At n = 5M, `bench/c/native_sort_bench.c` measured an LSD radix sort 1.8x
faster than the shipped ipnsort-style core on random input (39 vs 71 ms), and
2x faster on 10-distinct-value input. It lost on every ordered pattern, by up
to 46x, and it needs an O(n) scratch buffer plus a signed-to-unsigned key
transform. So it can only be a second algorithm, chosen after the full-run
scan has ruled out sorted and reversed input, above a size threshold measured
per width. Candidates are i64/f64 first, then i32/f32 on the same keys. u8 is
already a counting sort.

Done when: the harness gets a threshold sweep, a width switches only where
the sweep shows a win on random input with no loss on the ordered patterns,
and the scratch allocation's failure path is defined.
