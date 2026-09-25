# A cluster-mode session party takes an epoch hold it never releases

**DONE 2026-09-24.** Every party exit passes `end_party`, which releases the hold and
kills the Endpoint actor (its reap drops the pin): `finish`, the cluster runner's
success and three error arms, and the standalone runner's join failure. `initiate`'s
`ApInbox` actor, leaked once per initiated session, is killed too. Test:
`test/two_node/cluster_ap_local` measures `Scheduler.live_procs()` before and after
the two offered sessions and again around the hosted and pair sessions, and prints
`procs retired ... true`; with `end_party`'s kill removed it prints `false (4 over)` and
`false (3 over)`. A `PINS`-through-a-deploy test needs a local reload client, which
`forge deploy hot` does not offer (SSH only); the live-proc count is what a session
leaves behind. Filed 2026-09-24; the text below is the finding as filed.

Filed 2026-09-24 by the distributed-deploys review of `12c062761..d3396f743`
(step 6, PR #612, commit 753336d36). Plan: II.4.4, D28.

## Defect

`SessionNode.party()` sends its new Endpoint actor `HoldEpoch()`
(`stdlib/session_node.march:802-806`). The only `ReleaseEpoch()` is in
`SessionNode.finish` (`:1224-1225`), and only the standalone runner calls
`finish` (`serve_party`, `:1611-1617`). Every other path that creates a party
leaves the hold in place for ever:

- `run_cluster_party` (`:1917-1970`), which backs `cluster_R`, `offer_R`,
  `offer_hosted_R`, `initiate_R` and every generated topology offer, never
  calls `finish` or sends `ReleaseEpoch`, on success or on any `Err` arm.
- `run_party`'s join-failure arm (`:1603-1606`) returns `Err` without `finish`.

The Endpoint actor is never stopped either (no `kill`/stop of `p.ep`), so its
proc stays pinned to the epoch the session formed in, its marker stays
pending (`hcr_on_marker` keeps it while `epoch_holds > 0`), and the soft
drain deadline skips it (`hcr_boundary_slow` returns early on a hold).

## Consequence

In any cluster app (every topology app), each session run before a deploy
pins that deploy's predecessor epoch for the life of the process. The hard
drain deadline is off by default (`MARCH_HCR_HARD_DRAIN_MS`, deviation 5), so:

- the versions whose interval covers that epoch are never reclaimable, and the
  third deploy that touches the same slot answers `WAIT` until
  `forge deploy hot` gives up (`MARCH_DEPLOY_WAIT_S`, 600 s);
- every epoch that saw a session keeps a pin-table entry, so after about seven
  such deploys every activation answers `WAIT … table_full`.

## Confirmed

Runtime trace, not a deploy: a scratch runtime printed a line in
`march_epoch_hold`/`march_epoch_release`, and
`test/two_node/cluster_ap_local/node_a.march` (four cluster sessions in one
process: two `offer_R`/`initiate_R`, one hosted, one `cluster_R` pair) was
compiled against it and run. Output was correct, and the trace showed:

```
HOLDTRACE hold pid=9
HOLDTRACE hold pid=11
HOLDTRACE hold pid=17
HOLDTRACE hold pid=19
HOLDTRACE hold pid=28
HOLDTRACE hold pid=30
HOLDTRACE release pid=23
HOLDTRACE hold pid=36
HOLDTRACE hold pid=38
```

Eight Endpoint holds (two parties per session), none released. The single
release is the hosted server's `finish`, on a proc that never held (see
`2026-09-24-dd-review-hosted-register-path-takes-no-hold.md`).

No test exercises `HoldEpoch`/`ReleaseEpoch` behaviourally: `git grep` finds
them only in `session_node.march`.

## Fix I would make

Release in one place that every party exit passes: send `ReleaseEpoch` (or
stop the Endpoint, which drops its pin at the reap) from `run_cluster_party`
after `serve_cluster_outcome` and on each `Err` arm, and from `run_party`'s
join-failure arm. Better still, end the Endpoint actor when its session ends,
which removes the leak of the actor itself. Add a compiled test that runs a
cluster session, deploys through the reload socket, and asserts through `PINS`
that the older epoch retires.
