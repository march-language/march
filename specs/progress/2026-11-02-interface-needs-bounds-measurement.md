# Interface `needs` bounds: built-in interface measurement (2026-11-02)

Plan: `specs/plans/2026-11-02-interface-needs-bounds.md`, Task 4. Question: what breaks if
the four built-in interfaces (`Show`, `Eq`, `Ord`, `Hash`) declare `needs ()`?

## Method

A local patch set `needs ()` on all four in `mk_builtin_iface`, then `march --check` ran,
under a private `HOME`, over:

- every `.march` under `stdlib/`, `test/`, `examples/`, `bench/` and `specs/lang/` that
  hand-writes an `impl` of one of the four or uses `derive` (83 files; `test/errors/` and
  `specs/lang/grammar/reject/` excluded as deliberately broken);
- every `.march` in the sibling apps `conduit` and `test_conduit_app` (56 files), with
  `MARCH_LIB_PATH` set to their `lib/` and `src/`.

## Result

- **0** `cap_bound` diagnostics against a built-in interface.
- 58 hand-written impls of the four exist in the repo; the sibling apps have none.
- 10 of them live in `stdlib/prelude.march`, `stdlib/list.march` and
  `stdlib/msgpack.march`, which fail `--check` standalone for unrelated reasons (a stdlib
  file checked alone); their bodies contain no I/O call.
- Positive control: a hand-written `impl Show(T)` that calls `println` is rejected, with
  the chain `(via println)`.

## Finding: the dispatch-union cascade

The first control run reported the impure impl AND every generic impl of `Show`
(`Show($Tuple2)`, `Show($Tuple3)`, …), because a generic impl reaches every impl through
the method's dispatch node. Fixed in the same branch (commit "report an interface bound
violation once, where it is"): bounds are judged against rows solved without edges into a
violating impl or default body. Callers' rows are unchanged. Pinned by
`test_iface_violation_reported_once`.

## Decision and cost

Decided 2026-11-02: all four built-ins declare `needs ()`. An error against a built-in's
bound is reported at the impl method (a built-in has no source span) and says "built-in
interface". Every program now has bound points (the stdlib's impls), which turns on the
full row solve that phase 1 ran only when a bound existed; measured `--check` wall time,
median of 5 interleaved runs per program, private `HOME` and fresh cwd each run:

| program | before | after |
|---|---|---|
| examples/actors.march | 0.042 s | 0.040 s |
| bench/binary_trees.march | 0.042 s | 0.042 s |
| stdlib/json.march | 0.047 s | 0.047 s |
| test/stdlib/test_actor.march | 0.043 s | 0.040 s |

No measurable change.
