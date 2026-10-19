# HCR: an actor spawned by un-redeployed code started with the old state layout — FIXED 2026-10-18

Found by code reading on 2026-09-21 while fixing
`specs/progress/2026-09-21-hcr-migrate-order-and-snapshot-cap.md`.
**Not reproduced.**

A hot-reload actor's dispatch goes through the dispatch table
(`<Actor>_dispatch`), but its initial state record does not. `<Actor>_spawn`
is inlined and DCE'd into its caller (see the comment above the
`march_actor_set_dispatch_id` emission in `lib/tir/llvm_emit_alloc.ml`), so
the `init` state is built by whichever code version of the SPAWNING function
is running. After a migrating deploy that replaces `<Actor>_dispatch`:

- a spawn site that was not redeployed (a baseline-binary caller, or a
  boundary fn whose impl hash did not change) presumably still builds the OLD
  `init` layout;
- that actor is not in the activation's snapshot, so it gets no marker and no
  pin, and dispatches the NEW code from its first message.

The same holds for an actor spawned between `march_actor_publish_migrating`'s
snapshot and its publish.

To confirm: a two-version fixture where only the actor's handlers and
`migrate_state` change, then spawn a fresh actor from the unchanged caller
after the deploy and check the state layout its first handler sees. Possible
fixes: route the init-state construction through the dispatch slot, or have
the deploy tool treat every spawn site of a schema-changed actor as changed.

## Reproduced and fixed 2026-10-18

**Reproduced** with the two-node harness scenario `test/two_node/hcr_spawn_site_layout`
(one node): a `--hot-reload` base whose actor `C` has `state { count }`, a patch that
gives it `{ count, label, extra }` and a `c_migrate_state`, deployed through the real
reload server (`test/hcr_deploy.exe`, what `forge deploy hot` does) while three spawn
sites keep spawning fresh `C`s:

| Spawn site | Before the fix | Why |
|---|---|---|
| a function called through its slot (redeployed: its impl hash moves with `C`'s inlined init) | correct (`fresh`) | new code builds the new layout |
| a task started before the deploy (old epoch) | correct (`migrated`) | its actor inherits the OLD epoch, gets a spawn marker, and migrates |
| `main`'s own closure (built by the base) | **v2 handlers on a v1 record**: garbage fields, then SIGSEGV | `main` is unpinned (epoch 0), so the actor took the CURRENT epoch, while the closure that built its state is the base's |

So the suspicion held for exactly one shape: an unpinned spawner running old code. The
"boundary fn whose impl hash did not change" case does not arise for a spawner of the
changed actor, because the inlined `init` moves the spawner's impl hash.

**Fix.** The actor-record alloc site (`lib/tir/llvm_emit_alloc.ml`) now passes the
epoch of the code building it to `march_actor_set_dispatch_id`: a patch's own
`@__march_hcr_epoch` (stamped by its `__march_init`), 0 (= `MARCH_EPOCH_BASE`) from the
base image. The runtime keeps it as `march_actor_meta.build_epoch`, and
`actor_green_thread` runs every state migration between it and the proc's epoch on the
`init` state before the first message (`hcr_catch_up_init_state`, sharing the
activation-log walk with `hcr_advance` through `hcr_migrate_state`). Nothing changes
for an actor built by code at its own epoch.

The second window the todo named (an actor spawned between an activation's snapshot
and its publish) is the same mechanism: whatever epoch the proc ends up at, the state
is brought from its builder's epoch to it.

**Also found and fixed:** `Cmd_deploy_hot.so_exports_symbol` used `nm -D`, which
prints nothing for a Mach-O image, so on macOS `forge deploy hot` never found a patch's
`__migrate_<Actor>` and refused every state-changing deploy ("@compat(full) violated
... provide migrate_state") that carried one. It now also asks `nm -g` and accepts
Mach-O's leading underscore (`forge/test/test_so_exports_symbol.ml`, red on the old
check).

**Also found, filed:** the first hot deploy onto a freshly built baseline has no old
schemas, so a state change gets no migrate bit at all
(`specs/todos/2026-10-18-hcr-first-deploy-no-schema-baseline.md`). The scenario builds
version 1 as a `.so` to supply them.

Tests: the scenario prints, per spawn site, which layouts its actors saw and how many
v2 handlers read a state that is neither `fresh` nor `migrated`; red with
`hcr_catch_up_init_state` disabled (SIGSEGV), green with it, macOS arm64.
