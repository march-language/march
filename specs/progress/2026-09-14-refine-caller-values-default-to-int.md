# `[P3]` Refinement checker: caller values of unknown sort are still declared `Int`

Filed 2026-09-14 while landing Phase 1 of the set refinements strengthening
(`specs/plans/set-refinements-strengthening-plan.md`, step 1.6). Landed
2026-09-15 per design B of `specs/2026-09-15-refinement-remaining-designs.md`.

## The problem

Datatype terms carried the instance their declared type gives, but a caller
variable passed to a parameter was still reflected at `Int` unless the callee
declared that parameter `Bool` or `Float` (`scalar_sort_of_param_ty` in
`lib/refinecheck/refine_scope.ml`, its `caller_scalar` consumer in
`lib/refinecheck/refine_call.ml`, `scalar_sort_or_int` in `refine_encode.ml`).
A `String` or datatype value reflected there met its real sort in the same VC
and the obligation was skipped as `sort-conflict`, never reported.

## Landed

One commit per origin (design step B4), each with a skip-to-proved fixture,
a REJECT twin and a type-variable control in the `caller-sorts` group of
`test/test_refinecheck.ml`:

1. **Parameters.** `Refine_encode.sort_of_tc_ty` translates a typechecker type
   into a caller sort (Int, Bool, Float, String, registered datatype; `None`
   keeps the `Int` default). `rctx.binds` records each binder's binding-site
   span, never an occurrence span, and `local_shadow` retires names from it.
   `check_call` routes by sort: a String goes to the `Str` constants
   (`reflect_set_head`, `foreign_var`, `resolve_var`'s caller fallback,
   `path_resolve_var`, the `len` path measure); Bool and Float reach
   `caller_scalar_of`. `fn p(s : String) = need_a(["a", s])` proves.
2. **`let` binders.** A block `let n = e` records its binding span.
3. **Pattern variables.** `match` arms, `let?`/`let*`, destructuring `let`s
   and pattern parameters record their binders (`pat_binder_spans`). An
   or-pattern records none, so its names stay at the `Int` default.
4. **Refinement binders.** A refined binder's scope marker supplies its sort
   when the type table has no answer or no table was passed. A caller String
   reflected by name goes through `reflect_str`, so its own refinement is
   assumed.
5. **Path-condition variables.** A registered non-record datatype named in a
   guard is the opaque datatype constant `reflect_dt` builds, with its tag
   promise loaded for the constructors the goal tests:
   `if o == p do unwrap(o)` with `p : {Option(Int) | is_Some(_)}` proves.

No call-result or constructor-payload shape reaches the default (a call is
unreflectable in a list head; `reflect_field` gives a payload its field's
sort), so those origins from the original list needed no change. Set sorts
are not routed; no caller shape reaches them today.

## Verification

- `refine-oracle.sh` over the whole corpus (345 fixtures, 7338 lines):
  identical diagnostics against a compiler built at the base; the oracle was
  shown to go red on a perturbed baseline. The new fixtures live only in the
  test suite (`caller-sorts`, 21 cases).
- CI skip ratchet on `stdlib/list.march` on a cold `.march/cas/artifacts-v2`:
  46 skipped, 30 proved in the user + stdlib slice, identical to the base
  (ceiling 46). Coverage audit: 0 unenforced.
