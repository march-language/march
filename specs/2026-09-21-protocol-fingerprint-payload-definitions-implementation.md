# The protocol fingerprint should digest what a payload type is made of

Implements [[2026-09-20-protocol-fingerprint-payload-definitions]] (P2, filed by the
choreography UX pass). Two halves, separable: **(1)** fold a payload type's DEFINITION into
the digest, and **(2)** exchange the fingerprint on the transports that do not, so skew is
a setup error everywhere rather than only at an access point.

## The bug

`<P>_Msg.fingerprint()` digests the protocol's roles and steps, with each payload type by
NAME. `Desugar_endpoints.ty_key` (~line 510) is the whole of it:

```ocaml
| TyCon (c, []) -> c.txt
```

So a protocol step `A -> B : Thing` contributes the four characters `Thing` no matter what
`Thing` is. Two nodes whose `Thing` is `{ x : Int }` on one and `{ x : String }` on the
other produce the SAME fingerprint. The access point accepts the invitation, the session
forms, and the skew surfaces mid-session as a decode failure, `Protocol(role,
"undecodable message: ...")`, at whichever step happens to carry a `Thing` first.

That is the worst shape for this class of error: it arrives after the session is doing
work, blames a message rather than a version, and only on the receiving side.

Worse, two of the three entry points never compare fingerprints at all. `offer_role` /
`offer_hosted` check them (`SessionNode.offer_verdict`, `stdlib/session_node.march` ~line
1904: `else if fp != o.fingerprint do "protocol differs"`), because `SessionAP.Invite`
carries the fingerprint. The direct runner (`run_<Role>`) and `cluster_<Role>` do not: the
hello frame is `encode_hello(role, me)`, role and pid only (~line 636). A skewed pair on
those paths has nothing to compare even once part 1 makes the fingerprint meaningful.

## Part 1: fold the definition in

**Where.** `Desugar_endpoints.ty_key` and `fingerprint_of` (~lines 510-538). The digest
input is built in `expand` (~line 1347), which already has the module's `decls` in scope
and already walks them for exactly this purpose: `check_payload_codecs` (~line 1279)
collects `DType`/`DAlwaysLinearType` names and `DDeriving` names from `decls` to decide
whether a payload has a `Json` codec. Reuse that shape; do not invent a second walk.

**What to fold in.** For a `TyCon (c, args)` whose `c` names a type declared in this
module, append the type's DEFINITION, recursively, rather than only its name. A variant
contributes its constructors in declaration order with each one's payload types; a record
contributes its fields in declaration order with their types, since a reordering changes
the JSON the `derive Json` codec emits. Type parameters are positional and must be
substituted, not spelled: `Box(Int)` and `Box(String)` differ.

**Three hazards, each needing a test.**

1. **Recursion.** `type Tree = Leaf | Node(Tree, Tree)` must terminate. Keep a set of type
   names already expanded on the current path and emit a back-reference for a repeat
   (`@Tree`), not another expansion. A protocol carrying a recursive payload is ordinary,
   so this is not an edge case.
2. **Types from other modules are out of reach.** The todo says so and it is right: at
   desugar time `decls` is the module being expanded. A `TyCon` naming an imported type
   must fall back to today's name-only key, and the fallback must be VISIBLE rather than
   silent, because an unexpandable payload is precisely the case the fingerprint cannot
   protect. Prefer a distinguishable key (`extern:Thing`) so the digest at least records
   that the definition was not available, and note the residual gap in the progress record.
   Do not try to reach the typechecker's view from the desugarer for this.
3. **Every fingerprint changes.** The digest is a version marker; widening its input
   renumbers all of them. Nothing persists a fingerprint across a release today (it is
   computed at compile time and compared live), so this is a compatibility break only
   between a node built before the change and a node built after. Say so in the CHANGELOG
   in those words: an old binary and a new one will now refuse each other at the access
   point, which is the correct behaviour and not a regression.

**Do not** change `ty_key`'s output for the non-`TyCon` cases; they already describe
structure.

## Part 2: exchange it on the other two transports

The todo's second sentence: "the standalone runner and `cluster_<Role>` do not exchange
the fingerprint at all; sending it in the hello and refusing on a mismatch would make a
version skew a setup error everywhere, not only at access points."

**Where.** `stdlib/session_node.march`: `encode_hello` / `decode_hello` / `read_hello`
(~lines 634-671), and the two joins that consume them, `accept_from` and `connect_to`
(~lines 780-800). The generated callers already have the value to pass:
`<P>_Run.run_<Role>` and `cluster_<Role>` are emitted in `run_module` and already call
`<P>_Msg.fingerprint()` for the access-point entry points (`desugar_endpoints.ml` ~lines
1131, 1146, 1223).

**Compatibility of the hello frame itself.** `decode_hello` must be able to read a hello
without the field, or an old and a new node deadlock at the handshake instead of reporting
skew. Add the fingerprint as an OPTIONAL trailing element and treat its absence as "peer
too old to say", which is itself a refusal with a clear message, not a silent accept.
Confirm how `NodeSend.cast`'s payload list is framed before choosing the encoding.

**The error.** A mismatch must be refused at setup with a message naming the protocol and
saying the two sides were built from different versions of it. Route it through the
existing `RunError` vocabulary (`run_error_message`); a handshake-time refusal already has
a home, and `dial_retry` stops on `"Handshake:"` errors rather than retrying, which is the
behaviour a skew wants. Check that a refusal here does not turn into a retry loop.

## Tests

- **Unit, `test/test_endpoints.ml`**: two protocols identical except for a payload type's
  definition must produce DIFFERENT fingerprints; two identical ones the same fingerprint;
  a record whose fields are reordered differs; a recursive payload terminates; an imported
  payload type falls back without crashing. The fingerprint is a pure function of the
  generated module, so these are cheap and they are the heart of part 1.
- **Corpus**: an accept fixture with a recursive payload type, since that is the
  termination hazard. Update `specs/lang/types/INDEX.md`'s THREE count sites (title range;
  the "currently N/N" line, whose count WRAPS across a line break so a single-line replace
  misses it; the "**Result:**" footer), recomputed from `ls`, plus a table row.
- **`test/two_node/fingerprint_skew`**: two nodes whose protocol differs ONLY in a payload
  type's definition must refuse at setup, on the direct runner, with the skew message and
  no session formed. This is the scenario that proves both halves at once, and there is no
  scenario like it today. Precompile every node (`compile a`, `compile b`): a handshake
  refusal is a timing-sensitive setup path and CI's slower compile lands inside the window.
- **Prove the scenario goes RED for the right reason.** Before trusting it, check that it
  still refuses when part 1 is reverted but the payload names differ, and that it ACCEPTS
  when both sides agree. A skew test that refuses everything passes vacuously.
- `scripts/two-node.sh cluster_ap` and `cluster_ap_retry` exercise the existing
  fingerprint refusal and must stay green; `stream`, `crash_before_send` and
  `cluster_ap_hosted` cover the hello change.

## Records

`specs/progress/2026-09-21-protocol-fingerprint-payload-definitions.md`; move the todo out
of `specs/todos/`. CHANGELOG under `### Fixed`: a protocol whose payload types differ in
their definitions is now caught when the session is set up, rather than as an undecodable
message once it is running, and the check now covers the direct and cluster runners, not
only access points.

## Out of scope

Reaching across modules for an imported payload type's definition (needs the typechecker's
view, and the fallback above makes it explicit rather than silent). Persisting a
fingerprint across releases, or any notion of protocol version negotiation: the
fingerprint stays a same-or-refuse equality check.
