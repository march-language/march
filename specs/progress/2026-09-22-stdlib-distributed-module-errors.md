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

## Fixed 2026-10-12

**Cause.** Not stdlib code: a typechecker scoping gap. An actor's `on Msg(...)`
handlers become constructors of `<Actor>_Msg`. The entry (top-level) module's
pass 1 registers every `DActor` up front, so a message is in scope for the
whole module. A NESTED module's forward pass (`check_decl`'s `DMod` arm,
`pre_env`) prebound only its fns; actor constructors entered the env only when
`check_decl` reached the `DActor` itself. Any fn, or earlier actor's handler,
naming a LATER actor's message was "I don't know a constructor called". The
ratchet typechecks every stdlib file wrapped as a nested `DMod`, and all four
sites are above their actor: `SessionNode.over_limit`/`drop_link` (:299, :310)
and the `HostWatch` actor (:604) send `PeerGone`/`HostDown` to `Endpoint`
(:714); `ClusterNode.RegWatch` (:1638) sends `LocalDown` to
`ClusterNodeActor` (:1649). The same code in user programs failed too
(`mod Outer do mod Inner do fn poke(..) do send(p, Ping(1)) end actor ...`),
while the identical code in a top-level module was accepted; both backends
always resolved it.

**Fix.** `lib/typecheck/typecheck.ml`: the registration that `check_decl`'s
`DActor` arm did inline is now `register_actor_ctors ~ci_module`, and the
nested-module `pre_env` fold calls it for each `DActor` with
`ci_module = <module name>` (what the `DActor` arm uses there), so the later
registration dedups in `add_ctor` instead of creating an ambiguity. The
entries are module-local: the `DMod` export step is computed from the
post-check env, which held these same constructors already, so nothing new is
exported (the bare name still is not visible to the parent).

**Tests.** `typecheck` / "nested actor message ctor named above its actor"
(test/test_compiler.ml): a fn with a typed `Pid`, a fn sending through a
record field, and an earlier actor's handler all name a later actor's message
inside a nested module and are accepted; a wrong payload type, a wrong arity
and an undeclared message are still rejected. RED on origin/main's
typecheck.ml (copied in): "a message named above its actor resolves" expected
false, received true; GREEN with the fix. The `stdlib_known_internal_errors`
ratchet is now empty (it was `cluster_node 1`, `session_node 3`; on the old
typechecker it reports those four errors against the empty table).

**Evidence.** A nested-module repro with a fn above the actor: old `--check`
exit 1 (unknown `Zork`), new exit 0; interpreted and `--compile`d both print
the handler's output. `--check` of the 161 actor/session/cluster programs in
test/native, test/errors, examples and test/snapshots/src (private HOME), old
binary vs new: byte-identical output and exit codes (111 accept, 50 reject).

Not changed: `send(pid, msg)` does not relate the pid's type to the message's
actor (`ESend` infers both sides independently), so sending actor A's message
to a pid of actor B was accepted before and still is. That is a separate,
pre-existing gap.
