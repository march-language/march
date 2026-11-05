`[P2]` The interpreter dispatches an actor message by its constructor name

`run_scheduler` (`lib/eval/eval.ml`, the handler lookup `h.ah_msg.txt = msg_tag`) finds the
handler whose name equals the message value's tag. A `VCon` carries only that tag, so a
variant `Tok.Inc(-1)`, or another actor's `Ten.Inc(11)` sent to a pid whose state has the
same shape (the case `send_wrong_actor` cannot reject), runs the target's own `Inc`
handler. Compiled code gives every actor message a globally unique tag and drops a foreign
one (golden `g40_actor_foreign_msg_drop`).

Consequence for refinements: since 2026-11-04 a shared message name is obliged per actor
(`specs/progress/2026-10-15-actor-message-ctor-cannot-be-qualified.md`), but the handler
body still may not assume its parameter refinements, because under the interpreter a value
nobody obliged against this handler can reach it. Gap G4 of
`specs/2026-11-04-lemmas-hcr-actors-choreography-design.md` stays half open until this is
fixed: a `migrate_msg` that keeps a message's name gets its obligation, but the new
handler's body loses the assumption.

Fix direction: give actor message values an identity the interpreter can test, for example
tag a construction whose checked type is `<Actor>_Msg` as `<Actor>_Msg.<Msg>` (the
typechecker's type map reaches the driver, not the interpreter today), and drop a message
whose tag is not the target actor's, as compiled code does. Every interpreter site that
matches a message tag (handler dispatch, `Actor.call`, session endpoints, HCR
`migrate_msg`) must agree. Then `Refine_check`'s `DActor` arm can assume a refinement
whose `<Actor>_Msg.<Msg>` contract is registered.
