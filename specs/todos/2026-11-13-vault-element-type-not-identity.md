`[P2]` A Vault's element type is not part of its identity: the interpreter can mint a `PeerRegistry.Fd` (2026-11-13)

Found by the ocap phase 2b final re-review (I3,
`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-rereview.md`, probes `mint1`-`mint4`).
`Vault.new(name)` and `Vault.open(name)` / `Vault.whereis(name)` take any string, and the
element type is whatever each caller annotates. A module stores a value of its own type
`type Mine = Fd(Int)` under a name it chooses, reopens the same name as
`Vault(PeerRegistry.Fd)`, and gets a `PeerRegistry.Fd` it could never construct.

- **Interpreter:** constructors match by name, so the user's `Fd(n)` satisfies the stdlib's
  `match f do Fd(n)`. A forged `Peer` built from it reaches `SwimDriver.dispatch`, which
  writes to the guessed descriptor (`mint3`: "server side received 9 bytes").
- **Compiled:** safe only by accident. The constructor tag differs, so the stdlib's match
  panics (`mint1`/`mint3`/`mint4`), and a `Vault(Int)` payload SIGSEGVs (`mint2`).

So any opaque wrapper over plain data (`PeerRegistry.Fd`, and every `opaque type` whose
unforgeability matters) can be forged by an `IO.Mut` holder under the interpreter, and
the compiled behaviour is memory-unsafe rather than refused. This is the general case of
the threat model's "Handles minted from a name" hole; the stdlib-owned-names case is
specs/todos/2026-11-13-reserved-stdlib-vault-names.md.

Expected: a Vault's element type is part of its identity (a type fingerprint stored at
`new` and checked at `open`/`whereis`, refusing a mismatch), or `Fd` wraps a runtime handle
box (`VHandle` in the interpreter cannot be made from a user constructor). The first fixes
the class; the second only `Fd`.
