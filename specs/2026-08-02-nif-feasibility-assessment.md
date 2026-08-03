# March-as-Elixir-NIF: feasibility spike (phase 0)

Date filed 2026-08-02; spike run 2026-08-03 on macOS arm64, OTP 29 (erts-17.0.2),
Elixir 1.20.1-otp-29, against the worktree compiler.

**Verdict: the wedge is technically viable. All four planned kill points passed.**
March code runs inside a live BEAM as a NIF, allocates on the March heap from BEAM
scheduler threads, and runs its own green threads with preemption active, while the BEAM
stays responsive. One real defect was found (SIGUSR1 ownership, below) and one packaging
gap (no standalone-shared-library build mode). Neither is a blocker; both are fixable.

## What already existed

- `march --compile --compile-so` emits a `.so` with no `@main` (`emit_main:(not
  !compile_so)`, `bin/main.ml:2690`) and `-fPIC` runtime objects (`bin/main.ml:3016`).
- March emits **plain C-ABI signatures** for monomorphic Int functions: `define i64
  @Api.double(i64)`. No closure env, no boxing, no trampoline.
- Symbols are module-qualified with a literal `.` (`Api.double`) — legal in an object
  file, so a C caller reaches them with an `__asm__` label rather than by identifier.

## Findings, in the order they were established

### 1. `--compile-so` output is a patch, not a library

The first `dlopen` failed with `symbol not found in flat namespace
'_march_dispatch_enter'`. `--compile-so` deliberately omits `march_dispatch.c`,
`march_reload.c`, `march_blake3.c`, `march_cap_lattice.c` and `tweetnacl.c`
(`bin/main.ml:2795-2800`) and defers OpenSSL/zstd/brotli to the host binary — 221
undefined symbols in total. That is correct for a hot-reload patch loaded by a March host,
and wrong for anything the BEAM loads, because the BEAM provides none of it.

**Workaround used for the spike** (no compiler change): emit IR with `--emit-llvm`, then
link it directly against the full runtime —

```
clang -shared -fPIC -O1 -I<runtime> -I<erl_nif> \
  nif_shim.c module.ll $(ls runtime/*.c | grep -v wasm) \
  -lssl -lcrypto -lz -lzstd -lbrotlienc -lbrotlidec -lbrotlicommon -lblake3
```

**Implication:** a real NIF story needs a first-class standalone-shared-library mode
(`--emit shared-lib` or similar) — self-contained, `main`-less, with chosen exports.

### 2. Only `--hot-reload`-boundary functions are exported

In `--compile-so` mode every function gets `hidden` visibility except actor dispatch,
`*_migrate_state`, and members of the hot-reload name table (`lib/tir/llvm_toplevel.ml:189-227`).
Entry-module functions also get **bare, unqualified** symbols (`@double`, not
`@NifProbe.double`) — so `--hot-reload NifProbe` matched nothing until the functions were
moved into a nested `mod Api`. Bare names in a `.so` loaded into a host process are a
collision hazard in their own right.

Today `--hot-reload <Prefix>` is the only lever that makes a March function dlsym-able.
An explicit export annotation is the right long-term answer.

### 3. Step 1 — C ABI from a plain C driver: **PASS**

`dlopen` + `dlsym("Api.double")` + call. `Api.double(21) = 42`, `Api.double(-7) = -14`.
No runtime init of any kind. Unboxed `i64` in, unboxed `i64` out.

### 4. Step 2 — loaded as a NIF, called from Elixir: **PASS**

`ERL_NIF_INIT(Elixir.MarchNif, ...)`, `load/3` doing nothing. Correct results at 64-bit
width, 200k calls summing correctly, and a correct call after an explicit
`:erlang.garbage_collect()`.

### 5. Step 3 — allocation on the March heap from BEAM threads: **PASS**

String-building March functions called from BEAM scheduler threads, matching the native
control exactly (`4`, `18`). 20k allocating calls, then **14 schedulers × 5k concurrent
calls** — all schedulers returned the identical correct total, and a post-GC call was
still correct. **No March runtime init was needed**: `load/3` initialized nothing. The
allocator tolerates being entered from a foreign thread with no green thread current.

