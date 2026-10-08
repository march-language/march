# `monitor` leaked a reference to both of its actors

**FIXED 2026-10-07.** Found chasing the last objects a cluster session leaves behind
(after specs/progress/2026-10-07-mixed-tail-aggregate-leak.md).

## Finding it

A referrer scan of the session probe's survivors showed per-party actor records with
refcount 1 and no heap referrers: a 72-byte `SessionNode.Endpoint` (allocated in
`SessionNode.party`) and a 40-byte `ClusterNode.RegWatch` (in `h_register`), both of them
actors that had already been killed. `h_register` spawns a `RegWatch` per registered name
and calls `monitor(w, holder)`. A probe that spawns a target and a watcher, monitors, and
kills both left 2 objects per pair in either kill order, and 0 without the `monitor`.

## Cause

`monitor` sat in `Borrow.extern_owned_builtins`, so every call site handed
`march_monitor` one reference to each pid. `march_monitor` keeps neither: it never stores
the target, and its monitor node stores the watcher as a raw pointer with no reference of
its own. So each monitor leaked a reference to both actor records, which then outlived
their actors.

Borrowing both would not have been enough. The node's watcher pointer is looked up by
address when the `Down` is delivered (`deliver_monitor_down` -> `find_meta`), so a
watcher freed while the node is still linked could have its address reused by another
actor. The leaked reference was what kept that address unique.

## Fix

- `Borrow.extern_borrow_table`: `("monitor", [false; true])`. The watcher is owned, the
  target only read.
- `runtime/march_runtime.c`: the monitor node owns the watcher reference it was handed,
  released wherever a node goes away: after delivery at the target's death, at once when
  the target is already dead or invalid (no node is linked), on `demonitor` (outside
  `g_tbl_mu`, since the last release of a record runs its destructors), and when a meta
  that never died is freed.

## Evidence

`test/native/monitor_releases_actors.march`: under 5 objects left over 50 pairs on every
path that frees a node (watcher killed first, target killed first, demonitored, monitor of
an already-dead target), and a watcher still receives its `Down`. RED on main on all four
paths, GREEN after. Session probe, this fix alone: ~79 -> ~75 objects per session.
