# 37 of 94 `test/stdlib/*.march` files wired into CI

37 of the 94 files in `test/stdlib/` had real, substantial `describe`/`test`
coverage (237 `describe` blocks) but ran under no automated runner — only
manually, via `march test test/stdlib/<f>.march`:

```
actor, array, bigint, bytes, check, cli, csv, dataframe, datetime, decimal,
derive_json, derive_json_multi, dir, enum, file, gen, hamt, html, iolist,
island_bridges, iterable, map, math, option, path, plot, prelude,
properties, queue, regex, result, set, sigil, sort, string, string_utf8,
task
```

## What was found on audit

Running each of the 37 through `march test` surfaced real drift, accumulated
because none of it was CI-enforced:

- **5 files** (`test_map.march`, `test_set.march`, `test_hamt.march`,
  `test_iterable.march`, `test_enum.march`) called their module's `fold` with
  the arguments in the wrong order (e.g. `Map.fold(zero, coll, f)` instead of
  the actual `Map.fold(coll, zero, f)`), and in `test_map.march`'s case also
  used a curried lambda where the callback is actually called uncurried.
  Fixed by correcting each call site to the real signature.
- **`test_properties.march`** had a parser trap: a match arm body ending in a
  multi-line `&&` expression whose final operand was itself a lambda whose
  body was a `match` with a tuple pattern confused the arm-boundary lookahead
  (`I was expecting -> in the match arm`). Reproduced with a small repro,
  worked around by hoisting the two operands into `let` bindings before the
  `&&` (functionally identical, avoids the ambiguous parse shape).
- **`test_derive_json.march`** hit an already-documented compiler limitation
  (`specs/2026-07-31-json-from-json-dispatch-design.md`): when 2+ types
  `derive Json` in one module, the bare `from_json` name is rebound by each
  `derive Json` in turn, so only the *last* type's decoder is ever reachable.
  Fixed per that doc's interim guidance — capture each type's `from_json`
  result in a top-level `let` immediately after that type's own `derive
  Json`, before the next type's `derive Json` shadows the name.
- **`test_island_bridges.march`** hit the *same* root cause, but in the
  compiler's own auto-generated `update_json`/`render_json` island-bridge
  functions rather than in test code — which cannot be worked around from a
  test file, since the generated function bodies aren't test-authored. This
  turned out to be a distinct, more severe discovery: the island-bridge
  feature (`lib/desugar/desugar.ml:2601`, `gen_island_bridges`) is
  unconditionally broken for its own advertised trigger condition (a module
  with both `State` and `Msg` deriving Json) in *both* the interpreted path
  (silently returns the input unchanged) and the compiled path (hard
  ambiguous-dispatch compile error). Filed as
  `specs/todos/2026-08-12-island-bridge-from-json-broken.md`; this one file
  is left out of the CI wiring below pending that fix.

All other files passed as-is.

## Wiring

`test/dune` gained one `(rule (alias runtest) ...)` per file for 35 of the 37
(everything except `test_island_bridges.march`, excluded per above), each
running `march test test/stdlib/<f>.march` and judged by exit code — so a
regression in any of them now fails `dune runtest` (which CI's `test` job
already runs) instead of requiring anyone to remember to run the file by
hand.

`test_properties.march` (36th file, passes 228/228) was wired to a separate
`stdlib-march-properties` alias rather than `runtest`: its 76 `Check.all`
property runs took several hours on a machine with ~8 other concurrent
compiler sessions contending for CPU, and its real (uncontended) runtime is
unmeasured. Folding a multi-hour test into every PR's default `dune runtest`
without knowing that number first would be worse than leaving it out for now.
Follow-up filed: `specs/todos/2026-08-12-benchmark-wire-test-properties-march.md`.

## Net result

35 of the 37 files are now enforced by `dune runtest`. One (`test_properties`)
is enforced on-demand pending a runtime benchmark. One
(`test_island_bridges`) stays manual-only pending a real compiler fix to a
newly-discovered, tracked bug — running it now demonstrates the bug rather
than silently hiding it.
