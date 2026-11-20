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
