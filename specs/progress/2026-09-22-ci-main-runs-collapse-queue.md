# CI: main runs share a concurrency group so a merge burst queues one run, not N

**Landed:** 2026-09-22 (directly on main)

## Problem

`ci.yml` grouped main pushes by `run_id`, so every merge queued a full ~35-job
run and none ever cancelled. On 2026-09-22 a burst of ~12 merges between
11:35 and 12:12 UTC put ~400 jobs ahead of every PR on the org's 20-slot Linux
budget; PR jobs waited 80+ minutes to start, and the tail job
`property-coverage` (a one-minute coverage assertion that depends on all six
property-test shards) sat queued for a further half hour after its inputs
were ready.

## Change

- `concurrency.group` is now `ci-<pr number or ref>`; `cancel-in-progress` is
  true only for `pull_request` events.
- GitHub keeps at most one running + one pending run per group and cancels the
  older pending run when a newer one arrives. Main's in-flight run still
  finishes and gets its verdict; queued main runs collapse to the newest.
- `nightly.yml`'s gate already skipped `cancelled` conclusions; its comment
  and `.github/workflows/README.md` now describe the new reason a main run can
  be cancelled.

## Trade-off

Intermediate main commits in a burst get no CI verdict. Attribute a red main
by dispatching CI on the specific commit or running the suite locally.
