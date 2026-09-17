# The benchmark output gate: 17 unaccounted benches, and it never ran

Landed 2026-09-16.

## What was wrong

`test/test_bench_gate.ml` compiles every gated `bench/*.march` with `--opt 2`,
runs it, and checks the value it prints. It exists because three benchmarks
(`tree_transform`, `iolist_template`, `string_pipeline`) were silently broken
for weeks — two of them crashing with SIGBUS — and nothing noticed, because
benchmarks are not part of `runtest`.

Its own `test_manifest_is_exhaustive` check is supposed to stop the gate from
rotting: adding a benchmark without gating it should fail by name. Two things
defeated that.

**The `bench_gate` dune alias was referenced by no workflow and no script.**
Nothing ever ran it, so its failure was invisible. It had been failing for
long enough that **17 benchmarks** had drifted out of the manifest:
`json_stream`, `json_stream_strings`, `list_producers`,
`scratch_string_memmem`, the five `simd_*`, `steady_state_ring`, six
`string_*`, and `vector_math`.

**`IgnoreTiming` with no anchors is not a gate.** The mode does not compare the
`expected` string at all; it requires each anchor in `timing_value_anchors` to
appear in the output. An entry with no anchor list therefore asserted only
"printed something non-empty". `array_numeric` and `dataframe_bench` were both
in that state — gated in name, with no value coverage whatsoever.

## What landed

All 17 are now accounted for: 6 as `Exact` (a single stable checksum line) and
11 as `IgnoreTiming` with value anchors. `array_numeric` and `dataframe_bench`
gained the anchors they never had.

Every value was **captured from a real run**, never written from memory — the
file's own header records two entries that were once invented and were wrong.
Each benchmark was then run a second time and the two outputs diffed: the 6
`Exact` candidates were byte-identical, and in all 11 timing-bearing ones
**only** the timing lines differed, which is what makes the anchors safe. No
anchor is a measurement: no `*_TIME_MS`, no `MIN_NS`/`MAX_NS`, no latency
`BUCKET` counts, no per-worker `ms`. `MIN_NS` in particular happened to match
across both runs and is still excluded, because matching twice is not being
deterministic.

A new check, `test_ignore_timing_entries_have_anchors`, makes an anchorless
`IgnoreTiming` entry a failure instead of a silent hole, and also rejects an
anchor list naming a bench that is not gated. Verified non-vacuous by deleting
one anchor list: it fails naming `simd_sum`.

The alias is now wired into CI, in the `conformance` job alongside the other
slow-lane checks that are "not part of runtest". The full gate is ~72 s locally
for 43 benchmarks, compile-dominated.

## Floats and cross-platform pinning

Anchors on fractional floats are deliberately truncated. A multiply-add
contracted on one target and not another moves the low digits, so pinning them
buys a flake that reproduces nowhere rather than coverage. `vector_math` prints
`6853874.21103` and is anchored on `6853874`; `simd_kernels`'
`DOT_COMPOSED_RESULT` and `PARITY_CHECKSUM` are treated the same way. Values
that are exactly representable (`51.5`, `49500.`, `9950000.`) are anchored in
full. A real miscompile moves these numbers grossly, not in the tenths.

`vector_math` is in the `IgnoreTiming` block despite printing no timing at all,
because that mode is really "substring anchors, everything else free", which is
what a float needs. That naming is now noted at both sites.

## Not done

`strip_timings` masks digits *before* an `ms` suffix (`[0-9]+ *ms`). It
therefore does not normalise `ms=326`, `TIME_MS 10.118`, or a microsecond
(`us`) suffix. Widening it was considered and **rejected**: every timing-bearing
bench here is pinned by anchors instead, which is the stronger check, so the
masker's only remaining job is the non-empty guard. Widening a masker to eat
more digit patterns risks masking a legitimate value, for no benefit today.
The limitation is now written where a future reader will hit it.
