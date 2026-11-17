# ocap p4: known gaps in function-value capture

Logged with Task 5 of specs/plans/2026-11-15-ocap-p4-runtime-plan.md
(specs/progress/2026-11-16-ocap-p4-function-value-capture.md). In each, a function value
can run under a wider caller authority than it was made under.

- **REPL JIT, the precompiled stdlib.** `lib/jit/repl_jit.ml` runs the capture pass
  on the stdlib shared object (`~fragment:false`) only when that module has a frame
  (never, today), because that object registers no closure drops
  (`march_clo_drops_register`) and a captured self-recursive helper's environment
  (`$authbodyN`, e.g. in prelude `map`) leaked one object per call
  (`test_jit` "REPL fragments leak nothing"). So in the REPL a stdlib lambda runs under
  its caller's authority; one that escapes and does IO would differ from a compiled
  program with frames. Fix: register the stdlib object's closure drops, then pass
  `~repl:true` there too.
- **REPL JIT, earlier fragments' fns.** `Auth_rt.captures` judges a fn by the module it
  sees, so a lambda whose only authority-dependent call is to an earlier fragment's fn
  is not captured, and such a fn used as a value is not eta-wrapped: either runs under
  its caller's authority. Capturing on every call of a name the fragment lacks was
  tried: interface methods (`show`) are such names too, and the captured
  self-recursive helpers that made leaked one object per input in the REPL, whose
  fragments register no closure drops (`test_jit` "REPL fragments leak nothing").
  Fix: let the JIT pass the names of earlier fragments' fns, or register fragment
  closure drops.
- **A self-recursive lambda that is a case branch's value inside a `let` right-hand
  side.** Its helper closure `$authbodyN` is bound in the branch; when the result is
  only called (a borrowing environment, `Borrow.closure_escapes`), the helper's own
  captures can leak. Rare shape; a leak, never a double release.
- **Top-level lets.** The compiled pipeline re-evaluates an entry-module let in each fn
  that uses it, so a value made by a function the initialiser calls captures that fn's
  authority; the interpreter evaluates the let once, under the launch authority. Values
  written directly in the initialiser capture nothing in both.
- **REPL JIT.** The conformance suite's REPL mode runs the interpreter engine only
  (specs/todos/2026-11-17-repl-jit-runs-no-conformance-fixture.md), so none of the
  REPL JIT items above is pinned by it. (The interpreter REPL's prompt `let` captured
  nothing, as module-level code does; Task 7 fixed it: `Eval.eval_prompt_decl`.)
- **Interpreter: a default-argument fn read as a value.** Such a fn is bound as a
  `VMultiarity` (arity-dispatched closures), which `Eval.capture_named_value` does not
  wrap, so passed as a value it runs under its caller's authority.
- **Interpreter: a `use`/alias spelling read as a value.** `capture_named_value` wraps
  a named fn only when the variable's text is the fn's name (or ends in `.NAME`), so a
  fn read through an alias runs under its caller's authority.
