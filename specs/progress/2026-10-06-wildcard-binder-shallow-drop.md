# A value bound by a wildcard in a tuple or constructor pattern was freed shallow

**FIXED 2026-10-06.** The `Deque` cells a cluster session left behind (~7 per session,
allocated in `Deque.pop_front`) and part of what every NodeQueue frame cost.

## Finding it

Allocation-site tracing put two survivors per session at `Deque.pop_front$Deque_T_Int_Int_Bytes`:
the two `Nil` cells of `empty()` on its `Deque(0, _, _) -> (None, empty())` arm. A referrer
scan found nothing pointing at them (rc 1, unreachable), and the deque cell and the tuple
around them were freed, so whoever released the deque released it shallowly. The caller is
`NodeQueue.admit_waiting`:

```march
match Deque.pop_front(st.waiting) do
  (None, _) -> st
  (Some((_key, seq, frame)), waiting2) -> ...
```

In the final TIR the `None` arm ends `dec_rc $f33519`, never rewritten into
`__drop$Deque_T3_Int_Int_Bytes`, and `$f33519`, the binder lowering made for the `_`, is
typed `TVar`: nothing pinned it. `Drop.rewrite_dec` routes a release through the type's
drop function, and a type variable has none, so the release stayed `march_decrc`, which
frees the cell and nothing in it. The same happened inside `pop_front` to the second `_`
of `Deque(0, _, _)`.

## Fix

`Drop.refine_binders`: on each `ECase`, a binder typed `TVar` takes the type its position
has in the scrutinee's type, a tuple's element or a constructor's field with the type's
arguments substituted (through `droppable_ctors`, which declines whenever the layout is in
doubt). `rewrite_dec` uses the refined type. Only releases change; a binder that is not
erased is left alone, and a position whose type is itself a variable is not recorded.

## Test

`test/native/wildcard_binder_drop.march`: `admit_waiting`'s shape over a record holding an
empty `Deque`, 100 calls, live objects unchanged (RED before: 200 left). The session probe
(`session_party_released`) went from ~86 to ~72 objects per session.
