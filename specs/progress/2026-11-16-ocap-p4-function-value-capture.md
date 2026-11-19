# ocap phase 4: function values capture the authority they were made under

Plan: specs/plans/2026-11-15-ocap-p4-runtime-plan.md, Task 5.

A function value runs under the authority in force where it was made, not where it
is called (design §5). A value made by module-level code captures nothing and runs
under its caller's authority (design §21).

## Compiled (`Auth_rt.captures`, lib/tir/auth_rt.ml)

- Runs right after `Auth_rt.frames` in every compiled pipeline: bin/main.ml (native
  and JS), `lib/driver/js_pipeline.ml` (`~repl:false`), `lib/jit/repl_jit.ml`
  (`~repl:fragment`: a REPL fragment runs the pass even with no frame of its own,
  since its lambda can be called by a later fragment's framed fn; the precompiled
  stdlib object does not, see specs/todos/2026-11-16-ocap-p4-capture-gaps.md).
- With no frame and not the REPL it returns the module physically unchanged: every
  slot holds the launch authority, so a capture would change nothing. A no-frame
  program's IR is byte-identical (bench/list_ops.march `--emit-llvm` compared).
- Otherwise, a lambda (`ELetRec([fd], fd)`, `FnLambda`) captures when its body reaches,
  through direct calls, `Authority.check`, a `Cap_ops` `Checked` builtin or an actor
  spawn, or calls a function value (which may be an uncaptured module-level value).
  Its body becomes
  `let s = cap_enter($c) in let r = body in cap_restore(s); r`.
- `$c = cap_save()` is bound once at the top of the body that makes the value, not in
  the value's own `let` right-hand side: a closure that is only called borrows its
  captures (`Borrow.closure_escapes`), and a reference whose scope ended at the
  allocation was never released (seen with `--rc-trace`: one leaked slot list per
  creation).
- A self-recursive lambda (a local `fn go`) whose name is used only as a direct callee
  keeps its self tail call: its body moves to an uncaptured lambda `$authbodyN` and
  the captured `go` only enters `$c` around one call of it. Without this a
  `deep(1000000)` loop overflowed the stack.
- A named fn used as a value (an `AVar` outside callee position) that depends on the
  authority, or a capability builtin, becomes a captured eta lambda `$authlamN`.
- Not captured: lambdas lowered outside any function (`Lower_state` records them),
  the right-hand sides of the entry module's top-level lets (their `Tir.var` binders,
  matched physically after folding), and the zero-arg fns other modules' lets lower
  to.
- March has no partial application (the typechecker rejects a short call), so the
  plan's "partial application" case is the explicit eta lambda `fn p -> File.read(p)`.

## Interpreter (lib/eval/eval.ml)

- `VClosure` gains a 5th field, `value option`: `Some slot` for an `ELam` or local
  `fn` made outside module-initialiser code, `None` otherwise (and for a named fn's
  per-call closure). `apply_inner` installs `Some a` around the body when
  `a != !cap_slot`.
- `module_init` is set while a module-level `let` initialiser runs and cleared inside
  any function it calls, so only values made by the initialiser itself capture
  nothing, as in the compiled pass.
- A named fn (`<rec:NAME/ARITY>`) or a builtin read by its own name outside callee
  position is wrapped to run under the authority in force where it was read.

## Tests

- `test/test_auth_rt.ml` group `auth_rt_capture`: identity without frames (`==`), a
  lambda calling `println` captured and `fn x -> x + 1` not, `List.map(xs, File.read)`
  as a capturing eta lambda, `fn p -> File.read(p)` captured, module-level values
  uncaptured, the REPL capturing without frames.
- `auth_rt_runtime`: one program in interp, `--jit`, compiled and JS: values made in
  `main` and in framed fns, a named fn returned from a framed fn, module-level values.
  `test_fn_value_every_runtime` now passes module-level values (a named fn passed
  from `main` carries `main`'s authority since this change).
- TIR snapshot `auth_capture` (lower and perceus).
