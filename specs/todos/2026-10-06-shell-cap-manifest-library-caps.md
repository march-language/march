# Shell: declare the caps a fragment reaches through library code

Logged 2026-10-06 (observe plan R5.6).

`march --shell` declares the capabilities of a fragment from the pre-bound
cap names its input mentions (`console`, `clock`, `intro`, `debug`). A
fragment that reaches a capability through program or library code declares
nothing. For example, `Connection.connect(..)` from Depot opens a socket
(`IO.NetConnect`) and draws randomness for SCRAM (`IO.Random`). The node then
audits `caps:"-"`, and the `$MARCH_SHELL_POLICY` check passes no matter what
the policy lists.

Fix: compute the fragment's transitive cap set the way the typechecker's
module-caps pass does for a `main` (`typecheck_modcaps`), send that set as
`caps:`, and have the node check it against the policy. A test should cover
a fragment calling a program fn that needs `IO.NetConnect` under a policy
without it, and expect `ERR policy IO.NetConnect`.
