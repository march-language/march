# A Float task's result box is released when the Task dies

**Landed 2026-09-13.** Closes
`specs/todos/2026-08-12-float-boxing-task-trampoline-leak.md`, which is kept
below the rule. This is §6 of `specs/2026-09-11-codegen-leaks-design.md`,
built as designed.

## The defect

For a Float-returning task, the trampoline stores `task[3] = (box << 1) | 1`,
where `box` is the `march_alloc_float` cell the apply fn returned.
`task_await_unwrap` reads the double out of it without consuming it, because a
task may legally be awaited twice. The Task therefore owns that reference.
But a Task carried tag 0 (from `march_alloc`) and its free is generic and
shallow, so the box outlived it: **one box per awaited Float task**.

Measured by the probe below: 5,000 per leg, 10,004 across the two Float legs.

## What landed

- **`MARCH_TASK_TAG` (−7)** in `runtime/march_runtime.h`, set by both
  `march_task_spawn_thunk` and `march_task_spawn_with_cancel_thunk`.
- **`march_run_resource_dtor`**, the tag hook every RC free path already calls
  (resource cells used it alone), gains a Task arm. When `task[3]` is a tagged
  result whose untagged value is a heap object with `MARCH_FLOAT_TAG`, it is
  released. Everything else is skipped:
  - an unfinished task (`0`);
  - the cancel path's untagged `Err` cell;
  - a tagged scalar (it untags to an odd value);
  - a heap result of any other tag, which the await routes hand to the caller
    and account for.

## Tests

`test/native/task_lifetime_leak_probe.march` gains two Float legs inside its
existing `< 100` live-object bound: 5,000 `task_await_unwrap` and 5,000
`task_await` Ok-route awaits. The existing double-await witness, which
includes a Float task awaited twice both ways, still prints `…/500/…/650`.

| build | `live_allocs` delta |
|---|---|
| with the release | 4 (3 of 3 runs) |
| release removed (control) | 10,004 |

## Found alongside, filed

A fire-and-forget task, spawned and never awaited, retains 3,500–4,500
objects over 5,000 spawns. It does so for an `Int` result too, and the figure
varies per run and does not settle with thousands of `task_yield`s. It is not
the Float box: `specs/todos/2026-09-13-fire-and-forget-tasks-retain-objects.md`.

---

# Float-boxing erasure boundary: the `task_await_unwrap` site is still open

Filed 2026-08-12. **Narrowed 2026-08-20**: the apply-wrapper/uniform-ABI half
moved to its own item and is now **FIXED** — see
`specs/progress/2026-08-21-float-box-uniform-abi-call-site-release.md`
(call-site releases; the two failed approaches this file used to warn about
are post-mortemed there). **Re-measured 2026-08-21**: the blocker picture
below replaces the earlier "both sites unreachable" claim, which was too
coarse — the two sites differ. **Updated again 2026-08-21**: site 2 turned
out not to exist (its unbox was the Float-task crash, now fixed), so what
remains here is site 1 alone.

Background on the shared root (the Stage 2 float-boxing design never gave
`march_alloc_float`/`march_unbox_float` an ownership story):
`specs/progress/2026-08-12-float-boxing-case-merge-leak-fix.md`.

## Remaining sites, with 2026-08-21 measurements

1. **`task_await_unwrap` Float unbox** — `lib/tir/llvm_emit.ml`, the
   `inner_ty = "double"` arm of the `task_await_unwrap` builtin
   (`march_unbox_float` on the pointer recovered from `task[3]`).
   **REACHABLE and leaking** — the earlier "cannot be reached" claim was
   wrong for this site: `task_spawn(fn _ -> 2.5)` + `task_await_unwrap`
   compiles and runs correctly (compiled == interpreted == expected).
   Measured, 100k awaits of a Float-returning task, `--compile --opt 2`:
   `live_allocs` delta = **300,001** vs an Int-control **200,000** — i.e.
   the type-independent 2/iter task leak (see below) PLUS exactly one
   Float box per await; the Float excess is linear (50k → +50,001).
