`[P2]` # Interpreter does not carry registered names across a supervisor restart

**Backend parity gap.** `Actor.register` / `whereis` / `unregister` /
`registered` behave identically compiled and interpreted. **Restart
carry-forward does not** — it is compiled-only.

Found during the named-registry work
(`specs/progress/2026-08-12-named-registry.md`); the 9-task plan scoped
names-survive-restart to the compiled runtime, so this was never implemented on
the interpreter side rather than being broken by it.

## The bug

`lib/eval/eval.ml:2188-2196` — `spawn_child_actor`'s re-registration block on a
supervisor restart consults `pid_to_registry_name` and writes `process_registry`.
Those are the **old atom-based** process-registry tables. `named_registry`
(`lib/eval/eval.ml:172`) is a different `Hashtbl` and is the one
`Actor.register`/`whereis` actually use — it is never touched there.

The other half: `lib/eval/eval.ml:2460-2465` (the interpreter's mirror of the
runtime's `registry_retire_actor`) drops the dying actor's names from
`named_registry` **unconditionally**, with nothing capturing them first. So even
if the respawn path were taught to re-register, there would be nothing left to
re-register from.

The compiled runtime does both halves: `capture_reg_names_pending` snapshots the
names onto the (never-freed) `march_actor_meta` immediately before
`registry_retire_actor` wipes them, and `march_respawn_child` consumes the stash
onto the replacement child.

## Reproduction

`test/native/actor_registry_restart.march` is a native golden, so it only ever
runs compiled. Run it through the interpreter:

```
./_build/default/bin/main.exe test/native/actor_registry_restart.march
registered: true
respawned with new pid: true
lost after restart
respawned again with new pid: true
lost after second restart
```

against `test/native/actor_registry_restart.expected`, which says
`reached by name after restart` / `reached by name after second restart`.

## Suggested shape for a fix

Mirror the runtime's capture/consume pair, which is the shape the compiled side
already proved out:

- capture the dying actor's `named_registry` names before the drop at
  `eval.ml:2460-2465` — including for live siblings killed by `one_for_all` /
  `rest_for_one`, which is the case the compiled side got wrong on its first
  attempt (the capture gate was `supervisor != NULL`, and those strategies null
  the field out before killing the sibling — see
  `specs/progress/2026-08-12-named-registry.md`);
- consume it in `spawn_child_actor`, writing `named_registry` rather than
  `process_registry`;
- keep the "first live claim wins" rule: if another live actor took the name
  during the restart window, drop the carried registration rather than stealing
  it back.

## Acceptance

`test/native/actor_registry_restart.march` and
`actor_registry_restart_batch.march` produce their `.expected` output when run
through the interpreter as well as compiled. Pin it — this is exactly the class
of divergence that hid compiled `mailbox_size` returning the `Down` count.

Until then: the actors docs and `CHANGELOG.md` both state the split explicitly.
Do not let either drift back to an unqualified "identical semantics in both
backends" while this is open.
