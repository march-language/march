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

**Dependency grants (ocap phase 6, plan decision 14).** `Auth_rt.grants` wraps a granted
package's functions the same way (`f` enters the grant around `f$grant`). Inside the package
the hop is free: a direct call from the body of a P function whose wrapper is kept targets the
callee's `$grant` body, so a tail call between kept P functions is a plain tail call with no
wrapper (as an unframed program's would be). A hop still costs a wrapper frame where the
recursion crosses the boundary: a
dropped P function (proven, unscoped) calling a kept one, a `$auth` body of a P function that
also has a framed `needs` clause (its calls keep the wrapper names), and recursion that goes
app → package → app callback → package.

**Pinned by `test/cap_conformance/grant_callback_reentry.march` (ocap p6 Task 6).**
It recurses app -> granted dep -> app callback -> dep only 1,000 deep: the kept
grant frame around `Gate.bounce` is not a tail position, so 3,000 deep already
overflows the stack compiled (`--opt 0`) and under node, while the same program
with `gate` ungranted runs 10,000 deep as tail calls. Review Focus 3 asks for
10,000: whoever lifts this limit raises the fixture's depth to 10,000.

**What Task 8 (ocap p6) adds.** A call through a kept grant frame is never a tail position:
the wrapper restores the authority after `f$grant` returns, so every crossing into a granted
package costs one stack frame, whatever the call's position in the caller. Two of the hops
listed above are also redundant work, not just stack: a dropped P function calling a kept one,
and a P function's `$auth` body calling a P wrapper, both enter a grant that is already in
force (`Authority.enter_grant` finds it and pushes nothing, so the layer list stays bounded,
but the wrapper's save, check and restore still run). Retargeting those calls to the callee's
`$grant` body would remove both costs; it is sound only where the caller's grant is certainly
in force, which for a dropped caller it is not (decision 6).
