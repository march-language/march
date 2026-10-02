# Two per-request leaks in compiled HTTP servers (0.5 KiB + ~1 KiB per request)

Fixed 2026-10-02. Found by forgepm's pool acceptance run (sub-project A,
`specs/2026-10-01-forgepm-pooled-db-design.md`): the pooled Repo made forgepm
~13x cheaper per request and its RSS then grew ~400 MB/min on `/health`.
Repro and numbers: `specs/progress/2026-10-02-http-request-leak-512b.md`.
Regression test: `test/test_http_native.ml` Phase E (20,000 pipelined
keep-alive requests, RSS growth < 2 MiB, both server modes; was 23 MB).

## Leak 1 — the runtime never released the handler's result Conn (~0.5 KiB/req)

Both servers (`runtime/march_http.c` thread pool, `runtime/march_http_evloop.c`)
read status/headers/body out of the Conn the pipeline returns, write the
response, and dropped the pointer on the floor. The handler consumed its input
(`conn:own`) and handed back a fresh RC=1 record, so one 120-byte Conn plus its
strings and header cells leaked per request (GC trace: exactly 200 × 120 B,
1001 × 16 B, 1602 × 32 B over 200 requests).

The runtime cannot free it itself: `march_decrc` is shallow and `assigns` /
`upgrade` hold arbitrary March values. Fix: `HttpServer.listen` passes a fifth
argument, `release_conn : Conn -> Unit` (`stdlib/http_server.march`), to
`http_server_listen`; its compiled body is the synthesized deep drop
(`__drop$Conn`). The runtime (`march_http_release_conn`,
`runtime/march_http_internal.h`) applies it to every result once its bytes are
out of the iovecs: after a completed `writev`, after a deferred write drains
(`conn_state_t.pending_release`, `handle_write`), or on `close_conn` /
`detach_conn`; the WebSocket paths `march_incrc` the handler closure the
`upgrade` field still owns before calling it. `http_server_spawn_n` passes
`NULL` (keeps the old behaviour). Builtin arity change touched
`typecheck_builtins`, `eval_builtins` (the interpreter ignores it),
`llvm_builtins`' declare, and `test_codegen`'s golden preamble.

A second cut was needed in the compiler: `release_conn`'s parameter is unused,
so borrow inference marks it borrowed and the drop lands in the emitted
`$clo_wrap` trampoline, which released with a bare `march_decrc` —
`Llvm_calls.clo_wrap_define` now takes per-parameter `deep_drops` and calls
`__drop$T` when the module defines one (all four call sites). This affected
any aggregate handed through a closure value to a borrowing function.

## Leak 2 — dead join-point closures were dropped shallowly (~1 KiB/req)

`lower_match` hoists a match's fall-through into a join-point closure capturing
the live variables; nested patterns build a CHAIN (`$jp_clo41839` captures
`$jp_clo41837` captures `$jp_clo41835` captures `conn`). In a success arm the
innermost one is dead and Perceus emits `dec_rc $jp_clo`. `lib/tir/drop.ml`
skipped it: a closure's capture is typed `() -> '_` (a `TFn` with a TVar
return), filtered out by `has_tvar`, so the struct "owned no heap child".
Escape then promoted the non-escaping cell to the stack and deleted the dec as
dead, DCE removed the pure stack alloc, and the captured chain down to the
request's `conn` was never released. Any `match` with a non-trivial default
and a nested pattern paid this per evaluation.

Fix in `drop.ml`: a let-bound closure variable is mapped to its struct
(`clo_vars`, per function, from `EAlloc`/`EStackAlloc`/`EReuse` of a
`TDClosure`), so a bare `dec_rc` on it is routed through a synthesized
`__drop$<struct>` over the capture slots the environment OWNS. Ownership is
decided per slot at the allocation sites (`closure_sites`, a module pre-scan;
all let-bound sites must agree, any other allocation position disqualifies
the struct): a slot is owned when Perceus inc'd the capture in the RHS prefix
(a dup), or when the capture is a closure allocated earlier in the same
function and dead after the let (a move — the join-point chain). Everything
else is a borrowing capture of a non-escaping closure (`List.sort_by`'s
`sort_loop` captures its `groups` parameter that way) and is left alone:
claiming it double-freed (RC underflow), which is also why
`owning_apply_fns`' apply-side gate exists. Each site also records which
struct it stores in each slot (`clo_field_structs`), so an owned captured
closure is dropped deeply in turn; a struct that (recursively) owns no heap
data gets no drop function, so every match's capture-free panic-default chain
stays a shallow dec that Escape still stack-promotes and DCE deletes
(`unboxed_aggregates` keeps its zero `march_alloc`). Two regressions found
and fixed on the way: a module-wide `clo_vars` matched an apply function's
same-named capture local (`let cmp = $clo.$fv1`) or self alias (`let go =
$clo`) to another function's struct, and the first ownership rule claimed
borrowed captures.

## Measurements (thread pool, 10 s, `wrk`/pipelined client)

| program | before | after |
|---|---|---|
| text-only handler (`test/native/http_text_leak_repro.march`) | 0.50 KiB/req | 0.006 |
| `match method(conn) do :get -> … \| _ -> … end` | 0.92 | 0.083 |
| `match path_info(conn) do Cons("ping", Nil) -> … \| _ -> … end` | 0.98 | 0.086 |
| e2e router (tuple scrutinee, 3 rows) | 1.00 | 0.085 |

GC trace over 200 requests: 2,803 live objects before, 3 after (the e2e
router too). forgepm's remaining per-request growth is depot's `Db.exec`
path (~7.8 KiB per query) and its full router path; see
`project_forgepm_health_per_request_leak` (memory) / sub-project C.

## Still shallow, documented

A closure dropped unapplied whose captured closure's struct is NOT known at
every allocation site (an escaping lambda stored in data and dropped later)
releases the captured closure's cell but not what it captured. drop.ml's
header documents the gap; it is the remaining member of this class.
