# ocap: a tail call out of a framed `restrict` body is not a tail call

Logged 2026-11-19 by ocap phase 5 (specs/plans/2026-11-19-ocap-p5-restrict-plan.md,
decision 10).

A `restrict` block that keeps its run-time frame (a scoped or computed entry, or a block that
reaches a spawn or a call of a function value; `Auth_rt.restricts` in `lib/tir/auth_rt.ml`) is
lowered to `enter_fn(layer)`, the body, then `cap_restore`. A call in tail position inside the
body is therefore followed by the restore and is not a tail call. Re-entering the same restrict
while its layer is on top pushes nothing (decision 8), so the authority's layer list stays
bounded, but the native stack grows by one frame per hop: a self-recursion through a kept
restrict (`fn countdown(n) do restrict IO.FileRead("/srv/") do ... countdown(n - 1) end end`)
overflows a compiled binary's green-thread stack between 20,000 and 30,000 deep (measured
2026-11-21, `--opt 2`, macOS arm64: 20,000 runs, 30,000 dies with SIGBUS in the stack guard
page), where the same function without the `restrict` runs 1,000,000 deep as a loop.
`test/cap_conformance/restrict_reenter_noop` pins 1,000 deep (at `--opt 0` and under node,
10,000 already overflows, as a plain non-tail recursion does there).

The phase-4 analogue for function frames is solved for self tail calls (retargeted to the
`$auth` body) and open for mutual ones (`specs/todos/2026-11-17-ocap-framed-mutual-tail-recursion.md`).

What to do: when the tail call's target re-enters the same restrict (same `where` and text on
top, which `top_is_frame` already detects), retarget it past the entry so the recursion stays a
loop; or make the restore a continuation the callee inherits, which would fix the mutual
function-frame case as well. Raise `restrict_reenter_noop` to 100,000 deep once it holds.
