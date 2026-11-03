# `[P2]` An actor handler matching on a LinearMap.take_slot tuple leaked per message (FIXED)

Found by the 2026-10-12 LSan sweep (`linear_map` reports `Host_Step` /
`Host_Open` cells and the Map nodes under them) and confirmed per message in a
`live_allocs` loop: an actor with `state { done : Int, sessions :
LinearMap(Int, S1) }` leaks 2 objects per `Step` message for an absent id and
about 17 per Open + four Steps. The same handler body as a plain function over
a record (`fn step(state : St, ..) : St`) is flat, and handlers that update the
state after matching on a List field (`match state.xs do Nil -> { state with
.. } ..`) are flat too.

```march
on Step(sid : Int, last : Bool) do
  match LinearMap.take_slot(state.sessions, sid) do
    (None, slot) -> { state with sessions: LinearMap.vacate(slot) }
    (Some(s), slot) -> ..
  end
end
```

What the post-Perceus TIR (`--dump-tir`) shows: `state` is built from the
fields loaded out of `$actor` (`Lower_actor`), `state.sessions` is rewritten to
`$sf_sessions` and dup'd (`inc_rc`) because `state` also holds it, and
`take_slot` consumes that dup. The tails are `{ state with sessions = .. }`,
and `state` is released only on the non-exhaustive match's panic arms; on the
normal paths there is no release of `state`, so the cell and its reference to
the old map leak. Instrumenting the ELet aggregate scope-end drop in
`Perceus_core.insert_rc_expr` shows every precondition true for `state` in
`Host_Step` (including `drop_agg_at_tails` returning `Some`), so the drop is
emitted and something later removes or absorbs it (an in-place `EUpdate` /
reuse of `state`'s cell that overwrites the old field without releasing it is
the first suspect). Not chased further on the lsan-leaks branch.

Repro: `test/native/linear_map.march`'s Host actor driven 200 times with
`Open(i)` and `Step(i, ..)`, `live_allocs` before and after.

## Fixed 2026-10-12

**Which pass dropped it: none.** The post-Perceus TIR (`MARCH_DUMP_TXT=tir-perceus`)
already had no release of `state` on the normal paths, and disabling every
optional pass (`--disable-pass opt`, `known-call-pre`, `beta-adt-pre`,
`join-points-pre`, `simplify-pre`, `hof-spec`) left the leak at 2 per message.
The drop was never placed. `drop_agg_at_tails` (`lib/tir/perceus_core.ml`) did
return `Some`, but what it returned was the scope unchanged.

The scope of `state` is `let $result = <match> in <write-back>`. The match is
non-exhaustive in TIR, and its two panic arms release `state`. `go`'s first arm,
`releases_var name x && not (is_branching x) -> x`, is meant for a path that
already released `v`. But `is_branching` looks only at a let's BODY, and the
write-back after `$result` has no case in it. So the whole let counted as one
non-branching path that "already releases `state`" and was returned untouched:
no drop on any path. The next arm (`ELet (_, e1, _) when releases_var name e1 ->
x`) would have done the same.

**Fix.** Ahead of those two arms, a new arm handles a let (or seq) whose RHS is
branching, releases `v` on some of its paths, and has `v` dead after it. `go`
now descends into the RHS, so each path that does not release `v` gets the drop
at its tail (bound before the release), and the panic paths keep their own.
This is the same per-path placement the existing "paths of `e1` disagree" arm
does for an RHS that hands `v` over on some paths.

**Verification.**
- `test/native/actor_tuple_match_state_leak_probe.march`, `live_allocs` over
  5000 absent-id Steps, 2000 x (Open + 3 Steps), and 3000 messages to a
  shared-state control (one arm returns `state` itself, the other builds the
  new state from a String projected out of the old one through the tuple).
  Before: 10000 / 30000 / 6001. After: 0 / 0 / 3.
- `test/native/linear_map.march` golden unchanged; TIR snapshots unchanged.
- The Linux ASAN error pass over the full native sweep is clean.
