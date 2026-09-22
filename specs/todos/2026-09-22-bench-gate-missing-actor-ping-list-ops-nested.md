# `[P2]` bench-gate is red on main: `actor_ping` and `list_ops_nested` are in neither manifest bucket

Filed 2026-09-22. Reproduce with `./_build/default/test/test_bench_gate.exe test manifest 0`:

```
FAIL every bench/*.march is either gated or explicitly excluded
   Expected: `[]'
   Received: `["actor_ping"; "list_ops_nested"]'
```

Both benches came in with #587 (distributed-deploys groundwork G2-G7) as the
apparatus for the G1 hot-reload boundary-cost measurement, and neither was
added to `gated` or `excluded` in `test/test_bench_gate.ml`. The gate's whole
design point is that a new benchmark cannot be silently ungated, so this is the
failure working as intended — it just needs closing.

It fails the `bench-gate` job on every branch built from main, and because CI
is fail-fast it CANCELS the rest of the run, so unrelated PRs show a cancelled
CI rather than their own result.

Decide per bench: a pinned expected output in `gated` (with `IgnoreTiming` or a
`timing_value_anchors` entry if it prints wall-clock lines), or a row in
`excluded` with the reason. The G1 author knows which of these two is a
measurement harness rather than a value-checkable program.
