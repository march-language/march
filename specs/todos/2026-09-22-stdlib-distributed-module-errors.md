# `[P2]` 4 remaining internal type errors across the distributed/actor stdlib modules

Filed 2026-09-22 from the stdlib internal-error sweep
(`specs/progress/2026-09-22-stdlib-internal-type-errors.md`, the closed umbrella). Grouped because they are all in
the same cluster of modules and several may share a cause.

(`session.march`'s 9 `Cap(Session.Live)` "not declared in `needs`" errors were
filed here too; they were a typechecker bug, not stdlib's, and are fixed; see
`specs/progress/2026-09-23-nested-module-own-proof-cap-exemption.md`.)

- ~~`node_call.march` (5): ambiguous `NoConnection`~~ — fixed, see
  `specs/progress/2026-09-29-stdlib-actor-nodecall-type-errors.md`.
- `session_node.march` (3): unknown constructors `PeerGone` (:264, :275) and
  `HostDown` (:444).
- `cluster_node.march` (1): unknown constructor `LocalDown` (:910).
- ~~`actor.march` (2): `Pid` vs `Pid(w)`~~ — fixed, same progress record.

The unknown-constructor ones are worth looking at first: a constructor that does
not resolve inside the module that uses it usually means the type moved or was
renamed and one arm was left behind, which is the kind of thing that also
misbehaves at runtime.
