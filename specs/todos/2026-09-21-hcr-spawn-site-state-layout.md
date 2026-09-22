# HCR: an actor spawned by un-redeployed code may start with the old state layout (suspected)

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
