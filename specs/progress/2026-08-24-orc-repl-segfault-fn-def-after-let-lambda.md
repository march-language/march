# ORC REPL backend: SIGSEGV defining a fn after a let-bound lambda/map

## Minimal repro

```
fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end
let ys = List.map(List.range(1, 10), fn x -> x * 2)
fn sq(x) do x * x end
```

Run via:
```bash
MARCH_JIT_BACKEND=orc ./_build/default/bin/main.exe < repro.txt
```

**Result:** Process exits with code 139 (SIGSEGV) on the third line.

## Control case

Two consecutive `fn` definitions without the intervening let-lambda work fine:

```
fn fib(n) do if n < 2 do n else fib(n-1) + fib(n-2) end end
fn sq(x) do x * x end
```

**Result:** Both backends handle this without error.

## Context

The default clang backend handles the same session fine. This blocks flipping ORC to the default REPL backend (perf plan Phase 2.2) until fixed or root-caused. Found while building `bench/interp/repl_session.txt`, which was narrowed to avoid it.

## Status: FIXED (2026-08-24)

## Correction to the control case

The filed control ("two consecutive `fn` defs without the intervening
let-lambda work fine") is **wrong**. On ORC that session also exits 139:

```
fn f(x) do x + 1 end
fn g(x) do x * 2 end      <- SIGSEGV here
```

`let a = 1` followed by `fn sq(x) do x * x end` is the real healthy control.
The let-bound lambda in the original repro was incidental — the trigger is
simply *a second `fn` definition in a session that already has a `fn`
binding in a slot*.

## Root Cause

Two stacked defects, both required to explain "exit 139 instead of an error".

### 1. Duplicate external symbol across fragments (`lib/tir/llvm_repl.ml`)

`emit_slot_loader_fns` emits, for every prior REPL slot, a thin module-level
loader named after the **bare binding**:

```llvm
define ptr @fib() {          ; loads slot 0 via @march_repl_get
```

It is called by `emit_repl_fn` / `emit_repl_fn_with_closure_slot`, i.e. by
every `fn` fragment. When the prior binding is itself a REPL `fn`, an earlier
fragment already emitted the real definition under that exact symbol:

```llvm
; repl_0.ll
define i64 @fib(i64 %n.arg) { ... }
; repl_2.ll  (fragment for `fn sq`)
define ptr @fib() { ... }     ; <- same symbol, different signature
```

Under the **clang** backend each fragment is a separate `.so`, so the local
definition wins inside that `.so` and the collision is invisible. Under
**ORC** every fragment is added to ONE LLJIT `JITDylib`, and the second
external definition is a hard error from `addIRModule`. Evidence, after
fixing (2) below:

```
march(2)> jit error: LLVMOrcLLJITAddLLVMIRModule: In repl_1, duplicate definition of symbol '_f'
```

(Re-emitting `@fib()` in each *later* `fn` fragment would also collide with
itself, so this is not only a fn-vs-loader problem.)

### 2. Double-free on the ORC add-module error path (`lib/jit/jit_orc_stubs.c`)

The error from (1) never reached the user, because the cleanup branch was
itself unsound:

```c
LLVMErrorRef err = LLVMOrcLLJITAddLLVMIRModule(J, MainJD, TSM);
/* On success TSM is consumed; on failure the caller still owns it. */  /* FALSE */
if (err) { LLVMOrcDisposeThreadSafeModule(TSM); ... }
```

`LLVMOrcLLJITAddLLVMIRModule` wraps `TSM` in a `std::unique_ptr<ThreadSafeModule>`
on entry (`OrcV2CBindings.cpp`) and destroys it on return **regardless** of the
`Error` it produces. The explicit dispose therefore re-runs `~ThreadSafeModule`
on freed memory, which locks the already-destroyed `ThreadSafeContext` mutex.
lldb backtrace of the SIGSEGV:

```
frame #0: libsystem_pthread.dylib`pthread_mutex_lock + 12   (EXC_BAD_ACCESS, x0 = 0x1438fe)
frame #1: libc++.1.dylib`std::__1::recursive_mutex::lock()
frame #2: libLLVM.dylib`llvm::orc::ThreadSafeContext::withContextDo<~ThreadSafeModule::'lambda'>(...)
frame #3: libLLVM.dylib`llvm::orc::ThreadSafeModule::~ThreadSafeModule()
frame #4: libLLVM.dylib`LLVMOrcDisposeThreadSafeModule
frame #5: main.exe`march_orc_add_ir at jit_orc_stubs.c:213
frame #8: camlMarch_jit__Repl_jit.compile_fragment
frame #9: camlMarch_jit__Repl_jit.run_decl
```

So *any* recoverable add-module error under ORC killed the whole REPL.

## Fix

- `lib/jit/jit_orc_stubs.c`: drop the `LLVMOrcDisposeThreadSafeModule(TSM)`
  from the error branch (the C API already owns and destroys it); just report
  the error. Recoverable ORC errors are now reportable instead of fatal.
- `lib/tir/llvm_repl.ml`: emit the prev-slot loaders as
  `define internal <ty> @<bare>()`. Every reference to them is inside the same
  module, so module-local linkage is free — and `internal` symbols never enter
  the JITDylib symbol table, so neither the fn-vs-loader nor the
  loader-vs-loader collision can arise. No effect on the clang backend beyond
  removing a latent flat-namespace shadowing hazard.

## Validation

- 3-line repro: ORC exit 0, output identical to clang.
- 12-line session (fib / ranges / maps / sq / string_join / fib(22)):
  `diff` of ORC vs clang output is empty; both exit 0; `fib(22) = 17711`.
- `test/test_jit.ml`: two new ORC REPL-session regression tests (subprocess,
  so a SIGSEGV cannot take the runner down; skipped when
  `Jit_orc.available () = false`). Verified non-vacuous — they report
  `Received: 139` against the un-fixed compiler.
- `scripts/run-tests.sh -q` and `./_build/default/test/test_jit.exe -e`: pass.

## Follow-up noticed — since FIXED

A `fn` whose body references a prior REPL `fn` (`fn f(x) do x+1 end` then
`fn g(x) do f(x)+1 end`) failed on **both** backends — the fragment emitted
both the prev-slot loader `define @f()` and an unknown-function-fallback
`declare @f(...)` for the same symbol ("invalid redefinition"), after which
the REPL reported "I cannot find `g`". Fixed in
`2026-08-24-repl-jit-fn-calls-prior-repl-fn.md`: calls to slot-loader names
now route through the loader + closure dispatch (a `repl_slot_fns` ctx
table), so the declare is never emitted and the call follows the slot.
