`[P3]` **`Diagnose`: `rc.climb` fires alongside `mailbox.growth`.**

Found while writing the operator guide (`docs/observe.md`, PR #787). A
growing mailbox is itself a growing count of live heap objects (each queued
message is one or more), and the actor count does not change, so a node with
one backed-up actor reports both `mailbox.growth` and `rc.climb`. The second
sends an operator looking for a leak that is not there.

**Fix:** subtract the window's growth in queued messages (`MEM`'s
`queued_messages`, already in the snapshot) from the live-object growth
before applying the 10% threshold, or suppress `rc.climb` when
`mailbox.growth` fired in the same window and say so in the finding's text.
Same change in `forge/lib/diagnose.ml` and `stdlib/diagnose.march`, plus a
shared fixture (`forge/test/fixtures/diagnose/`) that grows one mailbox and
must yield only `mailbox.growth`.
