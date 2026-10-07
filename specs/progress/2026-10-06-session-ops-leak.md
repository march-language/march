# A cluster session's Party (and its 13 table handles) outlived the session

**FIXED 2026-10-06.** The largest part of what a cluster session still left behind after
specs/progress/2026-10-06-record-ownership-drops.md (~156 objects per session on the
single-node probe).

## Finding it

Allocation-site tracing showed the `Party` record and its 13 Vault handles surviving every
session. A scratch runtime then kept a table of live objects (allocation site per object)
and, at exit, listed every live object pointing at a 160-byte `Party`: only the closures
allocated in `SessionNode.ops`, held by the 96-byte `Ops` record. Logging every
inc/dec of those `Ops` records (the inline RC fast path defers to the runtime while
tracing, so every operation is seen) showed two separate faults.

## 1. Every Session operation leaked a reference to the session's Ops

`Session.emit` / `register` / `suspend` / `close` are

```march
match cap_dict(c) do
  Some(d) -> d.emit(ep, to, msg)
```

`cap_dict` consumes `c` and hands it back as `Some(d)`, `d` the same `Ops` record, read
only through a field. `d : Ops` names `Session.Ops` by its short name, so
`Perceus_core.is_aggregate_ty` (an exact lookup) did not see a record: no aggregate
scope-end drop, and a record read only through fields has no other release. One reference
per operation: four per party for a Ping session (register, emit, suspend, close).

Fix: `Kind.record_fields_short` (moved from `drop.ml`, where #812 added it for the drop
helpers) resolves a record's short name, and `is_aggregate_ty` uses it.

## 2. The capability's last release was shallow

The session capability IS the `Ops` record (`Session.attach` -> `cap_impl` stores it as
the capability's dictionary), but a reference released as `Cap(Session.Live)` is released
as one cell: the compiler cannot know which dictionary a `Cap` carries. When the last
holder let go, the record was freed and its ten closures, every one capturing the `Party`,
leaked, and with them the Party's table handles.

Fix: the runners (`run_cluster_party`, `serve_party`) keep a reference of the record's own
type, `o = ops(p)`, and release it last (`retire_ops(o)`), after the tables are closed, so
the final release is the deep one.

## Effect

Single-node cluster session probe: ~156 -> ~92 objects per session. What is left: the
registry's per-session names (tombstones, kept by design; see the tombstone todo) and the
endpoint actor's per-party state.

## Test

`test/native/session_party_released.march`: 20 sessions, under 120 objects left per
session (RED before: ~156).

## Left

Any other capability with a dictionary (`Cap(ClusterNode.Live)`'s `ClusterOps`) has the
same shallow last release; it is made once per node, not per session.
