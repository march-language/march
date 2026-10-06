`[P3]` **`forge diagnose` / `Diagnose`: coverage does not say the snapshot is capped.**

Found while writing the operator guide (`docs/observe.md`, PR #787).
`diagnose` reads two `SNAPSHOT`s, and `SNAPSHOT` returns at most the top 100
actors and the last 20 crashes. On a node with more actors, `mailbox.growth`
and `mailbox.over_limit` never see an actor outside the top 100 by mailbox
depth, and `crash.loop` counts only the last 20 crashes, so a loop
among many crashing supervisors can be under-counted. The envelope's
`coverage` lists every probe as `ran` regardless.

**Fix:** either report the caps in `coverage` (`partial`, with the row and
crash counts the snapshot had against the node's totals, which `MEM` and
`CRASHES`' `total` already give), or have diagnose ask for the larger
`ACTORS`/`CRASHES` limits when the node's totals exceed them. Both
implementations (`forge/lib/diagnose.ml`, `stdlib/diagnose.march`) and the
shared fixtures move together.
