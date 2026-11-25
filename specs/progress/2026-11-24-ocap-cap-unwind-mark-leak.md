# A caught panic leaked the authority of every frame it abandoned (fixed 2026-11-24)

Was `specs/todos/2026-11-19-ocap-cap-unwind-mark-leak.md`. The fix is the last section;
the sections before it are the todo as filed and the measurements that led there.

## As filed (2026-11-19): `march_cap_unwind` takes a new reference to the mark instead of adopting one

Found by the ocap phase 4 Task 10b review. At a panic-catch site,
`march_cap_unwind(mark)` (runtime/march_runtime.c) restores the authority slot to
the catch's mark with an incrc of the mark, while the reference the abandoned
frames held is dropped without being released. When the mark is a mortal cell
this leaks one reference per caught panic (the same behaviour as before Task
10b, so not a regression). It could adopt the abandoned reference instead.

What to do: adopt rather than incrc where the unwound chain owns a reference to
the mark, and pin it with an `--rc-trace` run of a caught panic inside nested
scoped functions (see the mortal-mark fixture todo,
`specs/progress/2026-11-24-ocap-mortal-mark-catch-fixture.md`).

## Measured on the mortal-mark fixture (2026-11-24)

`test/cap_conformance/panic_caught_mortal_mark.march` under `--rc-trace`: 15
authority cells are live at exit, in three groups.

- 3 cells, final count 2: `g_outside`'s frames. Only the unwind's extra
  reference keeps them. With the `march_incrc(mark)` removed (tried in a copy of
  the runtime) all three are freed, ASan is clean and the output is unchanged.
