# Crash branches: implementation spec (phase B1)

Implements Part B of [[2026-09-19-choreography-access-points-and-crash-branches-design]].
Read that first: the model (ECOOP 2023 crash-stop MPST), the syntax, the well-formedness
rules and the projection are decided there. This file is the file-by-file plan, the test
list, and what is out of scope. Decided 2026-09-19 with the user: crash branches in the
protocol, not cancel handlers that may send; syntax `may crash C` and
`A -> B : T or crash do ... end`.

## Concurrent work, and how to avoid colliding with it

[[2026-09-20-message-labels-implementation]] is being built at the same time, in the same
grammar (`protocol_step`) and generator (`Desugar_endpoints.annotate`). Rules:

- Do NOT change the shape of `Ast.ProtoMsg` (labels will add an optional field to it).
  Add NEW constructors: `ProtoMayCrash of name list * span` and
  `ProtoCrashOr of protocol_step * protocol_step list * span` (a message step with its
  crash continuation; the wrapped step is a `ProtoMsg`), and a `choose` branch whose
  label is `crash` is recognised by label, no new constructor.
- In the parser, add alternatives to `protocol_step`; do not restructure the rule.
- In `Desugar_endpoints`, add a new `astep` constructor (`ACrashOr`) and extend the
  walkers; do not rename `AMsg`'s fields.

## Files

**Lexer / parser** (`lib/lexer/lexer.mll`, `lib/parser/parser.mly` `protocol_step`,
lines ~948-967 today). `may` and `crash` are contextual: `may crash A, B` is
`lower_name(may) lower_name(crash) separated_nonempty_list(COMMA, upper_name)` at step
position; `crash` as a `choose` label is a plain `lower_name` already. `or crash do
... end` follows a message step: `upper ARROW upper COLON ty OR lower_name(crash) DO
list(protocol_step) END` (check whether `or` is a token; `||`/`or` in expressions --
reuse it if it is a keyword token, else match `lower_name` "or"). Menhir conflict count
must stay at the baseline (11); run `dune build --root . @grammar-check --force` and
read the log's contents (the alias without `--force` is empty).

**AST** (`lib/ast/ast.ml` `protocol_step`): the two constructors above.

**Well-formedness** (`lib/typecheck/typecheck.ml`, the `DProtocol` arm, ~5280-5400,
beside the existing "steps after loop" / "branch ends in stop" checks). Errors, each
with a corpus fixture:

1. a receive from a `may crash` role without a crash branch: "`C` may crash, so
   `C -> I : Read` needs `or crash do ... end`: what does `I` do if `C` crashes before
   sending?";
2. `or crash` on a step whose sender is reliable: "`A` is not declared `may crash`";
3. the crashed role appears in its own crash branch;
4. a role other than the detector that appears in both continuations must be able to tell
   them apart: its first interaction in the crash branch must be a receive from the
   detector, with a label different from its first interaction in the normal continuation
   (the rule `choose` already applies to non-choosers). Error names the role and the
   detector;
5. `choose by C` with a `crash` branch: every other branch head must go to one receiver
   (the detector); otherwise rejected;
6. `may crash` naming a role not in the protocol, or listed twice.

`typecheck_session.ml`'s projection (for `Chan(Role, Proto)`) does not learn crash
branches: it REFUSES a protocol containing `may crash` with "crash branches are only
supported with `@[endpoints]`". That keeps the older channel API sound without work.

**Projection and generation** (`lib/desugar/desugar_endpoints.ml`). For
`A -> B : T or crash do G' end ; G` with `A` in `may crash`:
- A: sends `T`, continues as `G|A`; the crash branch does not exist for it.
- B (the detector): an `LOffer` from A with two labels: the message's constructor
  (continue `G|B`) and `crash` (continue `G'|B`). The `crash` label carries no message
  constructor: give `LOffer` branches an `lbl_kind = Msg of ctor | Crash` (or a
  reserved constructor name `Crash__` that `collect_ctors` skips) -- pick the one that
  keeps `state_names` readable: the state is `S_recv_<Ctor>` as today, not
  `S_offer_...`, because from B's side it is still one receive.
