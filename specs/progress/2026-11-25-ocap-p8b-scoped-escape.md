# Object capabilities, phase 8b: scoped handles and escape checking

Plan: `specs/plans/2026-11-25-ocap-p8b-scoped-escape-plan.md` (approved by the owner
2026-11-25 with the recommended answers to Q1 to Q5). Design:
`specs/2026-11-11-ocap-capture-checking-design.md` §3, §4.4, §7, §8.1 rule 1, §16 row 8b.
Phase 8c (the public-signature rules, the stdlib migration, `forge fix`) is open in
`specs/todos/2026-11-12-ocap-capture-checking.md`.

## What it does

A handle that a function hands to a callback and closes afterwards cannot leave the callback.
`File.with_open`, `File.with_open_write` and `Socket.with_connection` mark their callback's
parameter `scoped`; a callback that lets the handle out is the build error `capture_escape`, in
`--check`, the interpreter, the REPL, `--compile` and `--target js`. Nothing else is newly
rejected.

## How it is built

- **Syntax.** `scoped` before the parameter type of a callback: `body : scoped File.Handle ->
  r`. It is a soft keyword: the token filter promotes the identifier `scoped` only when an
  upper-case name follows on the same line (`lib/parser/token_filter.ml`), so `scoped` stays an
  ordinary name (the stdlib has a parameter called it). The parser builds `Ast.TyScoped`.
- **Desugar removes it.** `desugar_fn_def_tys` takes the marker off a function parameter's
  arrow and records the attribute `scoped_param:<index>` on the function, so no later pass sees
  `TyScoped` in a well-formed program. One written anywhere else reaches the typechecker's
  surface-type conversion, which reports `scoped_misplaced`. The typechecker copies the
  attribute into `env.scoped_params` (function key to parameter indices), which travels with
  the stdlib's cached environment.
- **Tracked names.** `Capture_set.t` is now a scope part plus a list of names. No scope part
  covers a name, `IO` and `?` included; narrowing never removes one; a name prints after the
  scopes by its source label.
- **Handles carry a set.** The builtin handle types (`File.Handle`, `File.Dir`, `Socket`,
  `Listener`, `Process`) get a set variable in `Capture_ty`, as does any declared type that
  holds one. An ordinary handle's set is empty, so nothing printed in 8a changed.
- **Where a name starts.** Each use of a function in `scoped_params`, as a call or as a value,
  makes one fresh name and puts it in the set of the handle parameter of that use's callback
  type (`mark_scoped`, `lib/typecheck/capture.ml`). The existing constraint solver carries it:
  into the lambda's parameter, into a closure that captures the handle, into a record built
  around it, through a function it is passed to and back out of that function's result.
- **Names are not effects.** The variables that stand for what running a function does (`own`,
  `valv`, a scheme's `sc_val`) never receive a name, and neither does the "creates" edge from an
  inner function value to the one that creates it: calling or creating a function that holds a
  handle does not make the caller hold it.
- **Escape positions.** The callback's result type; the arguments of a builtin that keeps what
  it is given (`vault_*`, `send`, the watcher and logger registries); the arguments of
  `spawn(Actor(...))` and of `send`; an atom; the arguments of a call through a value the pass
  could not type; and the arguments of a call through a function value *of unknown origin*.
  The last is decided after solving: `Capture_set.unknown_origin` marks a function value a
  builtin returned from nowhere the pass can see, the mark travels with the set like a name,
  and a call through a marked function is an escape for a handle passed to it.
- **Finding them.** `find_escapes` reads the grounded solution (the one that also follows
  each call into the callee's own body), so a store two calls away, inside the stdlib's
  `Vault.put`, is found from the callback. A finding inside a library is reported at the
  nearest step in the program being checked. Two names for one handle (a function with a
  `scoped` parameter that passes its callback to another one) are reported once, through the
  outer use.
- **When the pass runs.** At the end of `check_module_core` and `check_module_with_env`, when
  the program typechecked and one of its own bodies (functions, module-level lets, tests,
  actor handlers, impl methods, interface defaults) names a function with a `scoped`
  parameter. A program that names none does not run the pass. On the compile path a crash in the pass is an internal compiler error through the
  driver's handler; on the editor and REPL path it is an `internal_error` diagnostic.
- **The editor path.** `check_module_with_env` records no reach bodies, so the pass also reads
  impl methods and interface default bodies from the declarations there.

## Decisions taken while building (the plan's rulings)

- `TyScoped` is removed in desugar and carried as a function attribute, instead of being
  threaded through the typechecker's types: about 130 passes match on `Ast.ty`, and none after
  desugar needs to know.
- The escape tests assert on the rendered diagnostic, not on an internal list: it is the same
  information and needs no test-only API.
- A detached-task route does not exist: the task API returns a `Task` that holds the function,
  so a task that outlives the callback is caught as a returned value. The plan's `Detached`
  route became nothing; `Registry` covers the builtins that keep a function to run later.
- A handle that reaches the result through a function used as a value (`let w =
  File.with_open`) has no source name at that point; the message says "The handle".
- Tasks 1 and 2 were implemented before their tests were run red; both were then shown red by
  switching the rule off (name covering ignored: 2 of 5 name tests fail).

## What is not covered

- `HttpClient.with_connection` hands its callback a function, not a handle:
  `specs/todos/2026-11-25-ocap-scoped-function-valued-callback-params.md`.
- The definition-site rule for a public function's handle parameters and the written form
  `(T needs h)`: `specs/todos/2026-11-25-ocap-p8c-handle-borrow-rule.md`.
- A table opened twice by name is two unrelated values to the pass, so a function value put
  through one and read through the other is not marked as of unknown origin (an 8a limit,
  `specs/todos/2026-11-24-ocap-capture-inference-precision-gaps.md`). A handle put in a table
  is rejected at the store either way.
