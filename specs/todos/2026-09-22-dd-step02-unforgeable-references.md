# `[P1]` Distributed deploys, build step 2: unforgeable local references (`Actor.Introspect`)

**Parent:** [../plans/2026-09-21-distributed-authority-and-deploys-plan.md](../plans/2026-09-21-distributed-authority-and-deploys-plan.md), section 1, II.1, D31. Groundwork done: G3 (stdlib-only
builtins, `specs/progress/2026-09-22-stdlib-only-builtins.md`) and G2
(`specs/progress/2026-09-22-cap-narrowed-signature-grant-test.md`).

**What.** `stdlib/actor.march` declares `proof cap Introspect` and one minting
function `Actor.introspect(io : Cap(IO)) : Cap(Introspect)`. `pid_of_int`,
`Actor.list`, `Actor.whereis`, `Actor.registered` take the cap; the raw builtins
(`pid_of_int`, `actor_pid_indices`, `actor_whereis`, `actor_registered`) go into
`Typecheck_builtins.stdlib_only` with their suggestions. `cluster_node.march` mints
once in `start` and keeps the cap in its `ClusterHandle`; `session_node.march` gets it
from the node. `Actor.register` stays unprivileged. Migrate the ~20 test and bench
files that call `pid_of_int`. Verify every migrated stdlib module with
`march --check stdlib/<mod>.march` (the stdlib diagnostic filter hides a stdlib
module's own errors from programs that load it).

**Correct the plan while doing it.** II.1 and II.3 say `Cap(IO.NetListen)` unifies
with `Cap(IO)` and that the grant walk alone stops a narrowed caller. It does not
unify: amplifying a cap is a type error, and the walk rejects it too (G2 pins both).
The conclusion (D31) stands; the stated reason is wrong.

**When the `stdlib_only` set is first populated,** check that every entry point that
typechecks the stdlib (driver, LSP, forge's in-process parses, the REPL) sets
`Typecheck_builtins.stdlib_source_files`. With it empty, the stdlib's own calls to the
gated builtins would be rejected.

**Acceptance.** A program that calls `pid_of_int` with no cap fails to typecheck,
naming `Actor.introspect`; one that mints in `main` and forwards the cap compiles; the
existing supervisor-restart tests pass after migrating to `Actor.introspect(io)`.
Breaking change: CHANGELOG `### Changed` with the migration.
