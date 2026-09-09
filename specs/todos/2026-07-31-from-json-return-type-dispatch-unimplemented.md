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
## Scoping pass, 2026-09-08 — split into two items with very different risk

A scoping pass for this item found that the two open symptoms it covers do NOT
need the same mechanism, and should not be attempted together.

**(A) The island bridges do not need return-type dispatch at all.**
`Desugar.gen_island_bridges` (`lib/desugar/desugar.ml`) emits two BARE
`from_json` calls and relies on inference to pin each one's type. But the
generator knows STATICALLY that the first decodes to `State` and the second to
`Msg` — it only generates the bridges when both types exist and both derive
Json. Emitting a call that is unambiguous by construction fixes both backends
(the interpreter's last-derive-wins rebinding and the compiled ≥2-impl
ambiguity error) and introduces NO new dispatch mechanism, so it does not go
near `check_json_cap_sites`. Blocking question a real attempt must answer
first: `derive Json` generates `DImpl` blocks under the pseudo-interfaces
`JsonFrom`/`JsonTo`, and the interpreter name-binds only the BARE method
(last-wins) while putting the impl in `impl_tbl`; so whether a per-type
reference is expressible in the generated AST such that BOTH backends resolve
it is the thing to determine before writing any code.

**(B) True return-type-directed dispatch for user-written bare `from_json`**
is the risky half, and the capability guard is the reason. `from_json` has an
unconstrained type (`poly2 (fun a b -> TArrow (a, b))`), so
`let forged : Cap(IO) = from_json("{}")` typechecks, `--cap-strict` included.
What stops it is not the type system — it is that no dispatch can produce the
value. Implementing (B) without preserving the guard turns a compile-clean
program into a working capability forge. The guard is `check_json_cap_sites`
(`lib/typecheck/typecheck.ml`), a DEFERRED end-of-module sweep, plus
`demote_to_monomorphic` on the recorded arrow; the witness that the sweep is
still deferred is
`specs/lang/types/reject/t143_cap_from_json_deferred_zonk.march`.

(A) is worth doing on its own — it closes
`specs/todos/2026-08-12-island-bridge-from-json-broken.md`, whose feature is
100% non-functional today, without touching (B). Neither was started.
