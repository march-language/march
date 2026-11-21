`[P2]` Compiled, `task_is_cancelled(tok)` answered `true` BEFORE a later `task_cancel(tok)` (DONE)

Found 2026-11-11 while writing golden `g49` (the user-type-vs-built-in identity fix); unrelated
to it, the program declares no type.

```march
mod Main do
  needs IO.Console
  fn main(c : Cap(IO.Console)) do
    let b = task_cancel_token_new()
    print_line(to_string(task_is_cancelled(b)))
    task_cancel(b)
    print_line(to_string(task_is_cancelled(b)))
  end
end
```

- Interpreted: `false`, `true`.
- `--compile`: `true`, `true`.

## Root cause

Not a reordering or CSE: the emitted IR kept both queries and the cancel in program order. The
cancel token was a bespoke `malloc`'d `{ _Atomic int cancelled; _Atomic int refcount; }`
(`runtime/march_scheduler.h`, built by `march_cancel_token_new` in `runtime/march_scheduler.c`),
but a `CancelToken` is a March value (`TCon "CancelToken"`), so `Kind.needs_rc_of` says true and
Perceus inserts `inc_rc`/`dec_rc` on it like on any heap value. Those operate on word 0 of a
`march_hdr`, which for this struct was the `cancelled` flag. With `b` used twice, Perceus
emitted `__march_rc_incrc_local(b)` before the first `task_is_cancelled(b)`: that `atomicrmw add`
of 1 set `cancelled`. Without the later `task_cancel(b)` there was a single use and no `inc_rc`,
which is why the program printed `false` then.

The same corruption hit `task_spawn_with_cancel`: a fresh token passed to it and used again read
as cancelled, the spawned task skipped its body, and `task_await` never returned.

`send_after`'s `TimerRef` had hit the same hazard and was built as a real `march_alloc` cell for
exactly this reason (see the comment on `MARCH_TIMER_TOKEN_TAG` in `runtime/march_runtime.h`); the
cancel token had been left behind.

## Fix

- The token is now an ordinary `march_alloc`'d, RC'd cell, `[rc][tag][pad][cancelled@16]`, tag
  `MARCH_CANCEL_TOKEN_TAG` (-12) in `runtime/march_runtime.h`. `march_cancel_token_new` moved to
  `runtime/march_runtime.c` (it needs `march_alloc`; the standalone scheduler tests link only
  `march_scheduler.c`). `march_cancel_token_ref`/`_unref` are `march_incrc`/`march_decrc`, with a
  weak no-op `march_decrc` in `march_scheduler.c` beside the existing weak `march_incrc`.
- `lib/tir/borrow.ml` `extern_borrow_table`: `task_cancel` and `task_is_cancelled` borrow the
  token, and `task_spawn_with_cancel` borrows it (`[false; true]`; the closure stays owned).
  These are emitter arms, not `in_is_builtin` rows, so `test_builtin_borrow_classification`
  never asked about them and they defaulted to owned: each call leaked one reference.
- `cancel_trampoline` (`runtime/march_scheduler.c`) released the spawned task's token reference
  only after `user_fn` returned, but the compiled `user_fn` (`march_thunk_trampoline`) ends in
  `march_sched_exit()` and never returns. The trampoline is the token's only reader, so it now
  releases the reference right after its start check. Verified with `--rc-trace`: no token is
  live at exit.

Regression test: `cancel_token_codegen` in `test/test_codegen.ml` runs a program using one
token several times, cancelling it, and spawning with a second token, interpreted and compiled,
and requires identical expected output (red before the fix: `true` x5 and the binary hung in
`task_await` until the test's alarm).

Not fixed here (different cause): a task spawned with an already-cancelled token never
completes its Task, so a compiled `task_await` on it hangs; see
`specs/todos/2026-11-19-compiled-precancelled-spawn-await-hangs.md`.
