# `[P3]` Three step-6 behaviours have no test that fails when they are removed

Filed 2026-09-24 by the distributed-deploys review (step 6, PR #612). Each was
checked by perturbing a scratch copy of the runtime at `origin/main`
(d3396f743), rebuilding `test_dispatch` and `test_hcr_migrate_order` with the
`test/dune` `cc` lines, and running both. All three stayed green: 60/60 and
all checks passed.

1. **Markers for actors spawned at an older epoch (deviation 2).** Made
   `hcr_spawn_marker` (`runtime/march_runtime.c:6104`) return at once. Green.
   Without it, an actor spawned by an old-epoch parent never gets a marker and
   pins its epoch for ever.
2. **Markers for every live actor, not only hot-reload ones (deviation 2).**
   Made `hcr_mark_all` (`:6050`) skip actors with `dispatch_name_id == 0`.
   Green. Without it, non-reloadable actors pin their spawn epoch for ever.
3. **The epoch is written before a version becomes live** (the plan's fourth
   "Bugs found" item, fixed by #551 and kept by staging). Moved the epoch store
   in `runtime/march_dispatch.c` from `march_dispatch_stage` to after the
   `live`/`current` stores in `march_dispatch_commit`. Green. That is the
   original bug's shape. It is a race, so this needs a threaded reader that
   asserts it never sees a live version with a stale epoch, as
   `test_reclaim_race_threads` does for the reclaim.

Also: `SessionNode`'s `HoldEpoch`/`ReleaseEpoch` have no behavioural test at
all (only `session_node.march` names them), and the hosted-API test checks
generated call counts, not behaviour.

## Fix I would make

Add a `test_hcr_migrate_order.c` case per item. For 1: an actor spawned by an
epoch-1 parent after a deploy advances before its first message. For 2: a
non-HCR actor's pin moves to the new epoch. For 3: a two-thread stage/commit
versus `enter_gen` loop. Then add a compiled session test through the reload
socket for the holds.
