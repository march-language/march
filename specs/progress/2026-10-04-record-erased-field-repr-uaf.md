`[P2]` `test/native/record_erased_field_repr.march` has a heap-use-after-free under ASAN

Found 2026-10-04 in an ASAN sweep (Linux container, `MARCH_SANITIZE=1
MARCH_DEBUG_RUNTIME=1`, `detect_leaks=0`) while fixing
the Known_call generic-lambda Float leak
(`specs/progress/2026-10-02-known-call-generic-lambda-float-leak.md`). It reproduced
with main's unmodified compiler at 2026-10-04, and again on 2026-10-06 on main
`11833975a` (after #811 and the record-ownership leak fixes), so neither caused it. The
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

## Closed 2026-10-07: fixed by the erased-Option drop fix, now under the ASAN gate

This is the same bug as `2026-10-05-record-get-float-box-double-release`,
filed a day later from a different sweep and closed by `299deadb7`
([2026-10-06-record-get-erased-option-drop.md](2026-10-06-record-get-erased-option-drop.md)).
`record_get`'s erased read is niche-encoded, but the `Option('a)` drop
assumed a boxed `Some` cell and released the payload a second time. That
matches the trace above: freed by `march_decrc_freed`, released again by
`march_decrc_local`, both in `march_main`. `299deadb7` left this file open.

Evidence on macOS (ASAN binaries hang on hosts running endpoint security
software, see `.github/workflows/README.md`). The substitute is libc malloc
(`MARCH_MALLOC=libc`, so objects bypass mimalloc) plus Guard Malloc
(`DYLD_INSERT_LIBRARIES=/usr/lib/libgmalloc.dylib`), which faults on any
access to freed memory:

- A binary of this fixture compiled on 2026-10-06 (main at that time plus an
  unrelated drop change) faulted deterministically (SIGSEGV, 3 runs of 3)
  right after printing `Some(0.5)`, the first Float erased read.
- On main `c31ef539a` the fixture runs clean at `--opt 0` and `--opt 2`,
  with a cold and a warm `$HOME`, 30 runs of 30, and its output matches the
  golden.
- Unexplained: fresh builds of `7b1db5973` and `299deadb7^` do NOT fault
  either, so the crash cannot be pinned to `299deadb7` locally. The faulting
  binary's code differs from today's builds of the same source (register
  allocation and spills around `__drop$List_T2_String_V`), so the build
  that produced it emitted different code. A likely cause is the cache-state
  dependence in `2026-10-05-post-tir-hash-depends-on-home-cache`, but that
  is not shown.

So the fixture, and `erased_option_read` (the regression `299deadb7` added),
are now in the curated native list of the ASAN gate
(`specs/lang/golden/sanitize.sh`, CI `sanitize-gate`). Neither was in it,
which is how this use-after-free kept its golden green. CI's Linux ASAN run
is the check that this file is truly closed; if it fails, reopen this.
