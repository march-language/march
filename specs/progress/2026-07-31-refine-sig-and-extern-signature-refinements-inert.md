**A refinement in a `sig` or `extern` signature is silently inert.** — SHIPPED
2026-07-31. Now a warning; still not enforced (deliberately).

## The defect

```march
mod SR1 do
  sig Store do
    fn put : Int -> {Int | _ > 0}
  end
  fn main() : Int do 0 end
end
```

`--check` exited 0 with *zero* diagnostics. Same for an `extern`:

```march
mod SR2 do
  needs IO.Foreign

  extern "c" : Cap(IO.Foreign) do
    fn take(n : {Int | _ > 0}) : Int = "take"
  end
  fn main() : Int do 0 end
end
```

`A.DSig` carries `sig_fns : (name * ty) list` and `A.DExtern` carries
`extern_fn`'s `ef_params`/`ef_ret_ty`, any of which can hold a `TyRefine`, but
`warn_predicate_decls` (`lib/refinecheck/refine_check.ml`) walked neither —
both sat in the "not walked" list under the label *"inert: no type annotation
or expression that can carry a refinement predicate"*. #146 corrected that
comment (it was load-bearing and false) without closing the hole.

Same shape as the `interface`-method-signature case made loud on 2026-07-30:
it parses, typechecks, reads exactly like a working contract, and enforces
nothing. The concrete failure was an author reading the new `interface`
warning, moving the contract into a `sig`, and getting silence again.

## What shipped

`DSig` and `DExtern` moved out of the "not walked" list into their own arms of
`warn_predicate_decls`, mirroring the `DInterface` arm's either/or: emit the
inert-signature warning when `ty_has_refinement` holds, otherwise run the
ordinary `warn_predicate_ty` vocabulary walk (running both would append
"annotate the function `@[measure]`" to a position where no annotation can
help).

Two new emitters, `warn_sig_fn_refinement` and `warn_extern_fn_refinement`.
**The messages differ on purpose** — reusing the `interface` one, or a single
shared message, would give wrong advice in at least one position:

- **`sig`** is merely *unread*. A `sig` is an ascription: it constrains what a
  module exports, not what any function body does, so there is no `fn_def` for
  the predicate to attach to and no call site that consults it. A missing
  check, not an unsound one. Remedy: the module's own `fn` definition, where a
  parameter refinement obliges callers and a return refinement is discharged
  against the body.
- **`extern`** is unverifiable *in principle*, not merely unwalked. The callee
  is foreign C: there is no March body to discharge a return claim against, and
  assuming it would be **unsound** rather than merely missing. So the remedy
  cannot be "move it somewhere it gets checked" — it is a March wrapper
  carrying the *parameter* refinement (where call sites really are obliged),
  with the foreign *result* checked at runtime rather than asserted in a type.

Both `ef_params` and `ef_ret_ty` are walked; they are separate fields and a
detector covering only one would be silent on the other. The return-position
case has its own test for exactly that reason.

## Scope: a warning, not enforcement

Deliberate. These shapes compile today and the defect is the *silence*.
Promoting either to a hard error would break code that compiles now; making a
`sig` ascription or an FFI boundary actually *enforce* a refinement is a much
larger question and remains open. `specs/lang/types/accept/t140` is an
`accept/` witness whose **exit code is the content** — it guards against doing
either by accident.

## Evidence

- RED proven by file-copy revert (never `git stash`): 3 `[FAIL]`, 2 controls
  `[OK]`. GREEN after: 5/5 `[OK]`. `test_refinecheck` 409 → 414, zero `[SKIP]`
  (z3 4.15.4 present — a skip reads as a pass and would have proven nothing).
- Stdlib sweep for the warning text: **0 hits** across `stdlib/*.march`, with a
  **positive control returning 1 each** on the two probe fixtures. A zero-hit
  sweep whose instrument never fires is not evidence.
- `t140` emits 3 warnings and stays exit 0. Its enforced contrast
  (`fn clamp(n : {Int | _ > 0})`) mutation-verified: `clamp(0)` is a real
  `refinement violation`.

## Plan defects found

Two, both in the plan's Task 3 as written:

1. **The suggested test helper was wrong.** `refine_error_text_d` filters to
   `Error` severity, so `msg <> ""` would have been **false on both sides** of
   a fix that ships a *warning* — a vacuous test pinning nothing. The suite
   asserts over `ctx.diagnostics` directly instead, matching the existing
   `iface_refine_suite`.
2. **The `extern` fixture did not compile.** `Cap(IO.FileSystem)` with no
   `needs` is rejected by two hard cap errors before refinecheck runs.
   Corrected to `needs IO.Foreign` + `Cap(IO.Foreign)`, matching
   `specs/lang/types/accept/t139`.
