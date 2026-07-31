# A refinement in an `interface` method signature no longer enforces nothing silently

Landed 2026-07-30.

**At landing:** `test_refinecheck` 387 (was 383, +4 `interface-signature-refinement`
tests). Typing corpus 240/240 (was 238/238, +1 accept `t137`, +1 reject `t138`). `run_compiler`
619, `run_codegen` 520, `run_eval` 256, `run_snapshots` 33, `run_stdlib` 826
with only the pre-existing environmental `MARCH_SANITIZE` failure, grammar
corpus 45/45 — all unchanged.

**What changed.** A refinement written in an `interface` method signature —
`fn run : a -> {Int | _ > 0} -> Int` — parses, typechecks, and is never read.
Nothing in `lib/refinecheck` consults `A.method_decl`'s `md_ty`: the pass's
`DInterface` arm in `visit_decl` descends only into `md_default`, and the two
other walks that touch `iface_methods` (`stdlib_member_defs_ok`,
`bare_builtin_undefined`) read method NAMES only. Nor does the front end carry
it: `Desugar.inject_defaults` synthesises a default method's `fn_def` with
`fn_ret_ty = None` and parameters taken from the default LAMBDA, which carry no
`param_ty`, so the one path where an interface signature becomes code drops the
predicate. The result obliges no call site AND lets no body assume anything — a
*missing* check rather than an unsound one, but silent, which is the failure
mode this area keeps producing.

`warn_predicate_decls`' `DInterface` arm now calls a new
`warn_iface_method_refinement` when `ty_has_refinement m.md_ty` holds.
Detection is the full type traversal, not just the arrow spine: a refinement
nested in a type argument, tuple, record field or linearity wrapper is equally
inert, and `ty_has_refinement` mirrors `warn_predicate_ty`'s recursion exactly
so the two cannot drift.

**The remedy is stated for both positions, on purpose.** The plan's wording was
"the `impl`-parameter spelling", which would be wrong advice for a
return-position refinement, and incomplete for a parameter one. The message
names the `impl` method's *own signature* and then splits: a RETURN refinement
there is always checked (`visit_fn` calls `check_fn_post` unconditionally),
while a PARAMETER refinement is enforced only when `adoptable_impl_methods`
adopts the name (exactly one `impl` defines it, no top-level `fn` owns it) —
otherwise `visit_decl` walks the body with the refinements stripped and no
caller is obliged. Saying "put it on the impl parameter" flatly would send an
author with an ambiguous method name from one silent no-op to another.

The advice was verified end-to-end rather than reasoned about: the typechecker
*accepts* a refined `impl` parameter against a plain type in the interface
signature (exit 0), and the resulting contract really is enforced —
`bump(Box(1), 0 - 5)` is a `refinement violation` error. `accept/t137` carries
both halves, the inert interface signature and the working `impl` spelling.

**One suppression.** When the signature carries a refinement the arm no longer
also runs `warn_predicate_ty` over it. That warning's remedy is "annotate the
function `@[measure]`", which cannot help on a signature nothing reads:
following it would leave the contract enforcing nothing just the same. A
misleading remedy costs more here than a missing one, and the vocabulary
warning still fires once the predicate is moved to the `impl` method, which is
where it can act.

**Warning, not error — deliberate,** for the same reason as the
qualified-spelling warning: the shape compiles today, and the defect is the
silence, not the lack of capability. Making an interface signature actually
enforce would have to oblige every call dispatched through the interface and
check it against every `impl`; that stays open in `specs/todos.md`, which
narrows the item rather than closing it.

**Sweep.** 0 of 111 stdlib modules warn — stated only because the same grep
returns 1 on a deliberately-refined probe. The stdlib declares no `interface`
at all today (the seven `interface` hits in `stdlib/` are all comments), so the
positive control is doing all the work in that number.

**Non-vacuity.** Verified by reverting `refine_check.ml` alone against the kept
tests: both warning cases FAILED pre-fix, and both false-positive controls (an
unrefined interface signature, and a refinement on an `impl` method) passed on
both sides.
