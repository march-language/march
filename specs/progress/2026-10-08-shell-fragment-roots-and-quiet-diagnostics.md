# Shell: prune from the fragment's entry only; print errors only at attach

Logged 2026-10-08. Found attaching the shell to forgepm (a real project).

## 1. Every input carried every `main` in the program

`Dce.prune_unreachable` roots at every function named `main` or `*.main`.
A shell fragment is lowered together with its program, and forgepm's library
modules each declare a `main` (forge task modules: `Forge.BuildIslands`,
file/process tooling). So `1 + 41` kept 196 functions, declared
`IO.FileRead`, `IO.FileWrite` and `IO.Process`, and the node's policy refused
it.

`Dce.prune_unreachable`/`reachable_fns`/`root_names` take `?roots`, replacing
the defaults (`tm_exports` still added). The shell's three prunes pass
`~roots:[ shell_entry_fn ]`. After the change the same session declares
`-` for `1 + 41` and `Actor.Introspect` for `Actor.list(intro)`.

Tests (`test_codegen.ml`, suite `prune_roots`): default roots keep every
`main`; `~roots` keeps the entry and what it reaches only; `tm_exports`
stay roots. Without `?roots` the suite does not compile, so the pre-fix
code cannot satisfy it.

## 2. Attach printed the whole program's warnings

The driver prints every user-file diagnostic before handing off to
`--shell`. For forgepm that was screens of refinement hints. Under `--shell`
only errors print now: they stop the session; the rest is the build's
business.
