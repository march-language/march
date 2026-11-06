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

## Fixed (2026-11-05)

- **Message identity.** When the driver typechecked the program, it hands the interpreter
  the constructor's checked type at each span (`Eval.ctor_type_of_span`, set in
  `bin/main.ml` before `run_module`). A construction of an actor message whose name some
  handler uses is tagged `<Actor>_Msg.<Msg>` (`msg_tag_of_con`). Patterns compare it
  without the prefix (`strip_msg_qual`), and printing already showed the last segment.
- **Dispatch.** `handler_for_msg` runs a `<A>_Msg.<M>` tag only on actor `A`. A bare tag
  whose name two actors, or an actor and a variant, share is dropped unless the
  interpreter built it itself (`Shutdown`, monitor `Down`, `$sys_inspect`). An unshared
  bare name still dispatches by name, and so does everything when no types were handed in
  (the REPL, tests that skip the typechecker). `Actor.call`'s request is runtime-built
  too: it is enqueued as `$call.<Handler>` (`runtime_call_prefix`) and dispatched by
  name on that instance. Left bare, a handler named like any variant (`Get`, `Count`)
  dropped every call, which the interpreter parity goldens `actor_call_late_reply`,
  `actor_call_in_handler_keeps_messages` and `actor_registry_restart{,_batch}` caught.
- **Found on the way.** Dropping a message did not mark scheduler progress, so a pass
  whose only work was a drop ended `run_until_idle` with later messages still queued.
- **Refinements.** `Refine_check`'s `DActor` arm now lets a handler body assume its
  parameter refinements when its message name is shared, since every construction of the
  actor's message is obliged per actor and both backends drop the others. This closes
  gap G4 of `specs/2026-11-04-lemmas-hcr-actors-choreography-design.md`: the design's
  probe (`on Bump(n : {Int | _ > 0})` next to an old `V1.Bump`) proves its handler body.

Tests: `test/native/actor_shared_name_drop.march` (a variant `Tok.Inc` and a same-state
actor's `Rival.Inc` sent to `Counter`, interpreted and compiled, one golden; the
interpreter printed `counter.n = 1108` before, compiled `8`); `test_refinecheck`
`actor-handler-contract` case 3.

Residual: a construction the typechecker recorded no type for stays bare, and if its name
is shared it is dropped rather than delivered. This needs a construction whose span the
type map lacks; no such case is known, but none was searched for exhaustively.
