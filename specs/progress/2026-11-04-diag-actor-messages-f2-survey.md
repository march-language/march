§F2 of `specs/plans/2026-11-02-diagnostics-depth-plan.md`, target 5 (the survey of the remaining actor
checks) and `send_wrong_actor`'s spawn site. Closes the todo filed 2026-11-02 (targets 1–4:
`specs/progress/2026-11-03-diag-actor-messages-f2.md`).

- `send_wrong_actor`: when the pid is a `let x = spawn(B)` binder, "this pid is an actor `B` (spawned
  on line N)" and a label "`x` is spawned from `B` here" on the `spawn` replace the actor-declaration
  label (kept as the fallback). The `ELet` arm records `spawnat:<binder>` in `env.decl_sites`;
  `check_send_target` takes the pid expression (`?pid_expr`) and resolves it through `binder_spans`.
- `spawn` of a non-actor (new code `spawn_not_actor`, explain page): a function, a type's constructor
  or an actor's message passed the checker and failed in lowering (`helper_spawn … is not a function
  in scope`) or at run time; a constructor with arguments was a `constructor_arity` error. Now "`Bump`
  is a message of actor `Counter`, not an actor, so `spawn` cannot start it." An actor is recognised by
  the new shared `env.actor_names` registry (filled where each actor's name constructor is
  registered), falling back to a self-typed nullary constructor that is no declared type, or a name
  bound to a `Pid`. A name nothing declares reads "I don't know an actor called `Countr`. Did you mean
  `Counter`?" (actors only, with a fix) instead of "(from type `Counter`)".
- Supervise blocks: a child line naming no actor gets the same two errors; a field missing from the
  supervisor's state (new code `supervise_field_missing`, explain page) was an internal error in
  lowering ("supervise field wx not found in actor state"); now it names the actor and the child, with a
  did-you-mean and an `FReplace` fix. A misspelt `strategy` word is "I don't recognize `strategy
  one_for_none`" with the three strategies, raised from `restart_strategy_tok` like `shutdown`'s
  (`mk_strategy_word`; no new accepted syntax, menhir conflict count unchanged at 7).
- `duplicate_handler`: house style ("Actor `Counter` has a second handler for `Bump`, and a message
  reaches only one."), labels the first handler.
- `remote_actor_unroutable`: on the standard renderer, primary span the actor's name (was the whole
  declaration), one label per handler with the reason it is not routable.
- `codec_missing` from a generated `@[remote]` dispatch was reported twice (tag and schema test) at
  generated `<none>` spans. It is reported once per payload type, at the handler's annotation, which
  `DActor` records as `remotepayload:<Actor>.<Msg>:<Type>`.
- `pid_serialize`: names the field or constructor holding the pid and labels it; the advice moves to a note.
- Surveyed and left: `migrate_state` IO (`io_not_allowed`), `actor_init_arity`, `spawn_computed_actor`,
  a `migrate_state` return type (an ordinary return mismatch). `Actor.call`/`Actor.reply` are untyped
  (`actor_call` is polymorphic in the reply), so a wrong reply type is accepted: filed as
  `specs/todos/2026-11-04-actor-call-reply-untyped.md`, an inference item.
- The internals allowlist had no actor entries left; its `S_end` line is F3's.
