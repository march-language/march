# Bench gate: gate the two G1 benches #587 added ungated

Landed 2026-09-22.

## What was wrong

#587 (`12c062761`, distributed-deploys groundwork) added two benchmarks for the
G1 hot-reload boundary-cost measurement, `bench/actor_ping.march` and
`bench/list_ops_nested.march`, without adding either to the manifest in
`test/test_bench_gate.ml`. `test_manifest_is_exhaustive` did exactly what it
exists to do and failed by name:

```
Expected: `[]'
Received: `["actor_ping"; "list_ops_nested"]'
```

Because the failure was on main, every open PR that merged main went red on the
`bench-gate` job (seen on #588 and #593) with nothing to do with its own diff.

## What landed

Both are gated `Exact`, with values captured from three `--opt 2` runs each
(all identical, all exit 0), not taken from the bench headers:

- `list_ops_nested` → `333333666666`, the same answer as `list_ops`, which it
  is a copy of with the helpers moved into a nested module.
- `actor_ping` → `1000000`. The printed number is the count of handled
  messages; `wait_done` loops until every message has landed, so the value does
  not depend on scheduler interleaving (the header records an earlier version
  that printed 730492 when it trusted `run_until_idle` alone).

## Prevention

Nothing new: the manifest check already turns a forgotten bench into a named
failure. The gap was that #587 merged with that failure showing. When adding a
file under `bench/`, run `dune build --root . @bench_gate` (or wait for the
`bench-gate` job) before merging.
