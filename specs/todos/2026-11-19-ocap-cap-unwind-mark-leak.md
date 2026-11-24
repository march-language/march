# `march_cap_unwind` takes a new reference to the mark instead of adopting one (2026-11-19)

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
