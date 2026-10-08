# DONE 2026-10-07: an `extern` called from (or passed as) a closure, compiled

## Symptom

A native `--compile` of a program whose lambda calls a user `extern` failed at
the clang step: `error: use of undefined value '@acc_push'` at
`%r = call i64 @acc_push(ptr %a0, i64 %a1u)`. A zero-argument extern inside a
lambda produced `store ptr @acc_new, ptr %fp..` instead. Direct (non-lambda)
extern calls worked (`test/native/ffi_resource.march`), and the interpreter ran
every variant correctly.

## Root cause: three sites

1. **`lib/tir/defun.ml`: free-variable capture.** A direct extern call is
   lowered as `ECallPtr (AVar <march_name>)`; Perceus (`env.extern_names`) and
   the emitter (`extern_map` in `emit_callptr_global`) resolve that to the
   extern's `ed_c_name`. But `collect_top_level_names` held only `tm_fns` and
   `builtin_names`, so `collect_lambdas` treated an extern named in a lambda
   body as a free variable. The closure alloc stored `@acc_push` (a
   function-pointer *value* under the March name) and the lifted apply fn
   loaded it from `$clo` and called through it. Fix: `defunctionalize` passes
   `top_level ∪ extern march names` to `collect_lambdas` only, so the lambda no
   longer captures the extern. `rewrite_expr` is unchanged and still turns the
   call into the `ECallPtr` shape a direct extern call has. Shadowing still
   works because `collect_lambdas` removes enclosing-scope bindings
   (`top_level_eff`).
2. **`lib/tir/llvm_emit.ml`: an extern as a first-class value.** Externs are
   registered in `top_fns` (`llvm_toplevel.ml`), so `List.map(xs, dbl)` takes
   the `top_fns` TFn arm of `emit_atom_raw`. That arm built the `$clo_wrap`
   trampoline around `mangle_extern v_name`, so it was `@dbl`, which nothing
   defines. The sibling raw-function-address arm did the same. A new
   `top_fn_symbol` resolves through `extern_map` first. Fix 1 exposed this
   path: without it the value case never got past the lambda bug.
3. **`lib/tir/perceus.ml`: trampoline borrow modes.** A closure call consumes
   its heap args, and a `$clo_wrap` releases the ones its target borrows
   (`Clo_flags`). Only `tm_fns` were registered, so an extern trampoline
   released nothing. `List.map([a, b], acc_total)` leaked one reference per
   element, and `List.map(words, slen)` leaked one per string. Perceus now also
   registers each extern's seeded borrow modes: a heap param is borrowed unless
   it is declared `consume`.

## Test

`test/native/ffi_extern_in_lambda.march`, run compiled AND interpreted against
one `.expected` (rules in `test/dune`). It covers an extern called in a lambda
that captures a resource, a zero-argument extern in a lambda, an Int extern
passed as a value, a resource and a `String` extern passed as values, an extern
in a nested lambda, a `consume` extern in a lambda, and a local binding that
shadows an extern's name. The last line is a `march_live_allocs` delta over 500
churns of every case.

Non-vacuousness:
- On the base compiler the fixture fails to build (`@acc_push` undefined).
- With fix 1 alone it fails on `@dbl`.
- With fix 3 perturbed (registration disabled, rebuilt), the leak line reads
  `1500`, three leaked objects per churn. With the fix it reads `0`.

`test/refine_audit/corpus.baseline` gains the fixture's two audit lines.

## Follow-up

The portable-closures branch (`claude/portable-closures`, `test/test_portable.ml`)
wraps its externs in March functions (`push`, `fresh`, `total`) to avoid this
bug. Once this lands, those wrappers can be removed.
