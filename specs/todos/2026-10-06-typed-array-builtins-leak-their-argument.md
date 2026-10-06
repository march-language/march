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
