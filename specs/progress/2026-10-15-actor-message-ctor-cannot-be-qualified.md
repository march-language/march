`[P3]` An actor's message constructor cannot be qualified by its actor

Found 2026-10-15 while adding the `send_wrong_actor` check
(`specs/progress/2026-10-12-send-message-not-checked-against-pid-actor.md`).

When two actors declare a handler of the same name, a bare `Tally(1)` resolves to
one owner (`lookup_ctor`), and the `ambiguous_constructor` hint says to "use a
qualified form to disambiguate, e.g. `Labels_Msg.Tally`". That form, and
`Counter.Tally` and `Counter.Msg.Tally`, are all `unknown_constructor`. So there is
no way to send the other actor its own message except renaming a handler, and the
hint's advice is wrong for actor messages.

Before the `send_wrong_actor` check this was a silent backend split (the
interpreter dispatches by handler name and runs the target's handler; compiled
code builds the other actor's message, globally unique tag, and the target drops
it). The check now turns the differing-state case into an error, but the
same-state case still splits, and the user still cannot write the correct send.

Fix direction: register each actor message constructor under `<Actor>_Msg.<Name>`
(the spelling the hint already suggests) and make sure lowering builds the
qualified owner's tag. Alternatively, at a `send` whose pid type identifies a
single owner, resolve an ambiguous bare name to that owner. Add a test with two
actors sharing a handler name, run on both backends.

## Fixed (2026-11-04, gap G4 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md`)

- **Typechecker.** Every actor message constructor is also registered under
  `<Actor>.<Msg>`, `<Actor>_Msg.<Msg>` and, for a nested actor, `<Mod>.<Actor>.<Msg>`
  (`Typecheck_env.actor_msg_ctor_keys`, used by all three registration sites). Lowering
  already keyed the allocation by the constructor's checked type (`<Actor>_Msg.<Msg>`), and
  the interpreter strips the qualifier, so `send(c, Counter.Tally(1))` reaches `Counter` on
  both backends (`test/native/actor_msg_qualified.march`, interpreted and compiled).
- **Diagnostics.** The `ambiguous_constructor` hint and the `send_wrong_actor` advice name
  the qualified spelling (`Counter.Tally`) instead of telling the user to rename a handler.
- **Refinement checker.** A refined handler's contract is also keyed `<Actor>_Msg.<Msg>`
  (`Refine_scope.collect_handler_sigs`). `Refine_check.handler_resolution` attributes a
  construction by its written qualifier, then by its recorded type, then by the bare name;
  a shared bare name with no recorded type is a recorded `message-unresolved` skip (a new
  `Obligation.reason`). So a shared name is obliged per actor instead of not at all. The
  handler body still assumes only an unshared name: the interpreter dispatches by name
  (todo `2026-11-04-interp-actor-dispatch-by-name`).
- **Found on the way.** A fresh state literal at a handler's tail was checked with an empty
  scope, so `on Bump(n : {Int | _ > 0})` could not prove `{ count: state.count + n }`
  against `count >= 0` even with a unique name. The design's probe P3 blamed the shared
  name. The literal is now checked with the handler's assumed parameter refinements.

Tests: `run_compiler` "actor message ctor qualified by its actor"; `test_refinecheck`
`actor-handler-contract` (cases 3-6) and `stored-field-contract` 6; the golden
diagnostic `send_wrong_actor_2`.