### 6. Step 4 — green threads + preemption inside the BEAM: **PASS**

`Task.async` × 2 + `Task.await`, called from a dirty CPU NIF. `task_spawn` from a foreign
thread reaches `march_ensure_sched_started`, which starts March OS worker threads and the
SIGUSR1 preemption daemon inside the BEAM process.

- 50 × `parallel_work(50000)` — one distinct (correct) result.
- 14 schedulers × 20 concurrent calls — one distinct (correct) result.
- Results identical to the single-threaded March control and to the native binary.

**Non-vacuity check** (the first run's workload was only 1.2ms, too short for a 10ms timer
to be meaningful, so it was re-run bigger): `parallel_work(200_000_000)` took **427ms**,
spanning ~42 preemption ticks, and `march_sched_total_spawned()` went 0 → 2 → 4, proving
green threads were really created. An Elixir canary process ticked **119 times during that
427ms call** — the BEAM kept scheduling normally throughout.

Both March functions were registered `ERL_NIF_DIRTY_JOB_CPU_BOUND`. Long-running March
work on a *normal* scheduler would wreck BEAM scheduling for ordinary NIF reasons, not
March-specific ones; dirty schedulers are mandatory in the docs we write.

### 7. Defect found: March overwrites the BEAM's SIGUSR1 handler

Measured directly by reading `sigaction(SIGUSR1)` before and after a March call:

```
SIGUSR1 handler BEFORE March: 0x100F0E7D0
SIGUSR1 handler AFTER  March: 0x10EEDB7B4   (green threads: 2)
```

The BEAM installs its own SIGUSR1 handler at startup — **SIGUSR1 is the BEAM's
crash-dump trigger**. March's preemption daemon replaces it process-wide the first time a
green thread is spawned. Nothing crashes, and preemption works, but the host VM silently
loses `erl_crash.dump`-on-SIGUSR1, and any BEAM-side re-installation would silently break
March preemption in the other direction.

This is not a design flaw in the wedge, it is a hardcoded constant: SIGUSR1 is reserved
throughout the runtime (`runtime/march_runtime.c:4659`). The fix is to make the preemption
signal selectable at init (e.g. SIGRTMIN-range on Linux, a configurable choice on macOS)
and to chain to the previously installed handler. Filed as
`specs/todos/2026-08-03-preempt-signal-configurable.md`.

## What this does NOT establish

- **Non-Int marshaling.** Every probe returned `Int`, deliberately, to isolate heap and
  scheduler questions from representation questions. String/list/record/Result marshaling
  across `ErlNifEnv` is untested, and March's tagged/erased-i64 convention makes it the
  next real design question.
- **Ownership across the boundary.** No March value was held by BEAM code across calls, so
  RC interaction with BEAM term lifetimes is unexplored. Resource types
  (`enif_alloc_resource`) plus March's linear handles is the design to write up — and it is
  also where the "the NIF can't corrupt the VM because the handle is linear" claim gets
  earned rather than asserted.
- **Linux.** macOS arm64 only. Linux uses different signal and `dlopen` semantics, and the
  runtime already carries a Linux-specific `SA_ONSTACK`/`SA_RESTART` fix for exactly this
  handler.
- **Long-running/soak behavior**, memory growth, or `enif_schedule_nif` yielding for work
  too long even for a dirty scheduler.
- **Supervision interop** — nothing here touches "keep supervision on both sides."

## Consequence for the plan

Phase 6's `/docs/elixir-nif/` can proceed and can be written as *demonstrated*, not
designed, provided it: uses dirty CPU NIFs, restricts the worked example to scalar
arguments (or lands marshaling first), and is honest that the packaging step is currently
a hand-rolled clang line rather than `forge build --target nif`. The two follow-on pieces
of real work are the standalone-shared-library build mode and the preemption-signal fix.
