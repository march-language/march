`[P3]` **Each shell input keeps its fragment and the fragment's literals on the node.**

Filed 2026-10-08, left over from
[2026-10-08-shell-slot-and-drop-leaks](../progress/2026-10-08-shell-slot-and-drop-leaks.md),
which fixed everything about shell inputs that grew with the data.

What stays, per input, for the life of the node:

- **The fragment's mapping.** `runtime/march_shell.c` never `dlclose`s a
  fragment: anything it allocated may point at its code or data, such as a
  closure's apply function, a static closure, or a literal's cell. That is
  ~70 KB of mapping per input. The file is unlinked once loaded.
- **One immortal string per string-literal site the input evaluates.**
  `march_string_lit_static` fills a per-site cell once, with an immortal heap
  string, and every input is a new `.so` with new sites. Measured with
  `live_allocs()`: `List.length(["a", "b", "c"])` leaves 3, and rendering a
  list leaves the renderer's 3 (`[`, `, `, `]`). LeakSanitizer does not
  report them, because they are reachable from the loaded fragment.
- **A panic's live values.** `panic` long-jumps out of the fragment, skipping
  every release, as it does for a panicking task in a native program. An
  input that panics in the middle of `List.map(List.range(1, 1000), …)`
  leaves 1 002 objects.

Ideas, none tried:
- For literals, emit a fragment's string literals as static immortal objects
  in its data section, as `Llvm_ctx.intern_static_closure` does for
  closures. Then nothing is allocated on the heap, and they go with the
  mapping.
- Unloading would need to know that nothing references the fragment: a
  per-fragment allocation arena, or a reference count on the fragment held
  by everything it allocates.
- Panics need unwinding or an arena; the same question exists for tasks.
