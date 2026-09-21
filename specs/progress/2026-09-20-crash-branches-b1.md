# Crash branches, phase B1: syntax, checks, projection, callback API, runtime

Shipped 2026-09-20. Part B, phase 1 of
[[2026-09-19-choreography-access-points-and-crash-branches-design]], as planned in
[[2026-09-20-crash-branches-implementation]]. The model is the ECOOP 2023 crash-stop MPST,
adapted so that the default is today's semantics: a protocol names the roles that `may
crash`; every other role is reliable and a protocol without the declaration means what it
meant before.

## What it adds

**Syntax** (`lib/lexer/lexer.mll`, `lib/parser/token_filter.ml`, `lib/parser/parser.mly`).
`may crash C, D` as a declaration step and `A -> B : T or crash do ... end` on a message
step; a `choose by C` branch labelled `crash` is C's crash branch by label, no new form.
`may` and `or` are soft keywords: the lexer emits `MAY`/`ORWORD` and the token filter
demotes them back to identifiers unless `crash` is the very next token, the way `restart`
and `backoff` already work. This is what keeps the grammar LR(1): after a message step's
type, a following `stop` (a `LOWER_IDENT`) and a following `or crash` would otherwise be
the same lookahead token. Menhir's conflict count is unchanged at 11.

**AST** (`lib/ast/ast.ml`): `ProtoMayCrash of name list * span` and `ProtoCrashOr of
protocol_step * protocol_step list * span` (the wrapped step is a `ProtoMsg`, matched as a
step rather than destructured, so the concurrent message-labels work can add a field to
`ProtoMsg` without touching this). Every consumer of `protocol_step` learned the two:
`typecheck.ml`, `typecheck_session.ml`, `lower.ml`, `eval.ml`, `ast_json.ml`, `format.ml`,
`lsp/lib/code_actions_ast.ml`, and the generator.

**Well-formedness** (`lib/typecheck/typecheck.ml`, `check_crash_branches`, run from the
`DProtocol` arm). Six rules, each with a reject fixture (`specs/lang/types/reject/t271`
to `t276`) and a unit test (`test/test_endpoints.ml`):

1. a receive from a `may crash` role has a crash branch (a `choose by C` where C may crash
   has a `crash` branch; the branch heads are covered by it, not individually);
2. a crash branch is only for a `may crash` sender;
3. the crashed role appears nowhere in its own crash branch (nested crash branches
   accumulate the dead roles along the path);
4. a third party in the normal continuation or the crash branch is told which one it is in:
   its first interaction in each is a receive from the detector, with distinct `choose`
   labels if both are branch heads (two plain message steps are always distinct messages);
5. a `choose` with a `crash` branch has one detector: every other branch heads to the same
   receiver;
6. `may crash` names roles of the protocol, once each, at the top level.

The typecheck-side projection for `Chan(Role, Proto)` does not learn crash branches: a
protocol with `may crash` or a crash branch is refused at the `Chan`/MPST type
(`typecheck_unify.ml`, `has_crash_branches`) with "only supported with `@[endpoints]`".
`project_steps` itself projects the wrapped message as if it had no branch, so the duality
and consistency checks still cover the normal path.

**Projection and generation** (`lib/desugar/desugar_endpoints.ml`). A new `astep`
(`ACrashOr`), a new local type constructor `LRecvCrash (from, branches, crash)`, and a
`merge` helper that generalises the non-chooser merge. For `A -> B : T or crash do G' end`:
A sends and continues (the branch does not exist for it); B gets `LRecvCrash` with one
branch (state `S_recv_<Ctor>`, function `recv_<Ctor>(s, st, k, on_crash)`, no `_or` form);
any other role merges its normal and crash projections into an offer FROM THE DETECTOR over
the messages it receives (`offer_<Ctor1>_<Ctor2>`, arms named by constructor since it is the
detector's messages, not a chooser's labels, that tell it apart). A `choose by C` with a
`crash` branch projects onto the detector as `LRecvCrash` over the labels (state
`S_offer_<labels>_crash`, `offer_<labels>_crash(s, st, on_l..., on_crash)`), onto C as a
`choose` over the other branches, and onto third parties by the same merge. The lenient
merge also splices an arm that is itself an offer from the detector (the full merge);
ordinary `choose` merging is unchanged. Every role module carries `Crashed_<Role> = {
role : Int, cause : String }`; the crash callback is `Crashed_<Role> -> S_<first state of
G'> -> Yield`. The fingerprint includes crash branches.

**Runtime** (`stdlib/session.march`, `stdlib/session_node.march`). `Session.Ops` gains
`on_crash : Int -> Int -> (Int -> String -> Int -> Int) -> Int` (endpoint, role, crash
continuation) and `Session.on_crash`; every `Ops` literal in the tree has the field.
`SessionNode` keeps the continuation in a new `crash_hs` vault under endpoint and role.
`check_waiting`, when the endpoint waits on a role that is gone with nothing queued, runs
the crash continuation for that role if one is installed (in the endpoint actor's turn,
then `drain`), instead of `cancel_endpoint`: the endpoint stays live and no Cancel frame
goes out. `resume_with` clears it when the message arrives. `check_waiting` and `drain`
carry `@[no_warn_recursion]`: the new call from the one into the other is bounded by the
protocol's nesting of crash branches.

**Parser fix found on the way.** A `choose` branch with a second MESSAGE step on a new
line (`read -> C -> I : String` then `I -> L : String`) never parsed: the token filter's
new-arm lookahead read the upper-case role and its `->` as a new arm. Every existing
protocol only ever put `stop` there. The filter now knows a `choose` block's arms start
with a lower-case label, so an upper-case token continues the branch
(`ms_is_choose`). Rule 5's fixture needs it.

## Tests

- `test/test_endpoints.ml`: shape (the detector's arity 4 receive, `Crashed_I`, the states,
  the third party's offer, nothing for C), all three roles typechecking, the crash callback
  holding the branch's state (sending the normal step from it is a type error), one test per
  rule plus the twice-listed case, the `choose` form, and the `Chan` refusal.
- `specs/lang/types/accept/t273_crash_branches_logging.march`, `reject/t271`-`t276`
  (INDEX.md's three count sites updated from `ls`). Mirror the rejects in march-lean after
  merge.
- `test/session/logging_crash.march` (+ dune rule): the logging protocol in one process on a
  transport that can mark a role gone, run twice: with C alive and with C crashed, where I
  takes the crash branch with a live state and L gets the Fatal.
- `test/two_node/crash_before_send` and `crash_after_send`: three OS processes, C SIGKILLed
  before or after its `Read`. Before: I takes the crash branch, L gets `Fatal`, both return
  `Ok`. After: the `Read` is delivered, the conversation completes without C, I's `Report` to
  C is dropped, both return `Ok`. All three nodes are compiled before the first `start_node`.

## Out of scope (phase B2)

- The event API: `Received_<Role>` has no `Crashed_<Ctor>` alternative yet and a hosted
  role (`host_<Role>`) does not take crash branches; when the role it waits on crashes it is
  cancelled as before (`check_waiting` finds no crash continuation, because `await_*`
  installs none). The guide says so. CLOSED by
  [[2026-09-21-crash-branches-b2]].
- Cluster mode is untested with crash branches; the same `check_waiting` runs there, so a
  SWIM-declared death should take the branch, but no scenario pins it.
- A crash branch inside a `loop` ends the loop (the design's simplest reading).
- The `Chan` projection refuses crash protocols rather than learning them.
