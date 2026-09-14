# `[P2]` Codegen: a user function named `own` with two arguments is miscompiled as the resource-registration builtin

Found 2026-09-13 while writing `test/session/stream_actor_supervised.march`.

## The bug

`lib/tir/lower_expr.ml` (the `own(pid, value)` special case, ~l.657) rewrites
**any** application whose callee variable is named `own` and has exactly two
arguments into `register_resource(pid, "drop_<Type>", fn _ -> Drop$<Type>.drop(value))`.
It matches on the bare name, not on resolution to the builtin, so a user's
own `fn own(ep : Int, p) : () do … end` called as `own(2, pc)` lowers to a
call of `Drop$Pid.drop`, which does not exist:

```
stream_actor_supervised.ll:15988:13: error: use of undefined value '@Drop$Pid.drop'
march: clang failed (exit 1)
```

`--check` passes, the interpreter runs the program correctly, and only the
compiled backend fails — at link time, with a message that names nothing the
user wrote. A user `fn own` with any other arity (the callback fixture's
three-argument one) is untouched, which is why it went unnoticed.

Same family as `specs/…/defun-capture-shadowing` (a user name colliding with
a compiler-known one): name-based dispatch in lowering.

## What to build

- Gate the special case on the callee resolving to the builtin (not a
  user-declared function in scope), the way `resolve_iface_method` is
  consulted for interface dispatch just above it — or on the value's type
  actually having a `Drop` impl, failing loudly at lowering otherwise.
- Witness: a program with `fn own(a : Int, b : Int) : Int do a + b end` that
  compiles and runs on both backends; today it fails to link.
- Sweep `lower_expr.ml` for other bare-name special cases with the same shape.
