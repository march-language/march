# Object capabilities phase 3: compile-time capability checks in every mode — DONE (2026-11-10)

Plan: `specs/plans/2026-11-10-ocap-p3-checks-plan.md`; design:
`specs/2026-11-10-object-capability-design.md` §15 ("The compile-time checks run under
`march --check`, the interpreter and the REPL, not only `--compile`").

- `lib/driver/cap_static.ml`: the TIR-side checks (the module ceiling via `Cap_attrib` +
  `Cap_ceiling`, host scopes via `Net_scope.check`) lifted out of `bin/main.ml`'s compile arm;
  `check_program` lowers on demand and stops `Contract_pipeline.run` at the compile path's
  pre-opt point. The compile path calls the same functions: `scripts/oracle-base.sh ir`
  IDENTICAL (527 programs).
- `--check`, `--check-json`, `--emit-core-ast`, the interpreter, `--jit`, `march test`,
  `march check` (forge check/build) run it on a front-end-clean program; the typecheck-side
  subset ceiling now runs in every mode except a full compile.
- REPL: a `mod` at the prompt is re-checked as part of the session's program (full typecheck,
  so function bounds too, then `check_program`).
- LSP: `run_tir_pass` publishes the ceiling and host-scope findings.
- A program that cannot be lowered gets `cap_unchecked` (warning), not a verdict. A stdlib
  file checked as the entry is not judged by the ceiling (stdlib is transparent, design §4).
- Caches: interpreter verdict in the project CAS (key walks every source, flags, compiler);
  forge's `check_all_cache_key` now includes the compiler identity.
- Tests: `test/test_cap_mode_parity.ml` (one fixture set through 8 modes; known-gaps list
  empty), `test/test_check_cas_cap_strict.ml` (warm check cache vs host scope; interpreter
  cache vs a dependency edit), `test/errors/cap_{host_scope,host_unproven,unchecked}_1`,
  `cap_ceiling_6`, LSP `run_tir_pass` cases, forge cache-key case. types-oracle IDENTICAL
  after the stdlib fix.
- Measured (load 12-24, not quiet): interpreted hello-world cold +1.3 s, warm within noise;
  REPL `mod` declaration +~2.2 s.

Left open, filed 2026-11-10: `ceiling-nested-impl-method-uncharged`, `nested-path-scope-unchecked`,
`march-check-nested-module-resolution`, `repl-module-call-unknown-callee`,
`check-json-omits-contract-diagnostics`, `jit-ice-on-interpreter-only-builtin`,
`lsp-module-end-capability-checks`. Not run before the PR: the plan's Task 8 regression sweep
over examples/bench/test/stdlib and the full suite (left to CI).
