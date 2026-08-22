# Task handles are released now, and task_await_unwrap stopped allocating an Ok cell it threw away (fixed 2026-08-22)

Closes `specs/todos/2026-08-21-task-object-never-freed.md` (this file is its
`git mv`). Probe: `test/native/task_lifetime_leak_probe.march` (in `@runtest`,
threshold `< 100`).

## What leaked — two objects per spawn+await, any result type

The filing measured exactly 2 objects per iteration and identified one of them
(the Task) while saying of the second only "the count says two, the task is
provably one of them; identify precisely when fixing". Traced with
`MARCH_TRACE_GC` on a 5-iteration run: the live set was `{24 B: 5, 48 B: 5}`.

### 1. The 48-byte Task — 1 per await

`march_task_spawn_thunk` returns RC=2 (the caller's handle plus a hold for the
trampoline); the trampoline drops only its own, so the Task ended life at RC=1
forever.

The filing's diagnosis was right and the fix is where it said: Perceus already
treats `task_await` / `task_await_unwrap` as CONSUMING — neither appears in
`borrow.ml`'s `extern_borrow_table`, whose default is "owned" — so it transfers
the caller's reference into the builtin and emits an `EIncRC` at every earlier
use. Confirmed in the emitted IR: a double-await gets an `march_incrc_local`
before the first one. The emitted builtin simply never released what it was
handed. Both sites in `lib/tir/llvm_emit.ml` now emit `march_decrc` on the task
pointer — the atomic form, not `_local`, because the trampoline's own drop runs
on a scheduler thread and races it.

Because Perceus dups for every use but the last, exactly one release happens
per await and double-await stays balanced. That is the whole soundness
argument, and it is why the release must be here rather than at "the first
await" or at the unbox site.

### 2. A 24-byte Ok cell nobody asked for — 1 more per `task_await_unwrap`

`task_await_unwrap`'s emit called `@march_task_await` — which allocates
`mk_ok(task[3])` — bound the result to a fresh SSA name, and then **never read
it**, calling `@march_task_await_value` instead. Both wait on the same done
flag; only the second is needed. The vestigial call is deleted.

This is why `task_await_unwrap` leaked 2/await while `task_await` leaked 1.

## Measured

Darwin arm64, `--compile --opt 2`, `live_allocs()` delta. Control = pristine
`origin/main` 8897bb1a, built by file-copy swap of `lib/tir/llvm_emit.ml`
(never `git stash` — shared stash stack).

| | unfixed | fixed |
|---|---:|---:|
| filed reduction: 10,000 spawn+await, Int, `task_await_unwrap` | 20,000 | **0** |
| probe `unwrap_leg`, 5,000 awaits | 10,000 | — |
| probe `result_leg`, 5,000 awaits (`match task_await(t)`) | 5,000 | — |
| probe total | **15,002** | **2** |

Stdout is byte-identical between the two builds.

## The interaction the filing predicted, resolved differently

The filing expected the Float task box to "follow for free" once tasks die,
via a tag-guarded release of `task[3]` in the task free path. That is **not**
what landed and the item it blocks —
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md` — is still open.

What actually happened is the reverse: fixing the erased-slot Float ownership
in `llvm_case` (`specs/progress/2026-08-22-erased-slot-ownership-leaks.md`)
made the `Ok(v)` destructure release the box — and exposed that
`march_task_await`'s `mk_ok` stores `task[3]`'s pointer into the fresh `Ok`
cell **without taking a reference for it**. With double-await legal, two `Ok`
cells aliased one box and the second `match task_await(t)` on a Float task read
freed memory (measured: second await printed `0`, then SIGTRAP). `task_await`'s
emit now takes a `+1` on a `"double"` payload so the `Ok` cell owns its own
reference. `task[3]`'s own reference is still never released — the Task's free
is shallow — which is exactly the residual the 08-12 item describes, unchanged
in size.

Tasks now dying does unblock that item: a tag-guarded release in the task free
path is now reachable. It still needs its own change, because `march_decrc` is
generic and the Task object carries no distinguishing tag.

## Not touched

`task_cancel_by_id` is also absent from `extern_borrow_table` (so also
consuming) and also never releases. Left alone: `Task.race` /
`Task.async_stream` route it through `List.each`'s closure, which is the
ECallPtr caller/callee convention mismatch
(`specs/todos/2026-08-21-ecallptr-owned-arg-borrow-callee-leak.md`), and adding
a release there without settling that convention risks an underflow rather than
closing a leak.

## Verification

* Probe RED 15,002 → GREEN 2; the filed reduction 20,000 → 0.
* Double-await witness (Int / Float / String via `task_await_unwrap`, Float and
  Int via `match task_await`) prints identical values on both builds — it is a
  leg of the probe, so it is pinned.
* `native_task_await_int`, `native_task_await_ptr`, `native_task_await_float`
  (which exercises `Task.await_many` and `Task.async_stream`, i.e. `task_await`
  called through a `List.map` closure), `native_task_burst_await`.
* Full `dune build --root . @runtest`, `scripts/run-tests.sh` (incl. the Slow
  vault concurrency test), sanitize sweep — see the landing commit message.
