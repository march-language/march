# DD review: the unconfirmed findings, triaged

`specs/todos/2026-09-24-dd-review-unconfirmed.md` listed five findings read from code
without a repro. Each is now decided; the file is deleted.

1. **Link reader tasks pin the startup epoch and stamp remote deliveries.** Confirmed
   in part: in the forge upgrade test, 6 task units still pinned epoch 1 20 s after
   the deploy, while a plain program drains to zero. Filed as
   `todos/2026-09-25-dd-review-link-reader-tasks-pin-epoch.md`.
2. **The actor loop does not handle a NULL from `march_dispatch_enter_unit`.**
   Dismissed: unreachable. A unit's own epoch is pinned, so the reclaim condition
   never retires the version it selects, and `enter_gen` only returns NULL after a
   retire. (The ABA found in `enter_gen` the same day also needs an unpinned caller.)
3. **The SIGTERM drain counts only offer sessions.** Confirmed from the code
   (`Topology.running` has no other input). Filed as
   `todos/2026-09-25-dd-review-sigterm-drain-ignores-initiated-sessions.md`.
4. **The loopback link outlives `ClusterNode.stop`.** Confirmed from the code
   (`h_stop` never closes it; `deliver_loopback` ignores `stopped`). Filed as
   `todos/2026-09-25-dd-review-loopback-link-outlives-stop.md`.
5. **Placement changes leak actors.** Confirmed for the `AlreadyOffered` path and
   for `close_offer` never stopping its `OfferActor`. Dismissed for "retired offers
   are never removed from `draining`": `watch_draining` drops them once idle. Filed
   as `todos/2026-09-25-dd-review-offer-actors-leak.md`.
