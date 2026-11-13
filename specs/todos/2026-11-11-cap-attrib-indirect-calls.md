# Capability attribution: authority entering through indirect calls is charged to the entry module

**Logged:** 2026-11-11 (phase 2b, Task 6 re-review)

`Cap_attrib.reach_from` (`lib/tir/cap_attrib.ml`) walks the static reverse call graph. Authority
that reaches a capability-using function only through a function value or a stdlib-internal
indirect call (an actor run by stdlib, a spawned task, a stored callback, `Socket.write` passed as
a value) has no static caller, so a lifted stdlib lambda whose host is reached that way falls back
to its own owner: the entry module. A nested module that triggers such a call can therefore rely
on the entry module's `needs` line instead of declaring its own.

This predates the host-charging fix (`specs/progress/2026-11-11-cap-attrib-stdlib-lambdas.md`),
which kept the fallback deliberately: without it, 4 cluster fixtures in `test_cap_mode_parity`
were wrongly rejected as `NetKernel` (a stdlib module, which declares nothing).

**Done when:** attribution follows the function value back to the module that created or passed
it (e.g. charge a closure's capabilities to the module that built it, tracked through Defun's
provenance), the cluster fixtures stay accepted, and a regression fixture shows a nested module
passing `Socket.write` as a value is rejected without its own `needs`.
