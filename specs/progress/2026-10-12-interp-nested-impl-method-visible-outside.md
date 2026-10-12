# Interpreter: an interface method implemented in a nested module was unbound outside it

**Date:** 2026-10-12. Found by the interpreter-vs-compiled differential sweep
(group V): `test/native/iface_collision_ambiguous_call.march` printed
`from-A` / `from-B` compiled and died `unbound variable: speak` interpreted.

## What was wrong

```march
mod Top do
  interface Speak(a) do fn speak : a -> String end
  mod NA do
    type Thing = TA
    impl Speak(Thing) do fn speak(_self) do "from-A" end end
    fn mk() do TA end
  end
  fn main(...) do println(speak(NA.mk())) end   -- interp: unbound variable: speak
end
```

The DImpl arm of `eval_decl` binds a general interface method's name to a
type dispatcher (it routes by the first argument's runtime type through the
global `iface_method_tbl`). For an impl inside a nested module that binding
lived only in the nested module's env: the DMod arm exports just the names
`declared_names` collects (fns, lets, sub-modules, externs), prefixed with the
module name. A bare `speak` in the parent or a later sibling therefore failed,
though the typechecker accepts it and compiled code dispatches it. Two tests in
`test/test_eval.ml` had documented the gap and worked around it.

## The fix

`lib/eval/eval.ml`, DMod arm: after computing the prefixed exports, also expose
every bare dispatcher (`VBuiltin` tagged `$dispatch$…`) bound in the module's
env to the enclosing env, unless the enclosing env already binds that name
(an outer impl's dispatcher is the same global-table router; a user binding is
never displaced). Nested modules chain: an inner module's dispatcher reaches
the outer module and from there its parent.

## Tests

- `test/test_eval.ml`: `interp nested impl method visible outside` (outer
  function and a later sibling module call bare `speak` on two nested impls).
- `test/native/iface_collision_ambiguous_call.march` (existing compiled
  fixture) now prints the same output interpreted.
