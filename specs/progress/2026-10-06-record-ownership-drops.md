# Records leaked when ownership differed between paths, or after a consuming use through a dup

**FIXED 2026-10-06.** Found by allocation-site tracing of the cluster session leak (a
scratch runtime that logs each `march_alloc` / `march_string_alloc` with its callers; the
survivors after a sentinel, grouped by allocating function and symbolized with `atos`).

Records (and tuples) are not refcounted by Perceus' general mechanism: an owned record
gets an explicit scope-end drop. Two gaps in when that drop was placed:

## 1. A release on one path stood the drop down on every path

`lib/tir/perceus_core.ml`, the `ELet` scope-end drop: it was skipped whenever any path in
the scope released the record. In

```march
match o do
  Some(e) -> if e.present && e.name != "" do Some({ e with clock: c, present: false }) else None end
end
```

Perceus releases `e` at the head of the `else` branch (dead there), so the `then` branch,
where `e` is only the base of the record update (a borrow), got no release at all:
`GlobalRegistry.unregister_own` leaked the old entry and its clock on every
unregistration. `drop_agg_at_tails` now works per path: a path that already releases the
record keeps that release, the others get the drop.

## 2. A consuming use through a dup counted as giving the record away

Perceus dups a variable before every consuming use that is not its last. The drop
placement treated ANY consuming use as a transfer, so a record passed to a function
(through a dup) and then used as an update base was never released:

```march
let st2 = { st with reg: GlobalRegistry.register_as(.., ClusterNode.identity_of(st, st.me)) }
```

leaked the whole old `ClusterNode` state on every registration. `path_counts` /
`covered_by_incs` count, per path, the consuming uses and the `inc_rc`s of the record: a
path whose consuming uses are all matched by incs still owns it at its tail, a path with
an unmatched one (a real last-use transfer: returned, stored, passed last) does not.
`drop_agg_at_tails` carries that balance along each path, and the owned-parameter pass
(`insert_owned_aggregate_param_drops`) uses `covered_by_incs` the same way. A path the
analysis cannot judge (an alias of the record, a match on it, a capture, sub-paths that
disagree) is left without the drop: a leak at worst, never a double release.

## Effect

`ClusterNode` register + unregister of one name, pure core: 29 objects per pair → 1
(with the nominal-record fix, specs/progress/2026-10-06-nominal-record-short-name-drop.md).
Snapshot `test/snapshots/perceus/nested_record_field_capture.expected` gains the release
of `my_id` after its last read (it was stored in `h` through a dup and then leaked).

## Test

`test/native/record_ownership_drops.march`, legs 1 and 2 (red on main before the fix).
