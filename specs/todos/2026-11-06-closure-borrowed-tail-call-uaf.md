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
