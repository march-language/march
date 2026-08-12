# Benchmark `test/stdlib/test_properties.march` and fold into `dune runtest`

Filed alongside `specs/progress/2026-08-11-test-stdlib-march-files-not-in-ci.md`
(the completed audit that wired 35 of the 37 previously-unwired
`test/stdlib/*.march` files into `dune runtest`, plus
`specs/todos/2026-08-12-island-bridge-from-json-broken.md` for the one file
excluded due to a real compiler bug).

`test/stdlib/test_properties.march` is the third file left out of that wiring
— not because it fails (all 228 tests pass), but because its true runtime is
unknown. It has 76 `Check.all` property calls (100 samples each by default),
generating and round-tripping nested Msgpack/JSON values through the
tree-walking interpreter. A full run took **several hours** on a machine with
roughly 8 other concurrent compiler sessions contending for CPU — but that
number is contaminated by load (see `project_bench_load_contamination` in
repo memory for why concurrent sessions on a shared dev machine make timing
numbers meaningless) and says nothing about a clean CI runner.

It is currently wired under its own dune alias, not `runtest`:

```bash
dune build --root . @test/stdlib-march-properties
```

## What to do

1. Run it on an otherwise-idle machine (or a CI runner) and get a real
   wall-clock number.
2. If it's fast (seconds to low tens of seconds) — move its rule from the
   `stdlib-march-properties` alias to `runtest` in `test/dune`, alongside the
   other 35 files wired in the block above it.
3. If it's genuinely slow — decide deliberately whether it belongs in the
   nightly/quarantine tier (see `.github/workflows/nightly.yml`, which already
   hosts tests quarantined out of `dune runtest`) rather than leaving it as an
   easy-to-forget manual-only alias indefinitely.
