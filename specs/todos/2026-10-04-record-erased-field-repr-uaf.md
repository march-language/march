`[P2]` `test/native/record_erased_field_repr.march` has a heap-use-after-free under ASAN

Found 2026-10-04 in an ASAN sweep (Linux container, `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1`, `detect_leaks=0`) while fixing
`specs/todos/2026-10-02-known-call-generic-lambda-float-leak.md`. It reproduces with
main's unmodified compiler (main at 2026-10-04), so it predates that fix. The
fixture's normal golden test passes: the freed memory is not reused in time to
change any printed value, so only ASAN sees it.

```
ERROR: AddressSanitizer: heap-use-after-free
  #0 march_decrc_local
  #1 march_main
freed by thread T0 here:
  #0 free
  #1 march_decrc_freed
  #2 march_main
previously allocated by:
  #1 march_alloc
```

An object is freed by a `march_decrc_freed` in `march_main` (a match that
destructures a uniquely owned value and frees the cell) and then released again by
a later `march_decrc_local` in the same function. The fixture exercises dynamically
shaped Records whose field reads cross the erased boundary
(`specs/progress/2026-08-20-record-put-get-float-niche-segfault.md`), so the likely
place is a field read through `march_record_get` whose result is both
destructured-and-freed and released as a temporary. Start by dumping the
post-Perceus TIR of `main` and finding the binder that is decremented twice.
