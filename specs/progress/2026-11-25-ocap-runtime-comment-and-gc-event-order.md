# Two small ocap phase 4 runtime nits (2026-11-19)

Found by the ocap phase 4 Task 10b review. Both are cosmetic, filed together
because each is a few lines in runtime/march_runtime.c:

- The comment on the supervised respawn path (around line 7495 at the time,
  near the `g_supervise_mu` leaf-lock contract) still describes how the child's
  authority was carried before Task 10b. Reword it to say the respawn reuses the
  authority of the child's first spawn.
- When two threads race to install a cached authority cell, the CAS loser emits
  its gc "immortal" event before it resets the cell's refcount, so a
  `MARCH_TRACE_GC` trace shows the events out of order for that cell. Emit the
  event after the reset.

## Closed 2026-11-25

- The respawn comment already says the replacement runs under "the slot's FIRST spawn's
  authority (march_sup_child.first_auth)"; nothing to reword.
- `march_cap_nil` and `march_cap_push_top` emit the "immortal" event only after winning the
  compare-and-swap. A loser's cell is made mortal again and released, so it now has no
  "immortal" event at all, where it used to have one ahead of its "free".

No test: the losing branch needs two threads racing on the first use of one cache entry, and
the single-threaded order of events is unchanged (the event follows the store by one
compare-and-swap). Checked by reading a `MARCH_TRACE_GC` trace of
`test/cap_conformance/panic_caught_mortal_mark`: the same "immortal" events before and after.
