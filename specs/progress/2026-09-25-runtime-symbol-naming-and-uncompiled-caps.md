# Runtime symbol naming, and the cap-table builtins the audit never saw

Filed 2026-08-03 as `specs/todos/2026-08-03-runtime-symbol-naming-and-uncompiled-cap-builtins.md`
while building the cap-to-symbol table for `forge cap inspect`
(`lib/caps/cap_symbols.ml`, drift test `test/test_cap_symbols.ml`). Closed 2026-09-25.

The todo had two items. Both turned out to be different from how they were filed.

## 1. `dns_resolve`'s C function was unprefixed

**Done.** The C function is now `march_dns_resolve` (`runtime/march_runtime.c`,
declared in `runtime/march_runtime.h`; no WASM runtime defines it). It has a row in
`lib/tir/llvm_builtins.ml` with `c_name`, a `declare_sig` and a `native_net_io_items`
preamble entry, so it no longer reaches codegen through `mangle_extern`'s identity
fallthrough. `Cap_symbols.table` keys `march_dns_resolve`, and the special-lowerings
entry in `test/test_cap_symbols.ml` is gone.

**What the rename fixes.** The binary audit (`forge/lib/cap_binary.ml`) matches RAW
symbol names from the whole symbol table. With the key spelled `dns_resolve`, any
symbol of that spelling was read as an IO.Network witness, for example from a
foreign C object linked in. Every key is now `march_`-prefixed.
`test_table_keys_are_prefixed` asserts that for the whole table, and asserts that
`dns_resolve` / `_dns_resolve` map to nothing while `march_dns_resolve` maps to
IO.Network. The positive control keeps the absence assertions from passing
vacuously.

**What the rename does NOT fix: the entry-module user function.** The todo said a
user `fn dns_resolve` in the entry module would record a spurious IO.Network marker
through the same fallthrough. Measured on origin/main at `3a9b49a9b`, that premise was
half wrong:

- A small user `fn dns_resolve(x : Int) : Int` gets inlined and never emitted, so it
  records no symbol and no marker. The real false positive was one layer earlier.
  `Cap_attrib.walk` looks calls up by bare March name in `builtin_cap_table`. The
  entry module's functions are unprefixed in TIR, so the user's call to their own
  function was charged IO.Network. The compiled build then FAILED the ceiling
  (`module 'Shfr' uses 'IO.Network' but does not declare 'needs IO.Network'`), and the
  same happened with IO.FileRead for a user `fn file_read`. The interpreted run was
  fine. The typecheck-level scans got this fix on 2026-08-09 (plan Tier 0), but this
  TIR walk had not. **Fixed:** `walk` takes `~is_defined` (the module's own
  `tm_fns`). A call to a defined name, or a reference to one, is a call to that
  function, and its body is walked on its own, so a real capability inside it still
  reaches callers through the call graph.
- A user function that SURVIVES to emission (big enough not to be inlined, or used as
  a value) does not compile at all, before or after this change. Before, the link
  failed with `duplicate symbol '_dns_resolve'` against the runtime. After, clang
  rejects `invalid redefinition of function 'march_dns_resolve'`, because
  `mangle_extern` maps a table-named user fn's definition onto the builtin's C
  symbol. The same is true today for `fn file_read`, for every one of the ~330 names
  with a `c_name` row. That is a separate, general bug, filed as
  `specs/todos/2026-09-25-user-fn-named-like-builtin-emitted-as-its-c-symbol.md`.

Regression tests in `test/test_cap_markers.ml` (emit-llvm, Slow):
`user fn named dns_resolve marks nothing` shows RED on origin/main's `cap_attrib.ml`
(`emit-llvm failed (rc=1)`, the ceiling) and GREEN after. Its positive control,
`real dns_resolve call still marks IO.Network`, asserts the marker, the owner row,
`call ptr @march_dns_resolve(`, and no `@dns_resolve(`.

