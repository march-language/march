`[P4]` A restarted child's registered names resolve before it can take messages

Found 2026-10-12 while fixing `specs/progress/2026-10-12-supervisor-child-slot-race.md`.

`march_respawn_child` (`runtime/march_runtime.c`) re-registers the crashed incarnation's
names on the replacement (`march_actor_register`) *before* `activate_actor_green_thread`.
In that window `whereis(name)` returns the replacement's pid and `is_alive` says true,
but `march_send` finds no green thread (`meta_gt` is NULL, `MARCH_SEND_DEAD`) and drops the
message. `specs/lang/actors.md` promises that a name holder "keeps reaching whichever
incarnation is current", so a send by name that lands in the window is lost to an actor
that then lives on.

The child-pid state word had the same window and now publishes after the activation.
Names were left alone because registering them after the activation opens a different
hole: a replacement that crashes before its names are registered would not stash them for
its own replacement (`stash_child_for_restart` reads the meta's `reg_names`), so the names
would be lost for good.

## Options

- Register after activation, and if the replacement is already dead when a registration
  fails, put the remaining names back on the slot's `pending_names` (under
  `g_supervise_mu`) for the next respawn to take.
- Make `march_send` to a meta that is alive but not yet activated wait briefly for the
  activation (it is a few non-switching C statements away), instead of reporting DEAD.

No test pins it yet: it needs a sender looping `whereis` + `send` against a crash-looping
child at 14 schedulers, asserting every message to a live incarnation is handled.
