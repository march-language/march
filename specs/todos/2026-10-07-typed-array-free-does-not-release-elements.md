`[P3]` A dead TypedArray never releases its elements (compiled)

Logged 2026-10-07, split from
[../progress/2026-10-06-typed-array-builtins-leak-their-argument.md](../progress/2026-10-06-typed-array-builtins-leak-their-argument.md).

A TypedArray is a plain `march_alloc` cell with tag 0 (`typed_array_alloc`),
so `march_decrc` frees it shallowly. Every element slot holds a reference
(since 2026-10-07 every producer takes its own: `from_list`, `set`, `create`,
`map`, `filter`, `slice`), but nothing ever releases them. An array of fresh
Strings leaks one String per element when the array dies: the String legs of
`test/native/typed_array_builtin_borrow_leak_probe.march` would grow
`live_allocs` by two Strings per iteration. Int/Bool elements are immediates
and do not leak, which is why that probe's flat legs use them.

Shape of a fix: give TypedArray its own reserved tag (like
`MARCH_NATIVE_ARR_TAG`, -6) and release every slot on the free paths that
already special-case tags (`march_run_resource_dtor`'s callers in
`march_decrc` / `march_decrc_local` / `march_decrc_freed`). Every place
that switches on a cell's tag must then know the new one: the cross-heap
message copier (`march_message.c`), `march_poly_eq`, value-to-string, the
wasm runtime and the reserved-tag lists. That is why it is not part of the
argument-leak fix. Verify with the probe's String legs made flat, and a
libc-malloc + Guard Malloc run, since the old shallow free hid any slot that
lacks its own reference.
