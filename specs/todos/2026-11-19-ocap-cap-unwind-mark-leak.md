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
