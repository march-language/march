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
`specs/todos/2026-11-19-ocap-mortal-mark-catch-fixture.md`).
