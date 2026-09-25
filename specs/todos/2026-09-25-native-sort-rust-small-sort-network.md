# `[P3]` `NativeArray.sort_*`: measure Rust's small-sort network against `nsort_net8`

Logged 2026-09-25, split out of the completed
`specs/progress/2026-09-25-native-array-sort-narrow-widths.md`.

The small-sort base case (n <= 32) is `nsort_net8_W`, a Knuth 5.3.4
19-comparator 8-element network followed by one insertion pass. Rust's
ipnsort uses a larger `small_sort_network` layer, which is where part of its
lead on random input comes from. Since the core is now one macro
(`NSORT_DEFINE_CORE`) instantiated for i64 and i32, a replacement changes all
four comparison widths at once. The widths must not be mixed.

Done when: the port is verified by the 0-1 principle (exhaustive 0/1 inputs)
in the harness, measured against `nsort_net8` on random input at several
sizes, and adopted or rejected on that measurement.
