`[P2]` TypedArray builtins are still classified owned (unaudited) and leak their argument

Found 2026-10-06 while fixing the NativeArray equivalent
(`specs/progress/2026-10-06-nativearray-builtins-leak-their-argument.md`).
`typed_array_from_list`, `typed_array_length`, `typed_array_get`,
`typed_array_map`, `typed_array_filter`, `typed_array_fold` and the rest of the
`typed_array_*` family sit in `extern_owned_builtins` in `lib/tir/borrow.ml`
with the note "unaudited". In compiled code a loop that builds a 3-element mask
with `typed_array_from_list(Cons(true, Cons(false, Cons(true, Nil))))` and reads
its length grows `live_allocs` by 5 per iteration (the list's four cells plus
one more object).

Fix the same way: for each builtin, read its C implementation
(`runtime/march_runtime.c`, `march_typed_array_*`) and move it to
`extern_borrow_table` only if it neither frees nor stores the argument AND
nothing hands it an unowned reference. The second check matters here:
`typed_array_get` returned array elements without a reference, which only
stayed balanced while `==` consumed them (see the comment above
`extern_owned_builtins`). Add a live_allocs leak guard per builtin, as
`test/native/nativearray_builtin_borrow_leak_probe.march` does, and an ASAN run.

## Fixed 2026-10-07

Audited every `march_typed_array_*` in `runtime/march_runtime.c`. None of them
stores or frees its array, list or mask argument, but four copied element
pointers into a fresh array WITHOUT taking a reference: `from_list` (from
the list), `filter` (from the array), `set` (every slot but the replaced
one, by `memcpy`), and `create` (one default reference in every slot).
That had only been safe because nothing ever released the source. Borrowing
the source without fixing them would have let the caller's release of a list
free elements the new array still pointed to.

Changes:

- `runtime/march_runtime.c`: those four now take a reference per copied
  element (`march_incrc`, a no-op on a tagged immediate), as `slice`,
  `to_list`, `get` and `map` already did. `create` keeps its default value
  OWNED: the transferred reference fills slot 0, each other slot takes its
  own, and an empty array releases it.
- `lib/tir/borrow.ml`: `from_list`, `to_list`, `length`, `get`, `set`,
  `map`, `filter` and `fold` move to `extern_borrow_table`, borrowing the
  array, list or mask. `map`/`fold`'s closure, `fold`'s accumulator and
  `set`'s new element stay owned. `create` stays in `extern_owned_builtins`:
  for a Float default the call site boxes a fresh cell
  (`builtin_boxed_generic_params_tbl`) and releases nothing after a builtin
  call, so a borrowed parameter would strand that box.

Regression: `test/native/typed_array_builtin_borrow_leak_probe.march`. It
has nine flat legs with Int/Bool elements: from_list + length (this todo's
repro), get, to_list, set, create, map, filter, fold, slice. All print
`flat: false` on base and `flat: true` with the fix. It also has a String
leg that runs every builtin and reads the values back after the sources
are gone. Output matches the interpreter at `--opt 0` and `--opt 2`. Built
with `MARCH_MALLOC=libc` and run under Guard Malloc, the probe and the
existing typed-array and DataFrame natives run clean.

Not fixed here, filed as
[../todos/2026-10-07-typed-array-free-does-not-release-elements.md](../todos/2026-10-07-typed-array-free-does-not-release-elements.md):
a dead TypedArray is freed shallowly, so its heap elements still leak.
