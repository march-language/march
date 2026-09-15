# Codegen: a user fn named after a C symbol the runtime links against hijacked the runtime

Found and fixed 2026-09-14, out of the two-node harness
([[2026-09-14-two-node-failure-semantics-harness]]): `node_a.march`'s
`pfn connect(port : Int) : Int`, called twice, compiled to a program that
died `fatal SIGBUS … stack guard page (overflow)` before its first print;
renamed, byte-for-byte otherwise identical, it ran.

## Cause

A top-level user function is emitted under its bare March name
(`define i64 @connect(i64 %port.arg)`), in the same link as the C runtime and
the libc/libm it calls. The runtime's `tcp_connect` calls `connect()`; the
link resolved that undefined reference to the user's definition before
libSystem, so `Socket.connect` → runtime → user `connect` → `Socket.connect`
→ … until the guard page. Any user fn named after a symbol the runtime
imports (`log`, `time`, `strlen`, `write`, `read`, `close`, `exit`, `free`,
`sqrt`, …) had the same fate, crashing somewhere in the runtime far from the
user's code. A single-call-site `pfn` dodged it only because it was inlined
and never emitted — which is why the minimal repros passed and the bisect
took three rounds.

Distinct from [[2026-09-14-user-fn-named-own-miscompiled-as-resource-builtin]]
(a lowering special case keyed on a bare name); this one is at the link.

## Fix

`lib/tir/llvm_builtins.ml`: `c_reserved_symbols`, every symbol
`runtime/*.c` imports (nm -u over the compiled objects, macOS) plus the
common libc/libm/POSIX/Linux surface; `user_symbol_of` emits a bare name in
that set as `name$u`. Applied at the one place a March name becomes a symbol
— the identity fallthrough of `mangle_extern` and `c_symbol_of_march_name` —
so the definition and every reference agree. Qualified names
(`Socket.connect`), compiler-generated ones (`$clo_wrap`), and names the
builtin table maps itself (`main` → `march_main`) are untouched; the
runtime's own `march_*` names must pass through unchanged (a builtin
resolved by the fallthrough, `march_decrc_freed`, reaches its C definition
that way — the first cut mangled the prefix and broke every program).

`lib/jit/repl_jit.ml`: `is_c_runtime_fn` asked `mangle_extern name <> name`,
which the mangling would now answer "yes" for a user `fn connect`; it now
asks table membership (`Llvm_builtins.has_c_mapping`), the question it meant.

Checked: no typecheck builtin resolved by the fallthrough is in the reserved
set (the four overlaps — `base64_encode`, `kill`, `md5`, `sha256` — all
have explicit C mappings).

## Witnesses

- `test/native/c_symbol_collision.march`: user `connect`/`log`/`time`/`strlen`,
  each used twice, with `Socket.connect` to a refused port and `Math.log`
  through the runtime; compiled output matches the interpreter (before the
  fix: never returned).
- `test_codegen` "user fn named after a C symbol is mangled": the IR defines
  and calls `@connect$u`, never bare `@connect`, and a non-colliding fn keeps
  its name.
