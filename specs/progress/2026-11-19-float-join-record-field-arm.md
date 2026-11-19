# A record field read joins a Float `if`/`match` in a `double` slot (done 2026-11-19)

Reported from Ur (a city builder on Strata and March): a profile of its
100,000-citizen replay found `walk_progress`, a five-line Float function, at
11% of the main thread, almost all of it `march_alloc_float`,
`march_rc_last_free_slow` and `march_free_any`.

## Cause

`predicted_unboxed_tail` (`lib/tir/llvm_case.ml`) predicts a `double` result
slot for a Float-valued case only when it recognises every arm's tail
(`specs/progress/2026-11-12-float-valued-case-join-slot.md`). It had no case
for `EField`, so an arm that is a bare field read, such as the early return
`event.progress` in

```march
if event.limit == event.progress || time <= event.started do event.progress else
  ...
end
```

made the whole case take the `ptr` slot. Every arm then boxed its value and
the merge unboxed and freed it. After LLVM merged the arms, every call to
`walk_progress` paid a malloc and a free.

## What changed

`predicted_unboxed_tail` answers the field's scalar register type for
`EField` of a variable whose record shape is statically known, which is the
case where `Llvm_emit_data.emit_field` loads the field at its own type. A
closure free-variable field (`$fvN`), a record of unknown shape, or a field
whose type is still a type variable yields no prediction, as before. A wrong
prediction would still be well-typed: every store goes through
`Llvm_ctx.coerce`.

## Effect

Ur's replay at 100,000 citizens, four alternated pairs, the same Ur commit
built with March `main` with and without the fix: 35.2 → 32.6 ms a frame
(28.1 → 30.4 FPS). In the Ur binary 11 of about 5,850 `march_alloc_float`
call sites go away, but `walk_progress` was the hottest.

## Test

`test_codegen.ml`'s float-join fixture (`float_join_fns`) gains `field`, a
join whose then-arm is a Float field of a record passed through a recursive
loop (`ftotal`), so inlining cannot fold the field away. Without the fix the
IR test counts 2 `march_alloc_float` calls; with it 0. The parity and
live-allocation gauge tests run the same fixture.
