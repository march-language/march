# Current State (as of 2026-07-31, the compiled HTTP server serves requests again)


**Counts:** `run_compiler` 619, `run_codegen` 521, `run_eval` 256,
`run_stdlib` 826 with only the pre-existing environmental `MARCH_SANITIZE`
failure (2222 total), `dune build @runtest` clean.

**Two stacked bugs, and the compiled HTTP server served nothing.** A compiled
`HttpServer` panicked `non-exhaustive pattern match` on request 1; fix that and
it segfaulted (exit 139, silently) on request 2. Both server paths were
affected — the default thread-pool one and the opt-in event loop. Both were
compiled-only; the interpreter served the same program correctly throughout,
which is exactly why the `http_server` tests (all interpreted,
`adversarial-regressions 48`/`49`) never saw it. A third defect (bug 2 below)
was found and fixed in passing but did **not** contribute to the outage — it
was initially reported as having caused one, and that report was wrong; see
the correction under bug 2.

*Bug 1 — constructor tag.* `stdlib/websocket.march` carried structural copies
of `Conn`, `Header` and `Upgrade` under a comment explaining they "mirror types
from Http/HttpServer (no imports in March)". March has one global type
namespace, so the copies were always redundant. They turned fatal when
`lib/tir/collision_set.ml` began giving same-short-name types in different
modules globally unique constructor tags: `HttpServer.Conn`'s ctor moved to tag
33554459 while `march_conn_from_parsed` in the C runtime kept writing tag 0.
The switch in `HttpServer.halted` had exactly one arm, for 33554459, so a
runtime-built conn fell through to the default and panicked. The duplicate
declarations are gone. The diagnostic that cracked it: `--emit-llvm` showed
`switch i32 %tag27, label %case_default12 [ i32 33554459, label %case_br13 ]`
against a value the runtime had zeroed.

*Bug 2 — boxed vs. raw `Bool`, and a misdiagnosis worth recording.*
`make_bool` in `runtime/march_http.c` allocated a 16-byte object and set a tag,
per a comment claiming "March Bools are heap objects with just a header". A
`Bool` field of a *boxed* ADT is a raw i64 0/1 (the `(v<<1)|1` tagging in
`lib/tir/repr.ml` governs niche *payloads*, not ordinary fields).
`march_ffi.c`'s `march_make_bool` had the encoding right all along; only this
local copy was wrong.

**This was initially reported as the cause of an empty-200 outage. It was
not.** `halted` is tested by its LOW BIT — the emitted IR for
`HttpServer.run_pipeline` loads the field as i64 and does `trunc i64 %x to i1`
— and `march_alloc` is calloc-backed, so the pointer is always even and reads
as `false`. The pipeline ran. Confirmed by restoring the heap version on top
of the other two fixes: 20/20 requests correct, full 26-byte body.

The empty 200 was **self-inflicted during debugging**: an intermediate fix
encoded the field as `(v<<1)|1`, which makes `false` = 1 — low bit set, so
every conn read as already-halted and `run_pipeline` short-circuited. The
symptom appeared while bisecting and was attributed to the code being
replaced rather than to the replacement. The lesson is narrow and repeatable:
when a fix for bug A reveals symptom B, test B against the *original*
unmodified code before attributing it — a pre-fix control, not the code you
have in hand.

The fix is kept regardless. Correctness should not rest on a pointer-parity
coincidence that an allocator change would silently break; any consumer
treating the field as a real `Bool` (equality, printing, passing to March
code) sees a pointer; and it malloc'd 16 bytes per request to carry one bit.

*Bug 3 — closure refcount at the C boundary.* The compiled apply-fn opens with
`march_decrc_local($clo)`: **calling a closure consumes a reference to it.**
All three runtime call sites — `march_process_one_request`, the
`connection_thread` batch loop, and `handle_read` in the event loop — passed
the server's one long-lived pipeline closure without bumping it, under a
comment asserting that holding it for the connection lifetime meant "no
per-request RC bump needed". Two calls took the refcount to zero; the closure
and its captured plug list were freed underneath the server. Each site now does
`march_incrc_local(pipeline)` first. This is the same "the C runtime is a third
owner of closures" hazard already documented for `task_spawn` and the
`__try_call` family, at three sites that audit missed.

**No automated coverage would have caught any of this.**
`test/test_http_native.sh` is the only end-to-end test of the compiled server
and is referenced by no dune rule and no CI workflow. It also compiles without
`--opt`, makes one request per server, and asserts on status codes — so even if
it were wired up it would have passed against bug 3, which needs a *second*
request to show up, and against a silently-skipped pipeline, which returns a
well-formed status with an empty body.
