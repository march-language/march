# Known_call's self-binding rule assumes `$clo` is never shadowed — guard it

Filed 2026-08-22 while landing
`specs/progress/2026-08-22-selfrec-closure-float-tail-call.md`. Small, and
purely defensive — nothing is known to be broken.

## The assumption

`Known_call.go` now carries the traversed function's `($clo parameter name,
own name)` and treats `let v = $clo` inside an apply fn as binding `v` to that
apply fn, so the self-call becomes a direct `EApp` and gets TCO'd. The
traversal recurses into `ELetRec` function bodies and `ECase` branch bodies
with that pair still set.

That is correct as long as no inner binder REBINDS the name `$clo`. If one
ever did, `let v = $clo` in that inner scope would name a *different* closure
and the rewrite would dispatch the call to the WRONG apply function — a
compiled-only miscompile of the kind this codebase has been bitten by
repeatedly (`specs/progress/2026-08-19-actor-handler-binder-shadowing.md` is
the same shape).

No such shadow exists today: defun's apply fns are top-level, and the
`ELetRec` groups that survive to codegen (join points, mutual-recursion
groups) take ordinary value parameters. So this is an observation about the
current pipeline standing in for an invariant.

## The guard

Clear the pair whenever a binder rebinds that name — a `shadowing` helper
applied at the `ELet` binder, `ELetRec` parameters and `ECase` branch vars.
It can only ever REMOVE a resolution, i.e. return that call to its
pre-2026-08-22 behaviour, so it cannot introduce a miscompile; the only thing
to check is that it does not remove the one we want.

## Verification (cheap, and exact)

One measurement decides it: `test/native/native_float_box_abi_leak_probe.march`
must still report a `live_allocs` delta of **1**. If the guard accidentally
disabled the self-binding rule, `selfrec_leg` re-leaks and the delta becomes
~1,000,001 — a 6-order-of-magnitude signal, not a judgement call. Follow with
`run_codegen` and the 71-program corpus sweep.

Written and reviewed but NOT landed in the original commit: the build lock was
held by a full `@runtest` on a box at load 60 and shipping it unmeasured would
have been worse than shipping without it.
