# Pass-site codomain witness ran capturing lambdas in the module environment

**FIXED 2026-10-06.**

`Refine_check.check_pass_sites` (lambda arm of the CODOMAIN check) decides whether an
inline lambda is closed before handing it to `Witness.with_lambda`, which evaluates the
lambda in the MODULE interpreter environment when a refuted codomain needs a witness. The
test was `List.exists (fun v -> List.mem v ctx.locals) (Witness.free_vars a)` with `a` the
whole `ELam`, but `Witness.free_vars` (built for rendering call-site examples) walks only
`EVar`/`EApp`/`ECon`/`EField`/`ETuple`, returns `[]` for an `ELam`, and skips application
heads. So every lambda counted as closed.

Effect: a lambda capturing a local was run with that local resolved against the module.
Usually that is an unbound variable, so the witness was `Unconfirmable` (the same skip the
capture path gives), which is why the existing "a capturing lambda stays silent" test
passed. But when a local shadows a module-level name the witness ran the wrong value:

```march
fn h(y : Int) : Int do 0 - 1 end
fn ap(f : (Int) -> {Int | _ > 0}, x : Int) : Int do f(x) end
fn go(h : (Int) -> Int) : Int do ap(fn y -> h(y), 1) end
```

reported a confirmed violation, "`<lambda>(0) returns -1`", computed from the module's `h`.

Fix: the capture test now uses `Refine_scope.expr_mentions_free` per local, which is
binder-aware (a lambda parameter spelled like a local is not a capture; the `ELam` arm
handles that) and counts call heads. `Witness.free_vars` is unchanged for its other callers
(`refine_call.ml` example rendering and the witness's own scope decoding).

Test: `callback-elements` "a lambda capturing a local is never run in the module
environment" in `test/test_refinecheck.ml` (failed before the fix on the shadowed-head
case; includes a control that a lambda parameter shadowing a local is still run and
rejected).
