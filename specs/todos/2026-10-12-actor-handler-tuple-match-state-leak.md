# `[P2]` An actor handler matching on a LinearMap.take_slot tuple leaks per message

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
