`[P1]` A closure freed captured strings before a borrowing builtin read them (compiled, ASAN)

Filed 2026-11-06, found by the HTTPS server work (`specs/progress/2026-11-05-https-server.md`).

## What

This closure, built in `HttpServer.tls` and called once from `HttpServer.configure_runtime`:

```march
let configure = fn pw ->
  match pw do
  (poll_secs, wait_flag) ->
    match src do                       -- src : TlsSource, captured
    TlsFiles(c, k) -> http_server_tls_configure(0, c, k, poll_secs, wait_flag)
    TlsPem(c, k) -> http_server_tls_configure(1, c, k, poll_secs, wait_flag)
    end
  end
```

compiled with `MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1` (Ubuntu 24.04 container, arm64) and run
with `c`/`k` from `process_env`, aborted at startup:

```
ERROR: AddressSanitizer: heap-use-after-free ... READ of size 8
    #0 str_dup                          march_https_tls.c
    #1 march_http_server_tls_configure
    #2 HttpServer.configure_runtime
freed by thread T6 here:
    #0 free
    #1 $lam0_HttpServer_tls$apply$0_HttpServer_tls
previously allocated by: march_string_lit <- march_process_env <- march_main
```

`http_server_tls_configure` borrows its two Strings (`Borrow.extern_borrow_table`:
`[false; true; true; false; false]`). The apply function released the captured strings and
then made the call, in tail position, so the builtin read freed memory. On macOS the
end-to-end suite passed anyway: the freed bytes were still intact.

A reduced program, a closure that captures a two-String ADT, matches it and passes the fields
to `string_byte_length`, did not reproduce. The suspects are the builtin returning a heap
`Result` in tail position, or the nested match on the closure's tuple argument.

## Workaround in place

`HttpServer.tls_configure_call(kind, a, b)` captures the strings themselves and binds the
builtin's result before returning it (`let r = ... ; r`). ASAN-clean in the same container.

## Done when

The original shape above is ASAN-clean (a `test/native/` probe under the sanitizer leg), and the
fix's Perceus or borrow change is covered by a `test/test_compiler.ml` case. The `compiler-rc`
and `march-debug` skills cover the tooling (`--rc-trace`, `scripts/triage.sh`).

## Fixed (2026-11-10)

**Root cause.** Not Perceus or borrow inference: `Drop.rewrite_apply_clo_drop`
(`lib/tir/drop.ml`). When an apply function's `dec_rc $clo` is the release that frees
the environment, that pass prefixes every tail with
`case $cfree of True -> __drop$T(capture)`. It already refused to put that release in
front of a tail that still uses a capture, but "uses" meant "names the capture
variable". A tail that names only the pattern variables of a `case` on the capture
(`case src of Pair($f1, $f2) -> let a = $f1 ... string_concat(a, b)`) did not count,
so the deep drop of `src` ran first and freed `a` and `b`. Those binders are borrowed
from the capture (Perceus adds no reference for them, and the builtin borrows them),
so nothing else kept them alive.

The earlier reduction with `string_byte_length` did not reproduce because it
used the result in an arithmetic tail (`+(...)`), which reads no capture field.
Any closure whose tail is a call reading a field of a captured value was affected:
`string_concat(a, b)`, a `string_byte_length(a)` tail, a nested match
(`Nest(p, s) -> match p do Pair(a, _) -> ...`).

**Fix.** `push` now carries an alias map: the pattern variables of a `case` on a
capture (or on an alias), and a `let` that copies or projects one, alias that capture.
`used` and `covered` look at the capture's name and all its aliases. A used capture
then follows the existing rules. A builtin tail is bound first and released after
(`let $cres = string_concat(a, b) in (release; $cres)`). A module-function tail
withholds the release unless Perceus incremented every occurrence. The second case is
the conservative leak that path already had.

**Tests.**
- `test/test_codegen.ml` group `closure_field_tail`: in post-Drop TIR, no `__drop$`
  call precedes the field-reading builtin on any path, and the release is still there.
  It was red before the fix.
- `test/native/closure_borrowed_tail_call_probe.march`: the original shape (tuple
  argument, then a match on the capture, builtin tail), a nested-field leg and a
  rebinding leg. Golden matches the interpreter. Added to the sanitizer gate's curated
  native list (`specs/lang/golden/sanitize.sh`). macOS prints the right values with or
  without the fix, so the ASAN leg is what sees a regression. ASAN was not run locally
  (no Docker on this host).

`HttpServer.tls_configure_call` keeps its workaround shape. Its comment now points here.
