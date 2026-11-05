# Actor diagnostics: F2 style leftovers

Follow-up to §F2 of `specs/plans/2026-11-02-diagnostics-depth-plan.md` (PR #1102,
`specs/progress/2026-11-03-diag-actor-messages-f2.md` and `…-f2-survey.md`): three messages
still carried their advice as an inline "hint:" line.

- `codec_missing` at `Node.send` / `Node.enqueue` (`Typecheck_caps`, the `node_send_sites`
  sweep): the second line says why a codec is needed (the message crosses the network as JSON,
  its type's name is its wire tag, a receiver decodes it with `from_json`) and "Add `derive Json
  for T` next to its declaration." is a note, as in the `@[remote]` case. The unresolved-type
  branch ("cannot choose a codec") gets the same shape.
- `io_not_allowed` for a hot-reload migration (`check_migrate_fn_io_free`): names the actor by
  the runtime's convention (`counter_migrate_state` → `Counter`, as `llvm_toplevel.ml` forms
  `@__migrate_Counter`): "`counter_migrate_state` migrates actor `Counter`'s state, and
  `migrate_state` must be IO-free, but it calls capabilities that need `IO.Console`." The advice
  is a note naming the actor. The "`migrate_state` must be IO-free" fragment the alcotest cases
  match is kept.
- `actor_init_arity` (`check_spawn_args`): a label on the actor's `init`, the parameter list
  ("`Counter`'s `init` parameters") or, for the bare form, the init expression ("`Plain`'s
  `init` takes no parameters"). `DActor` records it as `actorinit:<A>` in `env.decl_sites`. The
  message now starts with a capital ("Actor `Counter`'s init takes …"), as the corpus lint
  requires.

Corpus: `actor_init_arity_1` / `_2` added; `io_not_allowed_2` now declares the actor its
migration names; `codec_missing_1`, `_2`, `_5` and `io_not_allowed_1`, `_2` regenerated.
