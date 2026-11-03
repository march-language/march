`[P2]` Diagnostics for actors: message payload errors don't say "message of actor `A`" or point at the
handler; `send_wrong_actor` names the pid's actor by its state record `{ s : String }`; handler-result and
state-field errors don't name the actor; `actor_handler_state_type` is off-style. Survey the remaining actor
checks (call/reply, spawn, supervision, migrate_state, @[remote], pid_serialize, codec_missing). specs/plans/2026-11-02-diagnostics-depth-plan.md §F2.

2026-11-03: targets 1–4 landed (`specs/progress/2026-11-03-diag-actor-messages-f2.md`). Open: target 5,
the survey of the remaining actor checks (call/reply type, `spawn` of a non-actor, supervision specs,
`migrate_state`, `@[remote]` routing, `pid_serialize`, `codec_missing`), and `send_wrong_actor`'s
"spawned on line N" (it labels the actor's declaration instead).
