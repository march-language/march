# Shell: the policy gates proof capabilities again (Actor.Debug, Actor.Introspect)

Logged 2026-10-08. Found by the `--force` work (its branch filed
`specs/todos/2026-10-07-shell-policy-ignores-proof-caps.md`); a regression
from R5.6 (#862).

Before R5.6 the client declared the caps of the pre-bound names an input
used (`debug` gave `Actor.Debug`). R5.6 replaced that with the caps of the C
symbols the fragment's code calls (`Cap_symbols`), plus `cap_of_call` for code
called on the node. `Actor.Debug` and `Actor.Introspect` are proof
capabilities: holding the `Cap` value is the authority, and no runtime symbol
carries them. So they dropped out of the manifest, and a policy listing only
`IO.Console` let `Actor.inspect_state(debug, …)` run, audited `caps:"-"`.

## Fix (`lib/jit/repl_jit.ml`, `shell_compile`)

The manifest also declares every `Cap(C)` found, at any depth, in the type
of a parameter or a `let`- or case-bound variable of any function the input
reaches. A `Cap` value only reaches code by being passed down from the
input's pre-bound names or a session binding holding one, so this covers
what the input can exercise. It can over-declare, which only refuses more.

The root `Cap(IO)` is not counted. It appears only where the client narrows
it into a pre-bound name (`Actor.introspect(root_cap)`), and an input that
mentions `root_cap` is refused.

## Tests

`test/shell/skew.txt` (node policy: `IO.Console` only) gains
`Actor.inspect_state(debug, …)` and `Actor.list(intro)`. They are refused
with `policy Actor.Debug` and `policy Actor.Introspect`; on main they ran.
The session test, whose policy lists both, is unchanged.
