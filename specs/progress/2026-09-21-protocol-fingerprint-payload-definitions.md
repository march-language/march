# The protocol fingerprint digests what a payload type is made of

Closes the P2 todo filed 2026-09-20 by the choreography UX pass; implements
[[2026-09-21-protocol-fingerprint-payload-definitions-implementation]].

## What was wrong

`<P>_Msg.fingerprint()` digested the protocol's roles and steps with each payload type by
NAME — `Desugar_endpoints.ty_key`'s `| TyCon (c, []) -> c.txt` was the whole of it. Two
nodes whose `Thing` was `{ x : Int }` on one and `{ x : String }` on the other produced the
SAME fingerprint. The access point accepted the invitation, the session formed, and the
skew surfaced mid-session as a decode failure on whichever side received a `Thing` first.

Worse, only the access-point path compared fingerprints at all (`SessionAP.Invite` carries
one; `SessionNode.offer_verdict` checks it). The direct runner's hello was
`encode_hello(role, me)` — role and pid — so a skewed pair on that path had nothing to
compare even once the digest became meaningful.

## What landed

**Part 1 — the digest folds the definition in.** `lib/desugar/desugar_endpoints.ml`:
`ty_key_deep` / `ty_key_in` / `td_key_in` replace `ty_key` inside `fingerprint_of`, which
now takes a REQUIRED `~types` built by `ty_defs_of decls` in `expand` (the same `decls`
`check_payload_codecs` already walks; no second walk was invented). A `TyCon` naming a type
declared in the module carries its definition: a variant's constructors in declaration
order with each one's payload types, a record's fields in declaration order — reordering
fields changes the JSON `derive Json` emits, so it is a wire change. Type parameters are
substituted positionally, so `Box(Int)` and `Box(String)` differ. The non-`TyCon` cases are
byte-for-byte what `ty_key` produced; they already described structure.

**Part 2 — the fingerprint rides the hello.** `stdlib/session_node.march`: `encode_hello` /
`decode_hello` / `announce` / `read_hello` / `read_hello_within` / `await_hello` carry it,
`hello_verdict` decides, and `join_accepted` / `join_dialed` refuse on it; `dial_all`,
`accept_all`, `run_party`, `run`, `run_hosted` and `run_hosted_or` thread it through, and
the generated `run_<Role>` / `host_<Role>` / `host_<Role>_or` pass `<P>_Msg.fingerprint()`.
`join_dialed` announces BEFORE refusing so the peer, parked in its own `read_hello_within`,
sees the skew instead of waiting out its timeout and reporting a quiet peer.

## The three hazards, and how each was handled

1. **Recursion.** `ty_key_in` carries a `seen` list of the type names already expanded on
   the current path and emits `@Name` for a repeat. `type Tree = Leaf | Node(Tree, Int,
   Tree)` terminates; covered by a unit case and by the accept fixture
   `specs/lang/types/accept/t290_endpoints_recursive_payload_fingerprint.march`, whose whole
   job is to be compiled at all (a non-terminating digest hangs the desugarer rather than
   failing a check).
2. **Types from other modules.** At desugar time `decls` is only the module being expanded,
   so an imported payload type cannot be expanded. It falls back to a key marked
   `extern:Thing` — VISIBLY different from today's bare `Thing`, so the digest at least
   records that the definition was unavailable. A short list of compiler-owned names
   (`payload_builtin_types`: `Int`, `String`, `List`, `Result`, …) is exempt, since both
   nodes agree on those by construction. **Residual gap:** a change below an imported
   payload type's name is still invisible to the fingerprint. Closing it needs the
   typechecker's view of other modules, which the spec put out of scope.
3. **Every fingerprint changed.** Nothing persists a fingerprint across a release (it is
   computed at compile time and compared live), so this is a compatibility break only
   between a node built before the change and one built after: they now refuse each other,
   at the access point and, new here, at the direct runner's handshake. Stated in those
   words in `CHANGELOG.md`.

**Hello compatibility.** The fingerprint is an OPTIONAL THIRD element of the msgpack hello
array. An old node sends the two-element hello it always sent and a new node reads it
without deadlocking; `""` from the peer is a REFUSAL naming the reason ("built before the
handshake carried one"), not a silent accept. `""` on the LOCAL side means "no protocol
identity to compare" and skips the check — that is the raw party API (`accept_from`,
`connect_to`, `open`), which never had one and whose signatures are unchanged. The refusal
carries the `Handshake:` prefix `dial_retry` stops on, so a skew is reported at once rather
than retried until the connect budget runs out.

## Not covered: `cluster_<Role>`

The todo asked for the direct runner AND `cluster_<Role>`. Only the direct runner landed.
`run_cluster_party` does not exchange a hello at all: it finds its peers by name in the
cluster node's registry (`session:<sid>/<role>`) and rides the node's shared data queues, so
there is no frame to add an optional field to. Covering it means putting the fingerprint in
the registered endpoint entry and checking it when peers are found — a different mechanism
from the hello, and a separate change. An access point still checks every cluster session it
brokers (`offer_role` / `offer_hosted`), so a `cluster_<Role>` reached through an access
point is protected; a bare `cluster_<Role>` pair is not. Worth a follow-up todo.

## Tests

- `test/test_endpoints.ml`, five new cases: a payload type's definition is in the digest;
  reordering a record's fields changes it; a recursive payload terminates and its
  non-recursive parts still count; a parameterised payload's arguments are substituted; an
  imported payload type falls back to `extern:` without crashing while a builtin stays
  plain.
- `specs/lang/types/accept/t290_endpoints_recursive_payload_fingerprint.march`, with its
  INDEX row and all three recomputed count sites (405 / 405: 170 accept, 235 reject).
- `test/two_node/fingerprint_skew`: two nodes whose protocols differ ONLY in `Thing`'s
  definition. Both refuse at setup, on the direct runner, and neither body runs.
- `test/two_node/protocol/node_b.march` now declares the same `Bad` protocol as node-a,
  purely so the raw-`Session` node can pass `Bad_Msg.fingerprint()` to `SessionNode.run`.

**The skew scenario was proved non-vacuous four ways**, since a skew test that refuses
everything passes for nothing:

| perturbation | result |
|---|---|
| both sides agree (`Thing = { x : Int }` on both) | ACCEPTS — both bodies run, both end `ok` |
| payload type NAMES differ (`Thing` vs `Widget`) | refuses, as it did before this change |
| part 1 reverted (`ty_key_deep` back to name-only), definitions skewed | session FORMS, both bodies run, node-b dies decoding — the exact pre-fix failure |
| part 2 reverted (generated runner passes `""`), part 1 intact | same: the session forms and the skew lands mid-session |