2. **`task_await` Result-path Float unbox — THIS SITE NO LONGER EXISTS.**
   Superseded 2026-08-21 by the Float-returning-task fix
   (`specs/progress/2026-08-21-float-returning-task-compiled.md`). The
   entry above was written while `match task_await(t)` on a Float task
   still SIGSEGV'd, and reasonably assumed a leak hid behind the crash.
   It did not: that `march_unbox_float` **was** the crash. The trampoline
   stores `task[3] = (apply_ret << 1) | 1`, tagging box pointers too, so
   the emit site owes exactly one `ashr 1` to recover the uniform value —
   and the `double` arm did that and then *kept going*, unboxing and
   storing raw double bits back into the `Ok` payload, so the `Ok(v)`
   destructure unboxed a second time and dereferenced the IEEE-754
   pattern. Deleting the unbox+store removed both the crash and the site.
   There is nothing left to leak here; all three `llvm_ty` outputs now
   share one path.

## Why site 1 is NOT the "provably sole owner" shape — do not decrc it

The 08-12 filing hoped both sites were "unbox of a box only we can see".
Measured otherwise: **double-await is legal and works today** — two
`task_await_unwrap` calls on the SAME task both return the correct value
(compiled, verified). The box smuggled through `task[3]` is therefore
co-owned by the Task object for as long as the task is alive; an unbox-site
release would be a use-after-free on the second await.

The sound design: release `task[3]`'s heap payload (tag-guarded, like #313's
`fold_release_prev_acc`) **when the Task object is freed**. Which it never
is: tasks leak 2 objects per spawn+await for ANY result type — the bigger,
newly-filed `specs/todos/2026-08-21-task-object-never-freed.md`. **Fix that
first**; the Float box then has a natural owner and this item reduces to a
few lines in the task free path.

## Order of work

1. ~~`2026-08-21-task-object-never-freed.md` (task lifetime).~~ **DONE
   2026-08-22** — `specs/progress/2026-08-22-task-handle-and-ok-wrapper-leak.md`.
   Tasks now die: `task_await` / `task_await_unwrap` release the handle
   Perceus already transferred to them, and the type-independent 2/iter is 0.
   This item is unblocked and unchanged in size.
2. Site 1: tag-guarded `task[3]` release in the task free path; probe =
   the await loop above, asserting the Float excess over the Int control
   goes to ~0 (the absolute 2/iter is already pinned by
   `test/native/task_lifetime_leak_probe.march`).
3. `2026-08-20-task-async-float-thunk-compiled-build-break.md` (the
   `task_await` Result-path crash), then site 2 the same way.

## What "the task free path" now has to look like (2026-08-22)

The step-2 design needs one thing the filing did not anticipate: **there is no
task-aware free path to hook.** `march_decrc`'s free is generic and shallow,
and a Task carries tag 0 (`march_alloc` zeroes it), indistinguishable from an
ordinary ADT cell. So either the Task gets its own tag constant, or the two
emit sites call a dedicated `march_task_release(void *)` that does the
`atomic_fetch_sub` itself and, on the `prev == 1` (freeing) branch, releases a
`MARCH_FLOAT_TAG` payload in `task[3]` — the same tag guard as #313's
`fold_release_prev_acc`. The dedicated-helper form is narrower but misses the
fire-and-forget path, where the trampoline's own `march_decrc(task)` is the
last one.

Also note what changed around this item on 2026-08-22: `task_await` now takes a
`+1` on a `"double"` payload when it hands it to the fresh `Ok` cell, because
`mk_ok` stored the pointer without a reference and the `Ok(v)` destructure
started releasing erased-slot Float boxes. That `+1` is balanced by the
destructure's release; the reference it does NOT account for is still
`task[3]`'s own, which is precisely this item. Whoever implements the free-path
release must check the `Ok` route as well as `task_await_unwrap`'s unbox route
— `test/native/task_lifetime_leak_probe.march`'s double-await leg covers both.

> **Design spec (2026-09-11):** `specs/2026-09-11-codegen-leaks-design.md` — root cause re-verified against the tree, chosen fix, test plan with a RED control, effort and risk.
