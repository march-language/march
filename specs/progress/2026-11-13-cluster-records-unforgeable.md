# Cluster records and actors that carry raw descriptors are unforgeable (2026-11-13)

Ocap phase 2b final whole-branch review, finding C1
(`.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/final-review.md`).

**The hole.** Task 9 made the cluster *functions* that take an `fd : Int`
`@[stdlib_internal]`, and Task 10 made socket writes uncharged. A public record still
held raw descriptors: `PeerRegistry.Peer { node_id, identity, fd : Int, data_fd : Int }`,
and public functions consumed it (`SwimDriver.dispatch`/`dispatch_all`/`dispatch_with_load`,
`DistLink.resend_pending`, `Node.send_tagged`/`send_tagged_schema` and so `Node.send`). A
module holding only `needs IO.Mut` (or `IO.Mut("cache")`) built a `Peer` literal around a
guessed fd and called `SwimDriver.dispatch`: `--check` exit 0, and the compiled program
wrote 9 bytes into a socket `main` held (the reviewer's `forge_peer3`/`forge_peer4`).
Auditing the other fd-bearing types found a second route: the `NodeQueue.Writer` actor's
`Configure(fd, budget)` message. User code could `spawn(NodeQueue__Writer)` (the compiler's
own "did you mean" spelling), or take the writer pid of `NodeQueue.start_local`, send it
`NodeQueue.Configure(fd, ..)` and then `NodeQueue.enqueue`, and the frame was written to the
guessed fd (probe compiled and ran: "server side received 6 bytes").

**The fix.**
- `PeerRegistry.Peer`'s two descriptors are `PeerRegistry.Fd`, an `opaque type Fd = Fd(Int)`
  whose constructor is private to the module. The stdlib makes and reads them through
  `@[stdlib_internal]` `PeerRegistry.make`, `raw_fd`, `raw_data_fd`; `node_id`/`identity` stay
  plain fields. A record literal with `fd: 3` no longer has type `Peer` (type mismatch,
  "expected `Fd`"), and `PeerRegistry.Fd(3)` is an unknown constructor. `{ p with fd: .. }`
  needs an `Fd`, which only an existing stdlib-made `Peer` holds. Stdlib callers
  (`cluster_conn`, `swim_driver`, `dist_link`, `node`, `session_node`) and the plumbing
  fixtures (all `--stdlib-source`) moved to the accessors.
- **`@[stdlib_internal]` on an actor** (new, the existing attribute extended from functions):
  `Ast.actor_def.actor_internal`, set by the parser from the attribute list; the typechecker's
  `DActor` arm files a stdlib actor's name constructor and message type in
  `env.stdlib_internal_actors`, and the `ECon` arm refuses either outside
  `span_may_name_internal` (the stdlib, `<control>`, `--stdlib-source` entries):
  "`NodeQueue.Configure` belongs to the actor `NodeQueue.Writer`, which is internal to the
  standard library; use the public API of its module instead." (`[stdlib_internal]`).
  Since `spawn(A)` infers `A` as a constructor and `send` builds the message with one, user
  code can neither spawn such an actor nor send it a message. Marked: `NodeQueue.Writer`,
  `ClusterNode.CtlWriter` (`CtlUse(fd)`), `ClusterNode.ClusterNodeActor` (`Accepted(fd, ..)`,
  `Dialed(.., cfd, dfd, ..)`, `MoveReader(.., l : CnLink, ..)`). A user's own message type
  with the same constructor index does not reach the handler: actor message tags are
  globally unique and a foreign tag is dropped (lower_actor.ml, finding 19; probed).
- The audit of the rest: `ClusterNode.CnLink`/`CnHalf`, `NodeQueue.WriterState` and
  `SessionNode.Link` reach I/O only through those actors and private functions; the public
  `ClusterNode.core_*` functions that take a `cfd`/`dfd` are pure state transitions whose
  effects only the internal actor performs.

**Tests.** `test/test_stdlib_only.ml` "cluster records and actors unforgeable": the
reviewer's forged-`Peer` program and a forged-actor program (spawn of each of the three
actors, `NodeQueue.Configure`/`Enqueue` to a spawned and to a `start_local` writer,
`ClusterNode.CtlUse`) each fail `--check` with the errors above; the same actor program
under `--stdlib-source` is not refused. `cluster_plumbing_internal` gains
`PeerRegistry.make`/`raw_fd`/`raw_data_fd`. The errors corpus `codec_missing_1`/`_5`, the
reject corpus `t239` and the `codec_missing` explain page no longer build a `Peer` literal
(a `Peer` now arrives as a parameter).

Follow-up (unchanged): specs/todos/2026-11-13-cluster-record-types-hold-raw-fds.md, the
migration of the cluster records to `Socket` handles.
