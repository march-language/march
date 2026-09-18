# FIXED: each REPL JIT session owns its LLJIT (closed 2026-09-18)

The fix landed in #341 (`368181a7f`, 2026-08-24), two hours after this was filed.
`Repl_jit.get_orc` creates the LLJIT lazily **per session** and caches it on the
session record, and `cleanup` disposes it. There is no process-wide instance, so
a second session's prelude cannot collide with the first's. This file stayed open
because nothing proved the fix, and the test-side workaround was never removed.

## Closing it

- **The guard.** `test_codegen.ml`'s "two live ORC sessions in one process" keeps
  two sessions alive at once and evaluates `1 == 1` (which pulls in the
  prelude-synthesized `Eq$Int.eq`) in the order a, b, a. The rest of the
  `repl_jit_*` groups create sessions one after another and never overlap, so
  they could not catch a regression back to a shared instance. The test skips,
  and counts the skip, when libLLVM does not load.
- **RED control.** A temporary patch made `get_orc` share one process-global
  LLJIT, with `cleanup`'s dispose disabled so a double-free could not mask the
  result. The new test then failed with the original error class:
  `LLVMOrcLLJITAddLLVMIRModule: In repl_0, duplicate definition of symbol
  '_Show$Atom.show'`. It passes on the real code.
- **Pin removed.** `test/test_helpers.ml`'s `setup_jit_runtime` no longer forces
  `Clang`, so in-process JIT tests run on the default backend (ORC when libLLVM
  loads). The 29 `repl_jit_cross_line` / `repl_jit_regression` cases, the groups
  that had 21 failures originally, pass under ORC in 1.1s and under forced
  `MARCH_JIT_BACKEND=clang` in 19.4s.

---

The original filing follows.

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
