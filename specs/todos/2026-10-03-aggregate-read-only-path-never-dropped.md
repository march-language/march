# `[P3]` Compiled leak: an owned record that is consumed on one path and only read on another is never dropped there

Filed 2026-10-03, found while fixing
[../progress/2026-10-01-compiled-record-with-projection-sigsegv.md](../progress/2026-10-01-compiled-record-with-projection-sigsegv.md).

A record or tuple is read only through `EField` (and as an `EUpdate` base), so it has
no release on its read path. Perceus gives it one in two places: the ELet scope-end
drop and `insert_owned_aggregate_param_drops`. Both require
`used_only_as_field_source`: the aggregate is never handed off anywhere in the scope.
One consuming use anywhere (a call argument, a constructor capture, a closure
capture, an arm returning it) disqualifies it, so a path that only reads it keeps its
reference forever.

Two shapes, both measured with `live_allocs()`, compiled, on the branch that fixed the
todo above (and on main):

```march
-- 1. consumed on some paths, only read (as a `with` base) on one: the Some arm
--    never drops `rep` (about 10 allocations per call in a 2000-iteration loop)
fn (rep : Rep) ->
  let l = leader_state()
  let rep2 = if rep.detail != "" do rep else match List.find(l.obs, fn o -> o.report.node == rep.node) do
    Some(o) -> { rep with detail: o.report.detail }
    None -> rep
  end end
  leader_report(l, rep2)

-- 2. handed to a consuming call (dup'd, since it is live after), then only read
let r = mk(n)
let a = ser(r)
let b = ser(r)
String.byte_size(r.signature)   -- r is never dropped
```

The fix is probably the per-path rule `insert_owned_aggregate_param_drops` now uses for
releases, extended to consumption: on each path, the aggregate is still owned at the
tail if its last mention there is a read (an un-dup'd consuming use is always its last
mention, since Perceus dups a use that is live after). Both scope-end drops would then
drop it at that path's tail. Check the ELet one and the parameter one together, and
re-run the ASAN corpus sweep: this widens where drops appear.
