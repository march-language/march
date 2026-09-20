# Choreography: a UX and hardening pass

Shipped 2026-09-20. Method: ten deliberately wrong programs compiled to grade the errors a
user sees, a two-node run with mismatched secrets, and a read-through of the guide against
the generator. What was cheap is fixed here; the rest is filed
([[2026-09-20-choreography-message-labels]], [[2026-09-20-choreography-entry-state-alias]],
[[2026-09-20-session-in-process-transport]],
[[2026-09-20-protocol-fingerprint-payload-definitions]]).

## Fixed

- **A payload type without a JSON codec is an error at check time.** `type Thing = { x : Int }`
  as a payload passed `--check`, failed the compile with codegen's "ambiguous
  interface-method call to `JsonTo.to_json`", and panicked the interpreter at the first
  `encode`. The generator now checks every payload type declared in the module against the
  module's `derive Json` declarations (nested in `List` / tuples too) and says which step
  and which type: "the message `A -> B : Thing` carries `Thing`, which has no JSON codec
  ... add `derive Json for Thing`". It keeps generating, so the one error is not followed
  by a cascade of `Unknown module `P_Msg``. Types from other modules are not seen at
  desugar time and keep the runtime behaviour.
- **Session-state mismatches say what they mean.** `expected `S_recv_Msg_B_A_1` but got
  `S_send_Msg_A_B_1`` now adds that both are states of a generated role, what `S_<step>`
  means, and the two causes (steps in another order, or a body written for a different
  role than it is run as). `expected `Yield` but got `S_end`` says a body ends with
  `<Role>.close(s, st)`. (`Typecheck_unify.report_mismatch`, by name shape, so it costs
  nothing elsewhere.)
- **A rejected handshake is reported as such.** With different secrets, the dialing side
  retried for the whole setup time and ended with "Connection refused", from dialing a
  listener that had already given up. `dial_retry` stops on a `Handshake:` error and adds
  "(do both nodes run with the same secret?)". Scenario `wrong_secret`.
- **Errors name roles.** Every `RunError` carries role numbers, which a user never writes.
  `<P>_Msg.role_name(n)` and `<P>_Run.error_message(e)` (over the new
  `SessionNode.run_error_message_named`) give "connect to role A" instead of "role 1".
- **`offer_<Role>` returns `RunError`** like every other entry point, with the new
  `AlreadyOffered(role)`, instead of a `String`.
- **The guide**, both copies: the generated `Msg` functions it omitted; `Yield` explained
  where it first appears; the one-function-per-receive idiom instead of a closure pyramid;
  a table of the six entry points with transports and return types; the failure vocabulary
  in one table; a configuration table with every variable and its zero semantics
  (`MARCH_SESSION_QUEUE_MAX_BYTES` was undocumented); three statements corrected ("any
  size, nothing dropped" is bounded by the queue limit; `Accept` carries a reason, not
  roles; the cluster runner's 30 s is a fixed limit); the secret-mismatch messages; a
  pointer to a complete in-process transport for tests.

## Graded and left alone

Linearity errors (`used more than once`, `never used`), payload type mismatches, self-sends,
`choose` branches not starting with the chooser, and steps after a `loop` all read well as
they are. A missing `needs Session.Live` in a module whose `main` never names the
capability is correctly not an error.

## Not done here

- Message labels on protocol steps, so the names stop being `Msg_A_B_1` (the top finding;
  needs syntax).
- An `Entry` alias per role, a stdlib in-process transport, the fingerprint folding in
  payload definitions, hosted roles over a cluster node, a receive with a timeout.
