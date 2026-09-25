# `[P3]` Name the units that still pin an old epoch after a deploy in a topology app

**Filed** 2026-09-25 while closing `specs/progress/2026-09-25-migrate-msg-actor-message-tags.md`.

In `forge test --upgrade-from` on `forge/test/fixtures/upgrade/migrates`, 20 s after
the deploy (every test session done, the feeder task finished at about 6 s), forge
reported:

```
upgrade: app-1: 1 actor(s) still on an old epoch 20 s after the deploy (holding it for an unfinished session, or in a nested receive); ...
upgrade: app-1: epoch 1 (6 unit(s)) still pinned by units that are not actors (tasks); only a hard drain deadline (MARCH_HCR_HARD_DRAIN_MS) stops those
```

A plain program with the same actor and feeder drains to zero old-epoch pins (the
HCR migrate_msg test asserts it), so the base epoch has no pin of its own. The six
units are long-lived tasks, which by design never advance (II.4.3): candidates are
ClusterNode's link reader tasks (see the review's unconfirmed item 1, now
`2026-09-25-dd-review-link-reader-tasks-pin-epoch.md`), the topology placement loop,
listener/acceptor tasks and the SWIM driver. The actor is probably `RegWatch`
(nested receive) or a held `Endpoint`.

**Do.** Give PINS (or a debug env var) a per-unit listing (task/actor, spawn
function or actor name, epoch), identify the six, and decide per unit: advance it
(re-spawn at the current epoch), or document it as a permanent pin that only a hard
drain deadline clears.
