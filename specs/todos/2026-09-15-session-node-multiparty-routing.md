# `[P2]` `SessionNode`: multiparty routing (3+ roles on 3+ nodes)

Filed 2026-09-15, after [[2026-09-15-session-node-transport]] shipped the binary
transport. The projector has been multiparty since
[[2026-09-03-protocol-projector-typed-endpoints]] (step 5, `Relay`): it projects
any number of roles and checks them for pairwise duality. The transport is the
part that is still binary, so a 3-role protocol can be written and typechecked
but not run across three nodes.

## What is binary today, precisely

`SessionNode.ops(link)`'s `emit` ignores the destination role:

```march
emit: fn (ep, to, msg) -> do
  let _ = NodeQueue.cast(q, next_seq(meta), peer, "SessionNode.Deliver", encode_deliver(to, ep, msg), NodeQueue.DropNew)
  ep
end
```

`to` is carried in the payload (so the receiver fires the right endpoint) but
never used to choose a *connection*: there is one `link`, one queue, one peer.
`SessionNode.serve(link)` likewise reads exactly one data connection on the
calling thread.

Two facts make the extension small:
- **Roles are 1..n** (`<P>_Msg.role_<R>()`, `desugar_endpoints.ml:379`), and the
  transport's `register` returns the role as the endpoint id, so `ep` IS the
  local role and `to` IS the remote role. No new identifier space is needed.
- **`NodeQueue`, the hello, CREDIT and Bye are already per connection.** Only
  their ownership moves: from one `Link` to a set of links keyed by role.

## Design

### `Party` replaces `Link` as the thing `ops` closes over

```march
type Party = {
  my_role  : Int,
  handlers : Vault(Int -> Bytes -> Int -> Int),   -- one per local endpoint, as today
  meta     : Vault(Int),
  ep       : Pid({ n : Int }),                    -- ONE endpoint actor for the party
  links    : List((Int, Link)),                   -- remote role -> its connection
  on_close : Int -> Unit
}
```

One endpoint actor and one handlers vault for the whole party: continuations are
keyed by local endpoint, and a role has exactly one. Each `Link` keeps what it
owns now (data fd, control fd, peer pid, its `NodeQueue`, its control-reader
task). `links` is an association list, not a `Map`: n is a handful, and a list
keeps the record free of a Map-of-records.

### API

```march
-- one call per remote role, after the caller's own connect_split / accept_split
let p0 = SessionNode.party(my_role, fn ep -> ())
let p1 = SessionNode.join(p0, their_role, conn, accepted)
let p  = SessionNode.join(p1, third_role, conn2, accepted2)
let s  = Session.attach(io, SessionNode.ops(p))
...
SessionNode.serve(p)     -- a reader task per link; returns when every peer has said Bye
SessionNode.finish(p)
```

`SessionNode.open(conn, node_id, accepted, on_close)` stays, as `party` + one
`join` whose role is "the only peer". **Back-compat rule:** a party with exactly
one link routes every `to` to that link, so the binary case never needs role
numbers and `test/two_node/stream` is untouched.

### Who connects to whom

Every pair of roles that exchanges a message needs a connection. Deterministic
rule, so no configuration and no deadlock: **for roles i < j, i listens and j
connects.** The accepting side announces first in the hello, as today. The hello
gains the announcer's ROLE alongside its endpoint `GlobalPid`, so the acceptor
learns which role it just accepted rather than being told out of band.

A role only needs links to the roles it actually exchanges messages with; the
projection knows that set, but the caller passes it in for the first cut
(`join` per peer). A missing link is a runtime error naming both roles, not a
silent drop.

### Reading from n-1 connections

`serve` spawns one reader task per link and awaits them all. Each reader is the
current `on_frame` loop; deliveries go to the party's single endpoint actor, so
resumptions still run in mailbox order in one actor. Do NOT call
`run_until_idle` anywhere inside: with a reader parked in a socket read it never
returns ([[project_run_until_idle_parked_task_trap]] is the same trap the stream
scenario hit).