**Borrow classification.** Before it had a row, `dns_resolve` was on no borrow list,
so it defaulted to OWNED. The C function never frees its argument, so every call
leaked the host String. It is now in `extern_borrow_table` (the C code copies the
bytes into a stack buffer and never stores the String). Measured compiled with
`live_allocs()` around 1000 calls: growth 1000 without the rows, 0 with them. The
parity fixture asserts zero growth over 200 calls.

## 2. "Three cap-table builtins have no compiled lowering"

Each was compiled with `--compile` (scratch programs, output redirected), then
compared with the interpreter:

| builtin | what actually happened compiled | resolution |
|---|---|---|
| `task_spawn_link` | Rejected at lowering since 2026-09-24 with a positioned diagnostic: "`task_spawn_link` links a task to an actor so the task fails if the actor dies, which only the interpreter implements; …" | **Kept rejected.** A lowering would need a task/actor link in the compiled task runtime, which does not exist and is not cheap. It stays in `uncompiled_builtins`, and it was already in `Lower_expr.interpreter_only_builtin_reasons` and `test_builtin_compiled_lowering.ml`'s `interpreter_only`. |
| `unix_time_ms` | **Compiled and ran correctly.** It has had a `march_unix_time_ms` row since 2026-08-22 (#330), and the parity test is `test_compiled_unix_time_ms_parity`. | The `uncompiled_builtins` entry was stale. Stale here is not cosmetic: the drift test skips listed names, so `march_unix_time_ms` was in no cap table, and a binary using it carried **no IO.Clock marker** (checked with `nm`: `IO_Console` only). The row `march_unix_time_ms -> IO.Clock` was added. |
| `uuid_v7` | **Compiled and ran correctly,** but only because `mangle_extern`'s identity fallthrough emitted `call @uuid_v7` and the runtime happened to define an unprefixed C `uuid_v7`. This is the audit blind spot the todo called "worse". | Renamed to `march_uuid_v7` / `march_uuid_v7_at`, with explicit rows plus declares in the core preamble. `march_uuid_v7 -> IO.Clock` was added to `Cap_symbols.table`. `march_uuid_v7_at` now errors on a negative timestamp as the interpreter does, where before it silently produced a garbage prefix. |

`uncompiled_builtins` is now `[task_spawn_link; get_work_pool]`. A new test,
`test_uncompiled_builtins_not_stale`, fails on the reverse drift, meaning a listed
name that has a `c_name` row or a special lowering, or that is no longer a cap
builtin. Before, only the forward direction was checked, which is how two stale
entries went unnoticed for a month. `test_uuid_v7_marks_clock` and
`test_unix_time_ms_marks_clock` pin the markers.

Parity fixture: `test/native/uuid_v7_dns_parity.march`, run BOTH interpreted and
compiled against one golden. It checks the UUID v7 shape (8-4-4-4-12 lowercase hex,
version 7, variant 10xx), the exact `uuid_v7_at` timestamp prefixes (0, 1.7e12,
2^48-1), that `uuid_v7`'s embedded timestamp is within a minute of `unix_time_ms`,
that the builtin works as a closure body, and `dns_resolve` on a numeric host 200
times with zero allocation growth. Its two `corpus.baseline` lines were added.
`dns_resolve`, `uuid_v7` and `uuid_v7_at` left the "links because a same-named C
function exists" group in `test/test_builtin_compiled_lowering.ml` (and in
`specs/todos/2026-09-24-audit-same-named-runtime-builtin-abis.md`), because each now
has a declared signature.

## Found, not fixed

- `dns_resolve` resolves differently in the two backends. The interpreter asks
  `getaddrinfo` for IPv4 only and does not dedupe (`localhost` →
  `Ok([127.0.0.1, 127.0.0.1])`). The C runtime uses `AF_UNSPEC` and dedupes
  (`Ok([127.0.0.1, ::1])`). Filed as
  `specs/todos/2026-09-25-dns-resolve-interp-compiled-divergence.md`.
- The general user-fn/builtin symbol collision described in item 1.