- 6 cells, final count 5 or 7: `g`'s frames. Removing the incrc lowers them to 3
  and 5; the rest are references held by closures made inside `g` that the
  panic abandoned (the lambda wrapper's `cap_save`). Not the unwind's.
- 6 cells, final count 1: `h`'s frame in the two-deep catches, kept by `k`'s
  abandoned saved value. Removing the incrc does not change them.

So adopting the mark fixes the first group only. Do it after the catch sites
each have a fixture (`specs/todos/2026-11-19-ocap-catch-sites-untested.md`): once
the count is exact, a site that unwinds without an abandoned reference frees the
live mark.

## Adopting the mark is unsafe as proposed (2026-11-24)

Tried: `march_cap_unwind` without its `march_incrc(mark)` (a copy of the
runtime, `MARCH_RUNTIME_DIR`).

- Every `test/cap_conformance` caught-panic fixture stays clean under ASan, and
  three of the 15 live cells above are freed.
- `test/test_cap_runtime_slot.ml`, "a caught panic keeps the authority it
  restores alive" (added with this note) aborts: `RC underflow` in a plain
  build, `heap-use-after-free` under ASan.

Why. "Adopt" assumes the saved value of the first frame entered after the mark
still holds its reference when the panic is raised. Nothing guarantees that. A
saved value that is never restored is dead after the push, and the compiler
drops it there. The test does it by hand (`let _old = cap_push(...)`, then
`panic`). A compiler-made frame keeps its saved value live today only because
`cap_restore($auth_saved)` follows the call of the body; any pass that learns
the body cannot return (it always panics) and removes the code after it would
make that saved value dead at the push too, and the adopt version would then
free an authority that is in force. The current code is exact in that case and
leaks one reference in the other, which is the safe direction.

So this is not a count to "fix" in `march_cap_unwind`. The leaked reference is
the abandoned frame's own local, the same kind of leak as every other local a
caught panic abandons (the closure, the panic message), which the runtime
accepts everywhere ("whatever the fragment allocated before it panicked is not
released").

Options, for the owner:

1. **Close as accepted.** One authority cell per frame instance that caught a
   panic, on top of what a caught panic already leaks. Keep the guard test.
2. **Make the runtime own the saved reference.** `cap_push`/`cap_enter` keep
   the previous authority on a per-thread stack and hand compiled code a token
   that carries no reference (the tagged-word trick `MARCH_CAP_SAME` already
   uses); `cap_restore` pops; the unwind pops down to the mark's depth and
   releases exactly what was abandoned, intermediate cells included. Exact in
   every case and independent of what the compiler keeps live, but it adds a
   store and a load to every frame entry and exit, and changes the March
   policy, the C twin and the JS runtime together.

Recommendation: 1 now; revisit 2 only with the general question of releasing
what a caught panic abandons.

## Fix: the runtime owns the saved authorities (2026-11-24, option 2, owner's choice)

`runtime/march_runtime.c`, `runtime/march_scheduler.{c,h}`, `stdlib/authority.march`.

- Each green thread (and each OS thread outside one) has a saved stack next to
  its authority slot (`march_auth_state`: `auth`, `saved`, `len`, `cap`).
- `march_cap_push` and `march_cap_enter` move the slot's reference to the
  previous authority onto that stack and return a token for the entry:
  `((index + 1) << 1) | 1`. A token is odd, so the compiler's reference-count
  operations on a `CapAuthRef` holding one do nothing. It carries no reference.
- `march_cap_restore(token)` pops back to that entry. Entries above it (frames
  left without a restore) are released. The word `1` still means "nothing to
  put back". An even word is an authority from `march_cap_save` and is
  installed as before.
- `march_cap_mark` returns the stack depth and the authority in force.
  `march_cap_unwind` pops to that depth, which puts the mark's authority back
  and releases what every abandoned frame had saved, intermediate cells
  included. If the slot still differs (stdlib-internal code that installed a
  saved authority by hand), the mark goes back with its own reference, as
  before.
- A dead thread's remaining entries are released at its reap. That also covers
  `march_respawn_child`, whose restore a panicking `init` skips.
- `Authority.enter_fn`, on re-entering the frame in force, returned
  `cap_save()`: a real reference, leaked when a panic skipped the restore. It
  now returns `cap_enter(cap_save())`, the "nothing to put back" word.

The interpreter and the JS runtime keep the previous authority as a value in a
garbage-collected heap; neither changes, and `enter_fn`'s new body means the
same there.

### Measured

- `test/cap_conformance/panic_caught_mortal_mark` under `--rc-trace`: 15
  authority cells live at exit before, 6 after. The 6 are `g`'s frames, each
  still referenced by a closure made inside `g` that the panic abandoned (the
  closure is the leak; the runtime cannot see it).
- `test/test_cap_runtime_slot.ml`, "a caught panic releases what the abandoned
  frames saved": 100 catches under a refcounted authority left 999 objects (one
  frame), 1899 (two frames) and 1899 (a frame entered twice) before; 100 each
  after, which is the panic message alone.
- "a caught panic keeps the authority it restores alive" (the case that made
  adopting unsafe) passes: with a token there is no reference to drop early.
- Every caught-panic fixture is clean under ASan with unchanged output.

### Cost

Compiled at `--opt 2`, this tree against `origin/main`'s runtime and stdlib, 31
interleaved runs on a loaded machine (`list_ops`, which has no authority code,
moved by up to 3% between rounds, so that is the noise):

| bench | minimum | median |
|---|---|---|
| `restrict_enter` (1,000,000 frame entries) | 34.4 -> 35.2 ms | 37.7 -> 39.4 ms |
| `restrict_enter_static` | 12.3 -> 12.8 ms | 14.2 -> 14.3 ms |
| `restrict_enter_computed` | 574.6 -> 568.6 ms | 613.1 -> 605.8 ms |
| `cap_capture_closures` | 89.1 -> 87.9 ms | 98.3 -> 100.6 ms |
| `cap_check_slow` | 90.5 -> 89.9 ms | 99.5 -> 100.0 ms |

By instructions retired (`/usr/bin/time -l`), a frame entry and leave costs about
18 more than before (`restrict_enter`: 356M -> 374M for 1,000,000 entries): the
push onto the saved stack and the pop. A captured call under the authority it was
made under costs the same (`cap_capture_closures`: 1222.8M -> 1223.2M).

Two things were needed to get there, both found with this comparison:
`march_sched_auth_slot` keeps its own body (calling `march_sched_auth_state`
from it put a second call on every capability check), and `march_cap_restore`'s
non-trivial path is out of line (`march_cap_restore_slow`), so the no-op path of
a captured call saves no registers.

### Not changed

What a caught panic abandons outside the authority slot (closures, the message,
other locals) is still not released. A closure made inside a frame holds a
reference to that frame's authority (`cap_save` at the top of the body), so it
keeps the cell alive when it is abandoned.
