# A supervisor compiles and runs under `--hot-reload`

Landed 2026-10-02 (#764, merged 2026-10-03 as 7971248fd; it closes the P1 todo
`2026-10-02-supervise-block-fails-to-compile-with-hot-reload.md`, removed 2026-10-04). Found on origin/main 88397fbdb: any program with an actor
that declares a `supervise do ... end` block failed to compile with
`--hot-reload <Prefix>`:

    error: use of undefined value '@$sup_child_ptr_a'

Fixing the compile error exposed two runtime problems behind it, so three
fixes landed together.

## 1. The spawn glue skipped the children (`lib/tir/lower_actor.ml`)

Under `--hot-reload` an actor's state lives in a separate `<Name>_State`
record that the spawn glue hands to `EAlloc` whole, so `spawn_with_fields`
was just `spawn_inner`. That also skipped the per-field fold that spawns
each supervise-block child and binds `$sup_child_ptr_<f>`, while `wrap_sup`
still emitted `register_supervisor_child(..., $sup_child_ptr_<f>, ...)`. The
unbound local reached LLVM emission, which treats an unknown name as a
global function, hence the call to `@$sup_child_ptr_a()`.

The fold is now `bind_init_fields`. A hot-reload supervisor runs it too,
then rebuilds the state record from the `$init_<f>` vars (so supervised
fields hold the children's pids, not the `init` placeholders) and allocates
the actor with that record. The binding shape is the same as in the
non-hot-reload path, so `cap_passing.ml`'s `supervised_children` (which
matches it by shape) still finds the children. Hot-reload actors without a
supervise block and every non-hot-reload actor lower exactly as before.

## 2. The runtime read child pids from the wrong word (`runtime/march_runtime.c`)

Every supervisor site (restart, one_for_all / rest_for_one batches, tree
teardown in `march_actor_stop`) read a child's pid at
`((int64_t*)supervisor)[4 + word_idx]`. Under hot-reload word 4 is the
`$f_state` pointer and words 5+ are past the struct, so teardown stopped
whatever actor a garbage pid named (in the repro, the unrelated `Log`
actor: "log error: actor not alive") and a restart wrote out of bounds.
The compiler now ORs `MARCH_SUP_SLOT_IN_STATE` (`1 << 32`) into the
`word_idx` it passes to `register_supervisor_child` under hot-reload, and
the new `sup_child_slot` helper follows `$f_state` for a flagged slot. All
six sites go through it.

## 3. `get_actor_field` could not see hot-reload state

- `march_get_actor_field` (`runtime/march_extras.c`) only searched the actor
  struct's shape. On a miss it now follows the struct's `$f_state` field
  into the state record.
- A handler rebuilds the state record through `emit_reuse_ctor`, which left
  no shape id on the result, so the lookup answered None after the first
  message. Under hot-reload (`ctx.hr_config <> None`) the reuse now restamps
  the shape when the type is an actor state record
  (`Tir_names.is_actor_state_name`). Non-hot-reload IR is unchanged.

## Verification

- Regression: `native_actor_on_stop_tree_hr` in `test/dune` compiles
  `test/native/actor_on_stop_tree.march` with `--hot-reload Main` and diffs
  it against the same golden as the plain build. It fails to compile without
  fix 1. With fix 1 but without the slot flag (fix 2) it is red with
  "log error: actor not alive".
- Every `test/native` program with a `supervise` block and a golden (20 of
  them), built with `--hot-reload Main` (and `supervisor_deflected_crash_absorbed`
  run with its rule's env), matches its golden. All 20 failed to compile
  before.

## Known limitation

`word_idx` is an index into the state record's layout when the supervisor
was spawned. A hot patch that migrates the supervisor's state to a layout
with different field order would make a restart write the wrong slot. That
is not new: nothing re-registers supervisor children on migration.
