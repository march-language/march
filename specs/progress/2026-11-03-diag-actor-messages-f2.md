§F2 of `specs/plans/2026-11-02-diagnostics-depth-plan.md`, targets 1–4 (todo
`specs/todos/2026-11-02-diag-actor-messages.md` stays open for the survey, target 5).

- Message payloads: a constructor argument of an actor message is checked with the reason "`Bump` is a
  message of actor `Counter`, and its handler declares this argument's type", and the handler's
  parameter is the expected type's origin label (`ctor_arg_reason`; `DActor` records each handler
  parameter's span in `env.decl_sites`).
- `send_wrong_actor` names the pid's actor (the one actor declared in this file whose state the pid's
  state can be), lists its messages and labels its declaration; it falls back to the state record when
  no single actor fits. The `ambiguous_constructor` hint inside it is dropped (cascade rule).
- `actor_handler_state_type` in the house style: "The handler for `Bump` must return `Counter`'s new
  state, a `{ n : Int }`, but it returns an `Int`.", a label on the body, backticked field hints, and
  "If this is the new value of `n`, return `{ state with n: … }` with it." when the body's type is one
  field's. Explain page added.
- `{ state with cuont: … }` in a handler: "`Counter`'s state does not have a field called `cuont`. Did
  you mean `count`?", caret on the field, `FReplace` fix. The did-you-mean applies to every record update.
- Generated names: `ambiguous_constructor` describes an actor message as "a message of actor `A`" and
  never suggests the `A_Msg.X` qualifier (it cannot be written); when every candidate is an actor's
  message it says to rename a handler. `json_derive_name_collision` names a type in a generated
  `<P>_Msg` module as "the message type `T` generated for `P`". The `overlapping_impl` errors that
  followed it printed `<none>:29:266475457` for the generated impl's position; that now reads "a generated
  implementation", and they are dropped beside the collision error. Three allowlist lines removed
  (`Host_Msg`, `Labels_Msg`, `Stream_Msg`); the two `S_end` lines (F3) remain.
