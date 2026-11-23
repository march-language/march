# ocap p6: grants written in a dependency's own forge.toml are not applied

Logged 2026-11-22 by ocap phase 6 (specs/plans/2026-11-22-ocap-p6-grants-plan.md, Q1 and
decision 14).

Only the root project's `forge.toml` grants. If package A's manifest grants its dependency B
something, the build ignores it: `Cmd_build.dep_grants_text` writes the root project's grants
only, and `forge audit` lists each such grant as
`grant from A's forge.toml not applied (...)` (`Cmd_audit.dc_nested_grants`).

A nested grant should hold only on calls from A into B, not on the app's own calls into B,
which the app never agreed to limit. That needs per-edge frames (a grant keyed by the calling
package as well as the callee's), a different mechanism from phase 6's per-package wrappers
(`Auth_rt.grants`), which enter the grant on every call from outside B.

What to do: design per-edge grant frames (the call site's package decides which grant is
entered), extend the grants file with a fifth field naming the granting package, apply them
in all five runtimes, and turn the audit's "not applied" note into an applied grant. Pin it
with a conformance fixture where A's grant refuses A's call into B and the app's direct call
into B is allowed.