Termination: `close(ep)` queues a Bye on EVERY link (a role closes once, and each
peer's reader must learn it). A reader ends on its peer's Bye; `serve` returns
when all readers have ended. A peer closing the data connection after a local
endpoint has closed stays a clean end, as now.

## The load-bearing decision: cross-peer arrival order

This is the one thing that is not mechanical, and it does not arise with two
nodes.

A role's receives are sequential in the protocol, but with n-1 connections the
messages arrive on n-1 independent TCP streams. Per-peer FIFO is guaranteed;
across peers nothing is. So for a protocol where a role receives from A and then
from B, B's message can arrive first, and the installed continuation — which
expects A's — would be handed it. The generated handler decodes and matches on
the constructor, so this surfaces as the catch-all "unexpected message" arm (or,
worse, as a constructor that happens to be shared).

`Relay` does not exercise this (each role's receives come from one peer), which
is exactly why a `Relay`-only test would hide it.

**Recommended fix: make the expected sender part of `suspend`.** The projector
already knows it — `LRecv (from, ctor, payload, next)` and `LOffer (from, …)`
carry it (`desugar_endpoints.ml:62,64`) — and the generator then throws it away,
binding the handler's first parameter as `_from` (`suspend_with`, `:413`). So:

- `Session.Ops.suspend` becomes `Int -> Int -> (Int -> Bytes -> Int -> Int) -> Int`,
  the new `Int` being the expected sender role (0 = any, which is what a
  same-thread transport and the binary case pass).
- `Session.suspend` gains the argument; `suspend_with` passes `role_idx from`.
- `SessionNode` keeps, per local endpoint, a small per-sender buffer: a delivery
  from a role other than the expected one is parked, and fired when the
  continuation that expects it is installed.

Blast radius of the `Ops` change: `stdlib/session.march`, the seven hand-written
transports under `test/session/`, `test/test_endpoints.ml`'s harness, and
`stdlib/session_node.march`. Mechanical, but it must land in one commit with the
generator, or every fixture breaks.

**The alternative** — document the restriction and reject protocols where a role
receives consecutively from different roles — is cheaper but leaves a trap that
only shows up as a rare reordering under load. Not recommended; the projector
has the information, so the transport should not have to guess.

## Tests

- **Three roles in one process, over loopback** (`test/native/session_node_relay_loopback.march`):
  `Relay`'s three roles as three tasks with real sockets between them, the way
  `node_send_typed_loopback` does for two. Compiled only. This is the first
  witness and needs no harness change.
- **An out-of-order arrival**, deliberately: a 3-role protocol where one role
  receives from two peers in a fixed order, with the earlier sender delayed (a
  `Process.run("sleep")` before its emit) so the later message provably arrives
  first. This is the test the buffering exists for; write it before the fix and
  watch it fail.
- **Binary regression:** `test/two_node/stream` unchanged, goldens byte-identical.
- **A three-process scenario** (`scripts/two-node.sh` is two-node by
  construction — `node_a`/`node_b`, one port). Generalising the harness to N
  nodes is its own task; the loopback test above covers the semantics without
  it, so do not bundle them.

## Order of work

1. `Party` + `join` + per-role routing in `emit`, with the single-link fallback.
   Binary behaviour byte-identical; `stream` still green.
2. A reader task per link in `serve`, Bye to every link on close.
3. The `Relay` loopback test (three roles, one process).
4. The `suspend` expected-sender change: `Ops`, `Session`, `suspend_with`, the
   seven fixtures, and `SessionNode`'s per-sender buffer — with the out-of-order
   test written first, failing.
5. Docs: the `SessionNode` section of `specs/lang/clustering.md` and
   `docs/clustering.md` (both copies), and the module header.

## Out of scope

- Generalising the two-node harness to N processes (its own task).
- Session-typed routing across a partition, retries, or a peer that never
  connects: the transport reports the failure, the protocol does not resume.
- The `Chan`/`MPST` same-thread runtime, which this does not touch
  ([[2026-07-06-p2-compiler-session-types-protocols-channels]] F6).
