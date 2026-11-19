# ocap: mutually tail-recursive framed functions grow the stack

Logged 2026-11-17 by ocap phase 4 (specs/plans/2026-11-15-ocap-p4-runtime-plan.md, decision 7).

A framed function (a scoped `needs` clause, or one that reaches a spawn or a call of a function
value) is a wrapper around `f$auth` (`lib/tir/auth_rt.ml`). Its own self tail calls are
retargeted to `f$auth`, so they stay a loop. A tail call to another framed function goes
through that function's wrapper, which enters its frame, calls, then restores: not a tail
call. Two framed functions that tail-call each other therefore use one stack frame per hop,
and a long enough mutual recursion overflows the green-thread stack where the unframed program
would not.

What to do: retarget a tail call between framed functions whose frames are already in force
(the same clause on top) to the callee's `$auth` body, or make the wrapper's restore a
continuation the callee's tail call can inherit. `test/cap_conformance/frame_reenter_noop`
pins the self-recursive case; add a mutual one.
