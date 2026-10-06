# `record_get` of a Float field: the returned box is released twice (ASAN UAF, compiled)

**Logged 2026-10-05.** Found by an ASAN sweep of `test/native/*.march` (Linux arm64
container, `MARCH_SANITIZE=1`) while validating the colliding-type drop fix; the emitted
IR is identical (modulo fresh-name numbering) with and without that fix, so this
predates it.

`test/native/record_erased_field_repr.march` prints `Some(7)`, `Some(8)`, `Some(0.5)`,
then ASAN reports a heap-use-after-free in `march_main`:

- allocated: `march_record_get` -> `march_alloc_float` (the Float box for the erased
  `"y"` read of `record_put(record_from_list([]), "y", 0.5)`)
- freed: `march_main` -> `march_decrc_freed`
- read again: `march_main` -> `march_decrc_local`, a second release of the same cell

Without ASAN the program passes its golden (the freed cell is not reused before the
second decrement), so `native_record_erased_field_repr` stays green. The likely owner is
the ownership hand-off at the erased boundary fixed in
[../progress/2026-08-20-record-put-get-float-niche-segfault.md](../progress/2026-08-20-record-put-get-float-niche-segfault.md):
the Some cell and its Float payload are each released once by the caller, but one
path also releases the payload through the Option's drop.

Next: snapshot the post-Perceus TIR of the `rf` leg (`--dump-tir`) and count the
releases reaching the Float box.
