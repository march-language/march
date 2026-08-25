# `[P2]` ORC backend: multiple in-process REPL JIT sessions collide in the shared LLJIT

With ORC as the default backend (libLLVM present), `Repl_jit.create` sessions
share ONE process-global LLJIT (`orc_instance` in `lib/jit/repl_jit.ml`). The
second session's first fragment re-defines prelude-synthesized symbols in the
same shared JITDylib and fails with:

```
LLVMOrcLLJITAddLLVMIRModule: In repl_0, duplicate definition of symbol '_Eq$Int.eq'
```

First seen as 21 failures in `run_codegen.exe`'s `repl_jit_cross_line` /
`repl_jit_regression` groups after `d4b634e0` (ORC-by-default). Interim
mitigation: `test/test_helpers.ml`'s `setup_jit_runtime` pins
`set_backend_for_tests \`Clang` for in-process tests, so they exercise the
clang + dlopen pipeline they were written against; `test/test_jit.ml`'s
subprocess sessions cover ORC end-to-end.

Real fix direction: per-session JITDylib (with resource-tracker removal in
`cleanup`), or dedup/skip already-defined prelude symbols on later sessions.
A background task session was started for this on 2026-08-24. Remove the
`set_backend_for_tests` pin (or narrow it) when fixed so in-process tests can
run under the default backend again.
