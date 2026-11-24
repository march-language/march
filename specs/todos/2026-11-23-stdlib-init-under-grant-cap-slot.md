# ocap p6: a stdlib module first used inside a grant frame initialises under the narrowed slot

Logged 2026-11-23 by the ocap phase 6 final whole-branch review (M5). Found by reading the
code; not reproduced.

The interpreter loads a stdlib module on demand, at its first use. When that first use
happens inside a granted package's frame (a package function, or its module-level code),
`Eval.with_module_grant` runs the stdlib module's initialisers with `init_grant` cleared (a
function value they make is not the package's), but leaves `Eval_builtins.cap_slot` as it
is: the caller's authority intersected with the grant. A stdlib module-level `let` whose
initialiser needs a capability (opening a handle, reading the environment) would then be
refused, and the module's value would keep that refusal for the rest of the run, cached,
whoever uses the module next. Compiled code initialises module-level values at start-up,
under the launch authority, so the backends would disagree.

No stdlib module-level initialiser performs a capability operation today, which is why
nothing fails.

What to do: run a stdlib module's initialisers under the launch authority (save the slot,
install the launch layers, restore), as compiled start-up does; add a test whose granted
package is the first user of a stdlib module with an effectful initialiser (a test-only
module, if the stdlib has none).
