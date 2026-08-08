# try_finally native builtin + fd-streaming Option contract (2 stacked compiled-only bugs)

**Date:** 2026-08-08
**Symptom:** `examples/read_file.march` failed native compilation at link time:
`Undefined symbols for architecture arm64: "_try_finally"`. After fixing that,
the same example *hung* (100% CPU) in the `File.with_lines` section — a second,
previously masked bug.

## Bug 1 — try_finally had no native implementation

`try_finally(action, cleanup)` was a typecheck + interpreter builtin only
(`lib/typecheck/typecheck.ml`, `lib/eval/eval.ml`). It had no
`lib/tir/llvm_builtins.ml` row, so compiled call sites fell into the
unknown-extern fallback in `llvm_emit.ml`, which emitted
`declare ptr @try_finally(...)` against a C symbol that never existed. Its
siblings `__try_call` / `__try_call_val` only link because their C functions
are literally named after the March builtin (identity mangle).

**Fix:**
- `lib/tir/llvm_builtins.ml`: row mapping `try_finally` → `march_try_finally`
  with `ret_ty = TVar "_"` (the `record_put` precedent — the action's result
  is returned at the polymorphic type `a` *directly*, so call sites must read
  a uniform ptr and conditionally untag; a concrete scalar ret would read
  42 back as `(42<<1)|1 = 85`). `PDeclare` in `core_items`.
- `runtime/march_runtime.c`: `march_try_finally` next to `__try_call_val`,
  same jmp-buf save/restore panic capture. Contract: run action; run cleanup
  even if action panicked (cleanup's own panic is swallowed, matching the
  interpreter); re-raise action's panic after restoring the outer handler.
  No decrc of either closure (capturing closures' apply fns self-drop $clo —
  see the `__try_call` header comment).
- `runtime/march_runtime_wasm.c`: non-catching version (wasm panic traps the
  instance; there is no longjmp channel and nothing to clean up after).

## Bug 2 — file_read_line / file_read_chunk returned Result cells at type Option(String)

Only reachable once bug 1 let fd-streaming programs link. `Option(String)` is
**niche**-encoded compiled (Some's payload is the value itself, None is raw
NULL), but `march_file_read_line` / `march_file_read_chunk` returned
`mk_ok(string)` / `mk_err("eof")` Result cells like the rest of the file
family. Under the niche read every return — including the EOF Err — looked
like `Some(<Result cell>)`: a read-to-EOF fold never terminated
(`File.with_lines` hang) and using the misread "line" crashed (SIGBUS on a
straight-line read). The interpreter always had its own correct Some/None
implementation, which is why stdlib tests (interpreted) never saw it.

**Fix:** both functions now return the `march_string` directly on success and
NULL on EOF/error (non-EOF read errors fold into None — the Option type has
no error channel, matching the interpreter's `End_of_file` handling).

## Tests

`test/test_codegen.ml` (`try_call_capture_ownership_codegen` group):
- `try_finally: value untag + cleanup order` — Int result (the 42-vs-85
  untag witness), heap result, action/cleanup ordering, compiled vs interpreted.
- `try_finally: cleanup runs when the action panics` — nonzero exit, cleanup
  marker present, original panic message propagated.
- `File.with_lines streaming: fd Option niche contract` — end-to-end
  with_lines + Seq.take/to_list, compiled vs interpreted, with a 30s timeout
  so a contract regression fails instead of hanging the suite.

## Left open

`march_file_open`'s Err payload is a bare String, but the March-level type is
`Result(Int, FileError)` (and the llvm_builtins row says `Result(Int, String)`)
— the compiled Err path misreads the payload as a FileError ADT. Not on the
happy path; filed as a follow-up.
