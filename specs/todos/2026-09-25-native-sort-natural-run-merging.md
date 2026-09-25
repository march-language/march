# `[P3]` `NativeArray.sort_*`: nearly-sorted input is 2x behind a merge sort

Logged 2026-09-25, split out of the completed
`specs/progress/2026-09-25-native-array-sort-narrow-widths.md` (finding 3).

The ipnsort-style core only detects a run that spans the whole array. On
"nearly sorted" input (1% random swaps) at 5M it took 61 ms, against 40 ms
for a naive Hoare introsort. A natural-run merge (driftsort/timsort-style)
would be close to O(n) there. Accepted at landing because the gap is 2x,
where the other patterns gained 5-30x, and because run merging needs scratch
memory, which the in-place contract avoids.

Done when: a variant with run detection is measured in
`bench/c/native_sort_bench.c` against the shipped core on all nine patterns,
and it is adopted only if no other pattern regresses and the scratch cost is
acceptable.
