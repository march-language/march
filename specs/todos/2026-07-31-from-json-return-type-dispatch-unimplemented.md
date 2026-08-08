- [ ] **`from_json`'s return-type-directed dispatch is unimplemented — bare `from_json` resolves to whichever type derived Json last in a module, not the caller's target type.** Unlike `to_json` (fixed 2026-07-31 by adding `("JsonTo", "to_json")` to `is_type_dispatched_method`, `lib/eval/eval.ml`), there is no value of the target type in hand at a `from_json` call site to dispatch on the same way — the type is known only from the expected/annotated return type, which today's `impl_tbl` lookup does not consult. `derive Json for T`'s generated `from_json` unconditionally rebinds the bare name each time a type derives Json in a module, so calling `from_json` after two derived types in the same module silently decodes as the LAST one, not the caller's intended type. `from_json_events` (added 2026-07-31 for record types) inherits the identical caveat, by design. Fixing this needs return-type-directed monomorphization/dispatch. Full problem statement, prior-art survey, and design options: `specs/2026-07-31-json-from-json-dispatch-design.md`.

**Capability guard, added 2026-08-05 — do not regress it when implementing
this.** Until now, one thing limiting the blast radius of `from_json`'s
unconstrained type (`poly2 (fun a b -> TArrow (a, b))`) was that it could not
actually produce a value at run time. `let forged : Cap(IO) = from_json("{}")`
typechecked — `--cap-strict` included — and was stopped only by the very
dispatch this item proposes to build. Implementing return-type-directed
dispatch without a type-level guard would have turned a compile-clean program
into a working capability forge.

That guard now exists (`check_json_cap_sites` in
`lib/typecheck/typecheck.ml`, plus the `derive Json` rejection in
`lib/desugar/desugar.ml`; see
`specs/progress/2026-08-05-cap-unforgeability.md`), so this item is safe to
implement. Two things it depends on, both easy to break by accident:

**Compiled-backend status update, 2026-08-08** (see
`specs/progress/2026-08-08-from-json-native-ice-single-impl-and-diagnostic.md`):
the native backend now resolves a bare `from_json` when exactly ONE
`JsonFrom` impl is in scope (`Mono.return_position_single_impl` — the
argument-type-matches-impl-parameter proof), and rejects the ≥2-impl case
with a clean "ambiguous interface-method call" diagnostic (exit 1) instead
of the former ICE/linker error. The interpreter's last-derive-wins rebinding
is unchanged. This item — true return-type-directed dispatch so the ≥2 case
can RESOLVE instead of erroring — remains open.

- the check is a **deferred end-of-module sweep**, not a call-site check,
  because the result var is usually pinned by later unification. Making it
  eager silently disables it — `specs/lang/types/reject/t143_cap_from_json_deferred_zonk.march`
  is the witness.
- `demote_to_monomorphic` on the recorded arrow is what stops `let x =
  from_json(s)` from generalizing past the sweep. If return-type dispatch
  needs `from_json` to stay polymorphic at a binding, that trade has to be
  made deliberately and the capability check re-secured another way.
