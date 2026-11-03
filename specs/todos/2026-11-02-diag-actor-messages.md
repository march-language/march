`[P2]` Diagnostics for actors: message payload errors don't say "message of actor `A`" or point at the
handler; `send_wrong_actor` names the pid's actor by its state record `{ s : String }`; handler-result and
state-field errors don't name the actor; `actor_handler_state_type` is off-style. Survey the remaining actor
checks (call/reply, spawn, supervision, migrate_state, @[remote], pid_serialize, codec_missing). specs/plans/2026-11-02-diagnostics-depth-plan.md §F2.
