# `[P3]` `Array.sort_by` / `RRB.Vec` sort: stable driftsort, and `sort_by_key`

Logged 2026-09-25, split out of the completed
`specs/progress/2026-09-25-native-array-sort-narrow-widths.md`.

The NativeArray sorts are unstable and in place, and they take no comparator.
That is right for bare scalars, where stability cannot be observed. The
persistent `Array`/`RRB.Vec` needs the other shape. Its elements carry
payloads and it takes a user comparator, so it needs a stable sort: unpack
to a flat buffer, run a driftsort with the closure comparator, and rebuild
in bulk.

`sort_by_key` with a closure is a separate trap. A closure call per compare
(through `clo_call_int_int_int`) would erase most of the win. Instead,
extract the keys once into a parallel array and sort (index, key) pairs.
