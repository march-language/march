# `march --jit file.march` — whole programs through the in-process ORC JIT

Landed 2026-08-25 (interpreter/REPL-performance plan, Phase 4 Task 4.1). Adds a
third execution engine alongside the tree-walking interpreter and the
clang-compiled binary.

## What it does

`march --jit file.march` runs the program through the REPL's in-process ORC
LLJIT instead of the interpreter. Everything upstream of execution is unchanged:
parse, desugar, import resolution, typecheck, `Refine_check`,
`Division_safety`, `Cap_infer` and the whole diagnostics pass all run exactly as
they do in interpreted mode, and the flag is dispatched *after* them — a new
`else if jit_run then` arm in `compile` (bin/main.ml), sitting between the
`compile_mode` arm and the interpreter's `else`. So `--jit` swaps the engine and
nothing else; a diagnostic can never differ because of it.

The engine is `Repl_jit.run_program` (lib/jit/repl_jit.ml), which mirrors
`register_module_decl` step for step — `check_module_with_env` against a reset
env, `lower_module ~stdlib_context:ctx.stdlib_decls` on the USER module only,
`fresh_wrap_state` / `emit_fns_fragment ~session_wraps` /
`compile_fragment` / `mark_compiled_fns` / `commit_wraps` — and adds an entry
point. The stdlib prelude comes from `Repl.maybe_precompile_stdlib`, so `--jit`
reuses the REPL's cached prelude `.so` rather than compiling stdlib per run.
Backend selection is the existing lazy `backend_is_orc ()`, so
`MARCH_JIT_BACKEND=clang` works for `--jit` too through the same
`compile_fragment` dispatch (both are pinned by tests).

Measured on `bench/interp/fib.march` scaled to `fib(30)` (min of 3, wall):
`--jit` 0.354 s, interpreted 1.063 s, compiled binary 0.042 s (run only,
excluding clang). Net of the flat ~0.34 s front-end + JIT cost, `--jit`'s
compute is at compiled speed — the win is skipping the clang/link step.

## Three design findings

**1. `mangle_extern "main"` is `"march_main"`.** `partition_fns` classifies a
function as a C-runtime function with `is_c_runtime_fn name = (mangle_extern
name <> name)`, so a bare `main` was silently dropped from *both* the define
list and the declare list, and the fragment failed to parse with `use of
undefined value '@march_main'`. Fix: rename the TIR `main` to a fragment-unique
`march_jit_user_main_<n>` via the existing capture-avoiding
`rename_top_fn_refs`, **before** `partition_fns`. This also keeps the definition
clear of the runtime `.so`'s own symbols in ORC's single JITDylib. (`Mod.main`
would not have tripped the filter, but is renamed uniformly.)

