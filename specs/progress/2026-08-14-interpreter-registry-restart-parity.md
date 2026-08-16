# Interpreter now carries registered names across a supervisor restart (RESOLVED)

**Backend parity gap — closed 2026-08-14.** `Actor.register` / `whereis` /
`unregister` / `registered` behaved identically compiled and interpreted;
**restart carry-forward did not** — it was compiled-only. It no longer is.
What follows is the original filing, then the fix that landed.

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

---

## Resolution (2026-08-14)

Mirrored the runtime's capture/consume pair in `lib/eval/eval.ml`, keeping the
*semantics* rather than the C data layout:

- **`reg_names_pending : (int, string list) Hashtbl.t`** — the stash, keyed by
  the dying actor's pid. The interpreter has no per-actor meta outliving the
  instance, but `next_pid` is monotonic and pids are never reused, so a pid key
  is as stable as the C side's never-freed `march_actor_meta`.
- **`capture_reg_names_pending pid`** — snapshots every `named_registry` entry
  owned by `pid`. Guards an existing stash rather than overwriting, matching the
  C guard.
- **`crash_actor`** calls it immediately before the existing unconditional drop,
  gated on `ai_supervisor <> None`. Unsupervised actors' names are still just
  dropped.
- **`one_for_all_restart` / `rest_for_one_restart`** call it *explicitly* for
  each live sibling, **before** `ci.ai_supervisor <- None`. This is the half the
  compiled side got wrong on its first attempt: those strategies clear the field
  purely to suppress a recursive `notify_supervisor`, so a capture gated on it
  alone silently loses every batch-restarted sibling's names even though the
  sibling is unconditionally respawned a few lines later.
- **`spawn_child_actor`** consumes the stash for `crashed_pid`, writing
  `named_registry` (the table `Actor.register`/`whereis` use) — the pre-existing
  block wrote only the old atom-based `process_registry`, which is left as-is.
  Per name: if a *different* live actor holds it, the carried registration is
  dropped rather than stolen back, matching `actor_register`'s first-live-claim
  -wins rule and `march_respawn_child`'s comment.
- Both `named_registry` reset sites (`reset_scheduler_state`, `eval_module_env`)
  clear the stash too.

## Verification

`test/native/actor_registry_restart.march` and `..._batch.march` produce their
`.expected` output interpreted, byte-identical to compiled. Before the fix the
interpreter printed `lost after restart` / `second name lost after restart` /
`lost after second restart` for the first and `child-a: lost after restart` /
`child-b: lost after restart` for the batch one.

Both fixtures gained an **interpreted CI leg** in `test/dune`
(`interp_actor_registry_restart{,_batch}.out`, diffed against the same
`.expected` the compiled rules use) — the fixtures had only ever run compiled,
which is exactly how this divergence survived. The parity is now pinned by CI.
