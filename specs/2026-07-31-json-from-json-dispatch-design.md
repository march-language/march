# `from_json` return-type dispatch — design (future work, not scheduled)

**Status:** draft, **not part of any active plan**. Recorded so the bug is
tracked and scoped, not lost. Do not start without a fresh scoping pass.

**Date:** 2026-07-31

## The bug

`derive Json for T` binds a bare top-level `from_json`, and when two types in
one module both derive it, the *second* declaration's `from_json` silently
replaces the first — every call from the first type's code now decodes into
the wrong type. Found and reproduced (with a minimal 2-type repro) during
`specs/plans/2026-07-31-json-typed-decoding.md` Task 1;
see `specs/2026-07-31-derive-json-capability-map.md`.

## Why this is a different problem than `to_json`, and harder

`derive Eq`/`Show`/`Ord`/`Hash` generate a proper `DImpl`
(`lib/desugar/desugar.ml:1195`, `impl_one`), dispatched through the
compiler's `impl_tbl : (iface, type) -> value` at runtime
(`lib/eval/eval.ml:278`) — keyed by the *argument's* runtime type. `derive
Json` does not: it generates bare `DFn`s, and the typechecker binds
`from_json`/`to_json` as fully generic `∀a b. a -> b`
(`lib/typecheck/typecheck.ml:1921`) with a comment claiming "runtime
dispatches via `impl_tbl`" that is simply false — no `impl_tbl` entry is ever
created for either.

`to_json(x : T) : JsonValue` can be fixed the same way `Eq` was: the argument
has a known runtime type, so it can dispatch through `impl_tbl` exactly like
`Eq`/`Show`. That fix is tracked as Task 2 of the typed-decoding plan above.

`from_json(v : JsonValue) : Result(T, ...)` cannot use the same mechanism.
There is no value of type `T` to dispatch on — `T` is known only from the
*caller's expected type*, at compile time. `impl_tbl` dispatches on a runtime
value; it has nothing to dispatch on here. The correct fix is closer to
**monomorphization**: resolve each `from_json` call site to a concrete,
per-type specialization based on the type inferred for it, the way generic
functions are already specialized elsewhere in this compiler's `mono` pass.

There is a partial, confusing precedent worth investigating first rather than
assuming a from-scratch design: `impl_iface.txt` starting with `"Json"` is
checked specially in at least four places
(`lib/eval/eval.ml:9551`, `lib/typecheck/typecheck.ml:9756,9842`), suggesting
a "Json-family pseudo-interface" bookkeeping path already exists for
typechecking purposes, separate from `derive Json`'s actual codegen. Whether
that machinery is reusable, a dead end, or actually for something else
(hand-written `impl Json for T` blocks, a distinct feature) is unknown and
should be the first thing a real scoping pass determines.

## Non-goals for this note

This is a problem statement, not a plan. It does not commit to monomorphizing
`from_json`, to a specific mechanism, or to a timeline. A real design pass
should first answer: does the typechecker already know the concrete `T` at
each `from_json` call site (it must, to type-check the result) in a form the
desugar/mono pipeline can act on before codegen — or does that information
arrive too late in the pipeline to help.

## Interim guidance

Until this is fixed, any code deriving Json for more than one type in one
module must not rely on bare `from_json` calls resolving correctly per type.
`specs/plans/2026-07-31-json-typed-decoding.md`'s test files work around it
with an explicit convention: capture each type's decode result via a
top-level `let` placed immediately after that type's own `derive Json`,
before the next type's `derive Json` rebinds the name.