**2. The erased capability is `ptr null`, one per parameter — not a tagged
unit.** Confirmed at two sites that agree: `lib/tir/llvm_emit.ml`'s `AVar v when
v.v_name = "root_cap"` → `("ptr", "null")`, and `lib/tir/llvm_toplevel.ml`'s
`march_main_entry_thunk`, which passes `List.init main_arity (fun _ -> "ptr
null")` and is explicitly kept in step with `lib/eval/eval.ml`'s
`VUnit`-per-parameter `main` invocation. `run_program` generates the argument
list from `main_fn.fn_params` via `Llvm_ctx.llvm_ty`, emitting `ptr null` for
pointer-shaped parameters and `<ty> 0` as an honest fallback for a non-pointer
one (which would otherwise be an LLVM verifier error). Exercised live at 1 and 2
capability parameters.

**3. The entry must be the native three-call shape, not a direct call.**
`run_program` appends IR emitting `march_remote_init()` →
`march_spawn_main(<thunk>)` → `march_run_scheduler()`, exactly as the native
`@main` does. Calling the mangled `main` directly (the obvious approach) runs it
on the *host* thread rather than as a green thread, leaving the scheduler
unstarted — every `task_spawn` / `task_await` / HTTP program would deadlock.
With the native shape, `par_fib`, `par_map` and `http_server` all run correctly
under `--jit`. The two conditional declares go through a `declare_if_absent`
helper, because `Llvm_builtins`' `PDeclare` table emits `march_run_scheduler` /
`march_remote_init` only when a fragment happens to use them and LLVM rejects a
duplicate `declare`.

A consequence of (3), matching native exactly: **`main`'s value is not the
process exit code.** `march_spawn_main`'s ABI is `void (*)(void)` and native
`@main` returns a hard `0`.

## Known limitations (all deliberate, all experimental-stage)

- **`bench/interp/json_stream.march` dies with SIGBUS (rc 138) and no output**
  under `--jit`. Fails **identically under both backends**, so it is not an
  ORC artifact — something in the incremental fragment lowering or prelude
  linkage. Interpreted and compiled both give `checksum=28000`. Deferred to the
  Phase 4.2 decision note; every other corpus program is correct.
- **`argv` is empty.** The native `@main` calls `march_process_argv_init(argc,
  argv)`; the JIT entry has no argc/argv to hand it, so `march_process_argv()`
  sees the runtime's static `g_argc = 0`.
- **Actor programs are not JIT'd** — they fall back to the interpreter with a
  stderr notice, mirroring the REPL's own `actors_declared` guard.
- **Stdlib-shadowing programs are not JIT'd** — see hardening 3 below.
- `--jit` is not documented outside `march --help` and the changelog while it
  stays experimental.

## Fix round 1 hardenings (same feature, review follow-up)

**1. Host buffers are drained before control passes to JIT'd code.** JIT'd code
writes through the C runtime's own stdout and can terminate the process with C
`exit()` (`panic_`, `exit_`, a fatal signal), which never runs OCaml's
`at_exit` — so everything still sitting in OCaml's stdout/stderr buffers,
**including every warning and hint the diagnostics pass just printed**, was
lost. Measured on a warn-then-panic program with a private HOME: 3 warnings
interpreted, **0** under `--jit`, same exit code — the warning was invisible
precisely in the runs where it matters most. Fix: `flush stdout; flush stderr;`
immediately before `run_program`. `--jit` output for that program is now
identical to the compiled binary's, and carries the same warnings as
interpreted.

**2. No-`main` files and JIT failures degrade gracefully.** A file with no
`main` raised out as `Fatal error: exception Failure("--jit: no `main` …")` plus
an OCaml backtrace, rc=2 — where the interpreter is silent and exits 0. Now
`run_program` returns `()` for a mainless module, decided from the TIR
**before** any IR emission, dlopen or `march_spawn_main`, mirroring
`Llvm_toplevel.emit_module`'s `| None ->` branch. Any other `Failure` (fragment
compile error, clang failure) is caught in the `--jit` arm and reported as one
clean line — `march --jit: <msg>` on stderr, exit 1 — never a backtrace.
Verified with a deliberately-failing `clang` shim: `march --jit: clang failed
(IR preserved at …)`, rc 1.

**3. The `no_shadowing` guard is respected.** The `--jit` arm called
`get_stdlib_tc_env` unconditionally, bypassing the guard added one commit
earlier. That guard exists because the seed env built from a shadow-filtered
stdlib is unsound whether cached or not — and here the consequence is worse than
the wrong-diagnostics hazard it was originally added for, because
`run_program`'s `type_map` feeds **lowering**. `jit_run` now requires
`no_shadowing`; a shadowing program prints `march: --jit does not support
stdlib-shadowing programs yet; running interpreted` and runs interpreted.
Verified with the shadowed-`Json` fixture from `test/test_tcenv_cli_cache.ml`:
correct output, and no `stdlib_tcenv_cli_*` cache entry written.

## Tests

New `jit_file` group in `test/test_jit.ml` (subprocess-driven — `--jit` is a CLI
flag, and a miscompile here is a fatal signal that must not take the runner
down): whole-program run under ORC and under clang; actor fallback pinning
**both** the notice and the right answer; and one case per fix-round-1 finding.
All three fix-round cases were confirmed to **fail** against the pre-fix code
and pass after.

One wrinkle worth remembering: the flush test needs a **private HOME**, not the
file's shared `session_home`. The REPL harnesses leave that shared home holding
a stdlib prelude `.so` whose install-name points at a dead subprocess's runtime
`.so`, so every later run there prints "stdlib cache load failed …,
recompiling" — and that notice is written with an explicit flush, which
incidentally drains the very stderr buffer the test exists to check. On the
shared home the pre-fix binary **passes**; on a private home it fails. A
vacuous-pass hazard that looked like nothing.
