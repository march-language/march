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

## Fixed 2026-10-07

`typed_array_alloc` now stamps `MARCH_TYPED_ARR_TAG` (-8, `runtime/march_runtime.h`),
and `march_run_resource_dtor`, which every RC free path already calls, releases
each of the `len` slots (`march_decrc` ignores a tagged immediate). Other code
that switches on a cell's tag:

- `march_message.c`'s cross-heap `copy_value` gained an arm: it copies the
  header, `len`/`cap` and slots, then copies each slot recursively. With tag 0
  it used to fall to the ADT arm, which reads `n_fields` from alloc_meta.
- `march_poly_eq`, `march_poly_compare` and `march_value_to_string` already
  treat an unknown negative tag like any opaque cell (identity / `#<tag:-8>`),
  as they did for tag 0. No change.
- The arena GC (`march_gc.c`) never sees a TypedArray (it is `march_alloc`'d,
  not arena-allocated), and the wasm runtime has no TypedArray. No change.

Pinned by `test/native/typed_array_elements_released_probe.march`: seven legs
(`from_list`, `set`, `create`, `map`, `filter`, `slice`, `to_list`) of fresh
String elements. Every leg read `flat: false` before the fix and reads
`flat: true` after it, with the values unchanged; the existing
`typed_array_builtin_borrow_leak_probe` golden is unchanged. A slot released
early would change a value read back after its source died. Landed 2026-10-11 (rebased onto main; the first attempt sat on
`fix/typed-array-free-elements`). The probe also runs clean under a local
`MARCH_SANITIZE=1` build (ASAN+UBSan) with every leg flat, and reads
`flat: false` on all seven legs against origin/main's runtime.
