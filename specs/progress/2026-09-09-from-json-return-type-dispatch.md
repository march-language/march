# `from_json` return-type-directed dispatch

**Filed:** 2026-07-31 (`specs/todos/2026-07-31-from-json-return-type-dispatch-unimplemented.md`)
**Design note:** `specs/2026-07-31-json-from-json-dispatch-design.md`
**Landed:** 2026-09-09

## What was wrong

`from_json` dispatches on its RESULT type. Every implementation takes the same
`JsonValue` argument, so nothing among the values at a call site says which
decoder to run — only the type the caller expects does, and that is known to
the typechecker alone.

- **Interpreted:** `derive Json` binds the bare name `from_json` in the
  environment, so the LAST type to derive Json in a module owned it. Every
  earlier type's decode silently ran the wrong decoder and returned a
  `DecodeError` that looked exactly like bad input.
- **Compiled:** `Mono.return_position_single_impl` could resolve only the case
  where exactly ONE `JsonFrom` impl existed module-wide. With two, the program
  failed to build: "ambiguous interface-method call to `from_json`".

Its most visible casualty was `derive Json`'s auto-generated island bridges,
which are generated only for a module that has BOTH a `State` and a `Msg`
deriving Json — that is, only in the configuration that guaranteed the bug.
`update_json` always fell through to its `_ -> state_json` arm and returned its
input unchanged, silently
(`specs/todos/2026-08-12-island-bridge-from-json-broken.md`).

## How it resolves

The design note asked the right question first: does the typechecker know the
concrete `T` at each call site, in a form the rest of the pipeline can act on?
It does, and the mechanism was already built — for the security check.

`Typecheck_caps.check_json_cap_sites` is a DEFERRED end-of-module sweep over
every recorded JSON builtin application, holding the instantiated arrow. By the
time it runs, unification has solved the result type. The same sweep now also
resolves the dispatch target from that solved type and records it per call-site
span (`March_ast.Json_dispatch`). Both backends read that one answer:

- `Lower_expr` rewrites the callee to the impl's mangled symbol
  (`JsonFrom$T.from_json`), so everything downstream sees an ordinary direct
  call and Mono's single-impl fallback is no longer load-bearing.
- `Eval` takes the impl straight out of `impl_tbl ("JsonFrom", T)` instead of
  the shadowed environment binding.

**A side table rather than a rewritten AST.** Returning a rewritten module from
`check_module` would oblige every entry point — the driver's several pipelines,
forge, the LSP, the REPL JIT — to feed the NEW module to the backend, and one
that forgot would keep the old, silently-wrong dispatch. A table every consumer
already reaches is picked up everywhere by construction. It is process-global
and reset at `check_module_core` entry, because a REPL fragment, an LSP
re-check and a multi-file build are each their own check.

## The capability guard: what was required, and what was done

The todo's warning was the governing constraint. `from_json` has an
unconstrained type (`poly2 (fun a b -> TArrow (a, b))`), and what limited its
blast radius was that it could not actually produce a value at run time.
Implementing dispatch removes that limit, so the type-level guard is now the
only thing between a compile-clean program and a working capability forge.

The resolution is written INSIDE the guard's clean branch, deriving the target
from the very same solved type `cap_in_solved_ty` just cleared. A dispatch
target therefore cannot be derived from a type the capability check did not
see, and the ordering is structural rather than a convention a later edit can
drift away from.

Unchanged, deliberately: the sweep stays DEFERRED (the witness that it is,
`specs/lang/types/reject/t143_cap_from_json_deferred_zonk.march`, still
rejects with its exact expected text), and `demote_to_monomorphic` stays on the
recorded arrow. The trade the todo flagged — needing `from_json` to stay
polymorphic at a binding — did not arise: a single application still resolves
at a single result type, which is all dispatch needs.

Second, independent barrier: `derive Json` refuses outright to generate a codec
for a type with a capability anywhere in it, so no `JsonFrom$T.from_json`
exists for such a T and a resolved dispatch has nothing to reach.

Three forge attempts were tried against the built compiler and all three are
refused: a bare `Cap(IO)` result, a capability hidden in a record FIELD of an
otherwise ordinary type, and the deferred-zonk shape of t143. The first two are
pinned in `test/test_cap_unforgeable.ml`, asserting the forge DIAGNOSTIC rather
than merely that something failed — that harness typechecks with no stdlib in
scope, so a test written with `Json.parse` in it passes on the unknown-name
error alone and would keep passing with the capability check deleted. Both were
confirmed to go RED with the guard disabled, and the accompanying accept case
(two decodes at two types, no capability) stayed green, so they cannot be
satisfied by a check that refuses everything.

## Two things this needed that were not obvious

**Named records solve structurally.** A `type Point = { x : Int, y : Int }`
reaches the sweep as `TRecord [x; y]`, not as `TCon ("Point", _)` — the same
thing Mono works around with `record_to_typename`. The target is recovered by
matching solved field names against `env.records`. One declaration is
registered under both its bare and its module-qualified name, so the raw
candidate list is never a singleton; collapsing to short names first is what
makes it resolve. Two genuinely different record types with the same field
names still collapse to two names and stay unresolved.

**The island bridges shared one span.** `gen_island_bridges` stamped a single
span on every node it generated, so `update_json`'s two `from_json` calls — one
decoding `State`, one decoding `Msg` — were indistinguishable to any
span-keyed table: the second recording overwrote the first and both decoded as
the same type, reproducing the original bug through the new mechanism. The
generated decls now go through `Desugar_derive.respan_derived_decl`, the same
uniquifier derive-generated code already used, which turns a latent
diagnostics-quality issue into the correctness requirement it now is.

## Degradation

A call whose result type nothing pins records nothing and behaves exactly as
before: resolved by Mono's single-impl fallback if only one impl is in scope,
and reported as ambiguous if not. It never guesses.

## Tests

- `test/native/from_json_dispatch.march` — three `derive Json` types, decodes at
  three different types plus a repeat of the FIRST-derived type LAST so
  declaration order cannot be what makes it work. `.expected` is the
  interpreter's output, so the rule is an interpreter/compiled parity diff.
- `test/stdlib/test_island_bridges.march` — was held out of CI because 7 of its
  tests exercised a feature that could not work in either execution path. Now
  161/161, and wired into `test/dune`.
- `test/test_cap_unforgeable.ml` — the three cases described above.