- other roles: merge of `G|p` and `G'|p` (the generator's existing merge for non-choosers;
  rule 4 above guarantees it exists).
- a `choose by C` with a `crash` branch projects onto the detector as today's `LOffer`
  with one more label.

Generated API for the detector: `recv_<Ctor>(s, st, on_msg, on_crash)` where the crash
callback is `fn (crashed : Crashed_<Role>, st' : S_<first step of G'>) -> Yield`, and
`Crashed_<Role>` is a generated record `{ role : Int, cause : String }`. Keep the
existing `recv_<Ctor>` for steps WITHOUT a crash branch unchanged, and keep the `_or`
cancel variant (a crash branch is for a `may crash` sender; `_or` is for a reliable
sender that fails anyway). Event API: `Received_<Role>` gains `Crashed_<Ctor>(role,
cause, next)`; `resume` produces it; `await_<Ctor>` unchanged.

**Runtime** (`stdlib/session.march`, `stdlib/session_node.march`, and the in-process
transports in `test/session/*.march` which implement `Session.Ops`):
- `Session.Ops` gains `on_crash : Int -> Int -> (Int -> String -> Int -> Int) -> Int`
  (endpoint, the role that may crash, the crash continuation); `Session.on_crash`
  wrapper. Every `Ops` literal in the tree must add the field (grep `leave: fn`).
- `SessionNode.check_waiting`: when the endpoint waits on a role that is gone with nothing
  queued AND a crash continuation is installed for that role, run it in the endpoint
  actor's turn (like a delivery: install nothing, call it, then `drain`) instead of
  `cancel_endpoint`. The endpoint stays live; no Cancel frame goes out. Messages to the
  crashed role are already discarded (`emit` checks `gone`).
- The hosted path (`forward`): a crash for a hosted endpoint is forwarded like a
  delivery with a synthetic message; simplest is to reuse `forward_cancel` with a
  distinguishable cause prefix only if the event API cannot be reached otherwise.
  Prefer: `run_hosted_or`'s `cancel` callback is NOT used; add `forward_crash` (key "x")
  set by the hosted runner, and `Parked_<Role>.resume` handles it. If this grows past the
  budget, leave hosted crash delivery to B2 and say so in the progress record.

## Tests

- `test/test_endpoints.ml`: generator shape (the detector's `recv_<Ctor>` arity, the
  `Crashed_<Role>` type, `S_` names), and one `bad_desugar`/`bad` per error 1-6.
- `specs/lang/types/`: accept `t2NN_crash_branches_logging` (the ECOOP logging protocol
  from the design doc, all three roles written); reject one per error 1-6. Update
  INDEX.md's three count sites (title range, "currently", "Result") from `ls`; mirror the
  rejects in march-lean after merge (note it in the PR).
- `test/session/`: an in-process golden where C's role "crashes" by calling
  `leave_...` -- no: `leave` is a cancellation. Simulate a crash in-process by a
  transport that reports the role gone (`PeerGone`-equivalent in the test `Ops`). If the
  in-process `Ops` cannot express "gone", skip this and rely on the two-node scenarios.
- `test/two_node/crash_before_send` and `crash_after_send` (three nodes, the logging
  protocol): C killed before sending `Read` (I takes the crash branch, L gets `Fatal`,
  all three exit normally with the crash branch's output); C killed after sending `Read`
  (the `Read` is still delivered, the protocol continues until it next waits on C, which
  is never, so it completes normally). Precompile all nodes in scenario.sh (`compile a`,
  `compile b`, `compile c`) -- CI's slower compile otherwise eats any timing window.
- `docs/choreography.md` and `specs/lang/choreography.md` (identical twins): a "When a
  role may crash" section after "When a role fails", with the logging example; remove the
  Limits bullet "a cancel handler cannot keep the conversation going".

## Out of scope (say so in the progress record)

Crash branches inside a `loop` end the loop (the design's simplest reading); hosted crash
delivery may be deferred to B2; the typecheck-side `Chan` projection refuses crash
protocols.
