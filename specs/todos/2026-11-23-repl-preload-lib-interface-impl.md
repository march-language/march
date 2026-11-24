# The REPL's preload does not see an interface declared in a library module

Logged 2026-11-23 by the ocap phase 6 final whole-branch review, while adding
test/cap_conformance/grant_default_method.

`march repl FILE` (both modes) loads FILE's declarations, but an `impl` in FILE of an
interface declared in a `MARCH_LIB_PATH` module (`impl Greet(Mine)`, with `Greet` in
`Loudy`) is `unknown_interface`, and calls of its methods are `unbound_variable`. The same
file runs with `march FILE`, `--jit`, `--compile` and `--target js`. Functions and types of
library modules are visible to the preload; interfaces are not.

grant_default_method is listed in `repl_unsupported` (test/run_cap_conformance.ml) because of
it.

What to do: make the REPL's preload register library modules' interfaces (and their
defaults) before it checks FILE's impls, then drop the fixture from `repl_unsupported`.
