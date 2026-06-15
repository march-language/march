# Green Thread Scheduler — Implementation Plan

## Overview

Replace the current actor-mailbox scheduler (message-passing only) with a full M:N
green-thread scheduler that can run any March function as a lightweight process.
Implemented incrementally across phases:

```
OS threads (N=1)     OS threads (N=worker pool)
      │                         │
  Phase 1             Phase 3 (work-stealing)
  │                   │
  Basic ucontext      Multi-thread + atomic deque
  single scheduler    per-scheduler local queue
```

**C runtime phases 1–4 are complete.** The remaining work is wiring the C scheduler
into compiled March programs end-to-end: fixing the `bin/main.ml` gating bug, implementing
`task_await` as a real blocking wait, and adding compiled-mode codegen for all five
cancel-token builtins.

---

## Phase 1 — Basic green thread scheduler in C runtime ✅

**Goal:** Prove out the core context-switching primitives on a single OS thread.

**Files:**
- `runtime/march_scheduler.h` — public API + types
- `runtime/march_scheduler.c` — implementation
- `test/test_scheduler.c` — C test suite (4 tests)
- `test/dune` — dune rule to compile and run C tests

**Process struct** (`march_proc`):
| Field | Type | Purpose |
|---|---|---|
| `pid` | `int64_t` | Unique ID (monotonic counter) |
| `status` | `march_proc_status` | `READY / RUNNING / WAITING / DEAD` |
| `priority` | `march_proc_priority` | `NORMAL / HIGH` |
| `reductions` | `int64_t` | Budget remaining this quantum |
| `stack_base` | `void *` | mmap'd stack (above PROT_NONE guard page) |
| `stack_alloc` | `size_t` | Total mmap size (stack + guard) |
| `mailbox` | `march_mbox_node *` | Message queue head (Phase 2) |
| `ctx` | `ucontext_t` | Saved execution context |
| `fn` / `arg` | fn ptr + `void *` | Entry point |
| `next` | `march_proc *` | Intrusive run-queue link |

**Scheduler** (`march_scheduler`): single global instance, single OS thread.
- FIFO run queue (intrusive linked list)
- `sched_ctx`: the scheduler's own `ucontext_t`; all processes yield back here
- Round-robin: dequeue → run quantum → re-enqueue if READY, free if DEAD

**API:**
```c
void         march_sched_init(void);
void         march_sched_run(void);
march_proc  *march_sched_spawn(void (*fn)(void *), void *arg);
void         march_sched_yield(void);
void         march_sched_tick(void);   // decrement; yield if budget == 0
void         march_sched_exit(void);
```

**Context switching:** `ucontext_t` / `makecontext` / `swapcontext`.
Each stack is `mmap(PROT_READ|PROT_WRITE)` with a `PROT_NONE` guard page.
Default stack size: `MARCH_STACK_SIZE` = 64 KiB.
Reduction budget: `MARCH_REDUCTION_BUDGET` = 4000.

**Tests (all passing):**
1. `test_spawn_1000` — 1000 processes increment a counter; verify == 1000
2. `test_yield_interleaving` — explicit yields produce A→B→A→B ordering
3. `test_reduction_preemption` — `march_sched_tick()` causes automatic yield
4. `test_nested_spawn` — processes can spawn child processes

---

## Phase 2 — Message passing + PROC_WAITING ✅

**Goal:** Allow processes to block on mailbox receive without busy-waiting.

**Implemented:**
- `march_mbox_node *mailbox` + `mbox_tail` — FIFO message queue per process
- `march_sched_send(march_proc *, void *msg)` — enqueue message + wake target
- `march_sched_recv(void)` — dequeue next message, or park as PROC_WAITING
- `march_sched_try_recv(void)` — non-blocking receive
- `march_sched_wake(target)` — re-enqueue a WAITING process
- `march_sched_find(pid)` — O(1) process lookup by PID
- Spinlock (`mbox_lock`) protects recv's check-then-park against send race
- **Actor convergence:** `march_runtime.c` actor scheduling replaced with green thread
  delegation. Each actor gets a green thread running `recv → dispatch → loop`.
  `march_send` delegates to `march_sched_send`. Old worker pool, Treiber stack mailbox,
  and `process_actor_turn` removed.

**Tests (4):** `test_send_recv_basic`, `test_send_recv_multiple`, `test_waiting_wakeup`,
`test_try_recv`

---

## Phase 3 — Multi-thread M:N with work-stealing ✅

**Goal:** Scale to multiple OS threads with minimal contention.

**Implemented:**
- `N` OS threads (default `MARCH_NUM_SCHEDULERS=4`), each with its own `march_scheduler`
- Per-scheduler Chase-Lev work-stealing deque (`runtime/march_deque.h`, capacity 4096)
- Work-stealing: idle thread steals from random victim's deque (LCG selection)
- Spawn balancer: new processes round-robin to schedulers, prefer local deque
- Quiescence: `g_live_procs` atomic counter; `g_all_done` flag
- Thread-local `tl_sched` pointer for all scheduler operations
- `owner_sched` field on `march_proc` so trampoline returns to correct scheduler
- All status reads/writes are atomic (`_Atomic march_proc_status`)

**Tests (3):** `test_multithread_spawn_10000`, `test_multithread_send_recv`, `test_work_stealing`

---

## Phase 4 — Stack growth (lazy virtual-memory) ✅

**Goal:** Start each process with a small stack (4 KiB) and grow on demand.

**Implemented:**
- `MARCH_STACK_INITIAL` = 4 KiB initial usable stack per green thread
- `MARCH_STACK_MAX` = 1 MiB maximum usable stack per green thread
- Each process reserves `MARCH_STACK_MAX + page` virtual memory all as `PROT_NONE`,
  then makes only the top `MARCH_STACK_INITIAL` bytes read/write initially.
- A `SIGSEGV` handler (`march_sigsegv_handler`) installed via
  `sigaction(SA_SIGINFO | SA_ONSTACK)` catches guard-page faults, calls `mprotect` to
  extend the accessible window downward, then returns — the CPU retries the faulting
  instruction automatically.
- Per-scheduler-thread alternate signal stack (64 KiB) set up in `sched_loop()` via
  `sigaltstack`, ensuring the handler runs even when the green thread's own stack is full.
- `p->stack_base` tracks the current bottom of the usable region and is updated on each growth.
- Exceeding `MARCH_STACK_MAX` hits the permanent guard page → unrecoverable crash.
- No pointer fixup required: the virtual address range is pre-reserved, growth is in-place.

**Tests (2):**
- `test_stack_growth_deep` — one process recurses ≈10 KiB deep (> 4 KiB initial), completes
- `test_stack_growth_many` — 50 processes each recurse ≈10 KiB deep concurrently, all complete

---

## Phase 5 — Language-level wiring (CURRENT WORK)

**Goal:** Make compiled March programs actually use the C scheduler end-to-end for
`task_spawn`, `task_await`, `task_yield`, and all cancel-token operations.

### Known Design Issues (must fix before shipping)

#### BLOCKING: `march_scheduler.c` gated behind HTTP check in `bin/main.ml`

The `ensure_runtime_so` function and the direct-compile path both only include
`march_scheduler.c` when HTTP modules are detected. A plain CLI program using `task_spawn`
will get an undefined-symbol link error for `march_task_spawn_thunk`,
`march_run_scheduler`, `march_tls_reductions`, and `march_yield_from_compiled`.

**Fix:** Move `march_scheduler.c` out of the HTTP block — always append it to `extra_files`
and `extra_c_files` regardless of HTTP usage. (Stub below.)

#### BLOCKING: `task_await` in compiled mode reads the wrong thing

`task_await` in `llvm_emit.ml` (lines 2182–2195) is an inline load of `task[field 0]`
boxed into `Ok(value)`. The problem: field 0 stores the `march_proc*` green-thread handle,
not the task's return value. The trampoline (`march_thunk_trampoline`) discards the return
value of `apply(clo, 0)`. Result: `task_await` returns a garbage pointer dressed as `Ok`.

**Fix:**
1. Extend the Task heap object from 24 to 32 bytes — add `field 1` as a `void*` result slot.
2. In `march_thunk_trampoline`, store `apply(clo, 0)` into `task->field1` before calling
   `march_sched_exit`.
3. Implement `march_task_await(task_ptr)` in C: spin-yield until proc status == DEAD, then
   return `Ok(field1)`.
4. In `llvm_emit.ml`, replace the inline load with `call ptr @march_task_await(ptr %task_ptr)`.

#### BLOCKING: Five cancel-token builtins have no compiled-mode implementation

`task_cancel_token_new`, `task_cancel`, `task_is_cancelled`, `task_spawn_with_cancel`,
`task_cancel_by_id` are handled in the interpreter and in `stdlib/task.march` but have
zero compiled-mode codegen. They are absent from `known_builtins` in `llvm_emit.ml` and
have no corresponding C wrappers in `march_runtime.h`. Any compiled program using them
will fail at link time.

**Fix:** Add five codegen cases in `llvm_emit.ml` and matching C wrapper declarations.
(Stubs below.)

#### MAJOR: OCaml `lib/scheduler/` modules are interpreter-only scaffolding

`scheduler.ml`, `task.ml`, `mailbox.ml`, `work_pool.ml` have no connection to the C runtime.
The only consumer is `lib/eval/eval.ml` for cooperative reduction-counting. In compiled
programs, tasks are C `march_proc*` handles, not OCaml `Task.task` values. The naming
creates the false impression that these modules are wired.

**Fix:** Add header comments to each file making the scope explicit. Delete `work_pool.ml`
and `mailbox.ml` since they are unreferenced from outside the package.

#### MAJOR: `task_yield` emits a no-op in compiled mode

`llvm_emit.ml` (lines 2197–2199) emits `ret i64 0` for `task_yield()`. Phase 4 (green
threads + reduction counting) is already in use, so this should call `march_sched_yield()`.

**Fix:** Replace the no-op with `call void @march_sched_yield()`.

#### MINOR: `task_reductions` always returns literal 0

Should read `@march_tls_reductions` thread-local storage. Already declared in the LLVM
preamble — just needs an actual load.

---

## Code Stubs

### `bin/main.ml` — always include `march_scheduler.c`

```ocaml
(* Replace the HTTP-gated block at lines 295-309 with: *)
let extra_files =
  let sched_c   = Filename.concat runtime_dir "march_scheduler.c" in
  let base_files = opt_file sched_c ^ " " ^ opt_file extras_c ^ " " ^ opt_file compress_c in
  if Sys.file_exists http_c then
    let sha1_c    = Filename.concat runtime_dir "sha1.c" in
    let base64_c  = Filename.concat runtime_dir "base64.c" in
    let simd_c    = Filename.concat runtime_dir "march_http_parse_simd.c" in
    let resp_c    = Filename.concat runtime_dir "march_http_response.c" in
    let io_c      = Filename.concat runtime_dir "march_http_io.c" in
    let evloop_c  = Filename.concat runtime_dir "march_http_evloop.c" in
    let tls_c     = Filename.concat runtime_dir "march_tls.c" in
    Printf.sprintf "%s %s %s %s%s%s%s%s%s" http_c sha1_c base64_c
      (opt_file simd_c) (opt_file resp_c) (opt_file io_c)
      (opt_file evloop_c) (opt_file tls_c) base_files
  else
    base_files
in
(* Apply the same change to the direct-compile extra_c_files at lines 1259-1273 *)
```

### `runtime/march_runtime.c` — implement `march_task_await`

```c
/* Await the completion of a task.
 * Task heap object layout (32 bytes after this change):
 *   field 0 (word 2, offset 16): march_proc* — green thread handle
 *   field 1 (word 3, offset 24): void*       — result (set by trampoline)
 */
void *march_task_await(void *task_obj) {
    if (!task_obj) return march_mk_err_cstr("task_await: null task");
    int64_t *task = (int64_t *)task_obj;
    march_proc *p = (march_proc *)(uintptr_t)task[2];
    if (!p) return march_mk_err_cstr("task_await: null proc");

    /* Spin-yield until the task proc is DEAD.
     * Phase 5b: replace with mailbox notification (task registers awaiter). */
    while (atomic_load_explicit(&p->status, memory_order_acquire) != PROC_DEAD)
        march_sched_yield();

    void *result = (void *)(uintptr_t)task[3];
    return march_mk_ok(result);
}

/* In march_thunk_trampoline — extend to store the return value: */
static void *march_thunk_trampoline(void *clo_ptr) {
    void *task_obj = tl_current_task;  /* thread-local set by spawn */
    void *result = apply(clo_ptr, (int64_t)0);
    if (task_obj) {
        int64_t *task = (int64_t *)task_obj;
        task[3] = (int64_t)(uintptr_t)result;  /* store result in field 1 */
    }
    march_sched_exit();
    return NULL;
}
```

### `lib/tir/llvm_emit.ml` — replace broken task_await, add cancel-token codegen

```ocaml
(* Add to LLVM preamble (non-REPL block, after line 4342): *)
"declare ptr  @march_task_await(ptr %task)\n\
 declare void @march_sched_yield()\n\
 declare ptr  @march_cancel_token_new()\n\
 declare void @march_cancel_token_cancel(ptr %tok)\n\
 declare i64  @march_cancel_token_is_cancelled(ptr %tok)\n\
 declare ptr  @march_task_spawn_with_cancel_thunk(ptr %clo, ptr %tok)\n\
 declare void @march_task_cancel_by_id(ptr %task)\n"

(* Replace broken inline task_await (lines 2182-2195) with: *)
| Tir.EApp (f, [a]) when f.Tir.v_name = "task_await" ->
  let (_, tp) = emit_atom ctx a in
  let r = fresh ctx "tawait" in
  emit ctx (Printf.sprintf "%s = call ptr @march_task_await(ptr %s)" r tp);
  ("ptr", r)

(* Replace no-op task_yield (lines 2197-2199) with: *)
| Tir.EApp (f, []) when f.Tir.v_name = "task_yield" ->
  emit ctx "call void @march_sched_yield()";
  ("i64", "0")

(* Fix task_reductions to read TLS (lines 2209-2211): *)
| Tir.EApp (f, []) when f.Tir.v_name = "task_reductions" ->
  let r = fresh ctx "reds" in
  emit ctx (Printf.sprintf "%s = load i64, ptr @march_tls_reductions" r);
  ("i64", r)

(* Add cancel-token cases after task_reductions: *)
| Tir.EApp (f, []) when f.Tir.v_name = "task_cancel_token_new" ->
  let r = fresh ctx "ctok" in
  emit ctx (Printf.sprintf "%s = call ptr @march_cancel_token_new()" r);
  ("ptr", r)

| Tir.EApp (f, [tok]) when f.Tir.v_name = "task_cancel" ->
  let (_, tp) = emit_atom ctx tok in
  emit ctx (Printf.sprintf "call void @march_cancel_token_cancel(ptr %s)" tp);
  ("i64", "0")

| Tir.EApp (f, [tok]) when f.Tir.v_name = "task_is_cancelled" ->
  let (_, tp) = emit_atom ctx tok in
  let r = fresh ctx "isc" in
  emit ctx (Printf.sprintf "%s = call i64 @march_cancel_token_is_cancelled(ptr %s)" r tp);
  ("i64", r)

| Tir.EApp (f, [clo; tok]) when f.Tir.v_name = "task_spawn_with_cancel" ->
  let (_, cp) = emit_atom ctx clo in
  let (_, tp) = emit_atom ctx tok in
  let r = fresh ctx "tswc" in
  emit ctx (Printf.sprintf "%s = call ptr @march_task_spawn_with_cancel_thunk(ptr %s, ptr %s)" r cp tp);
  ("ptr", r)

| Tir.EApp (f, [t]) when f.Tir.v_name = "task_cancel_by_id" ->
  let (_, tp) = emit_atom ctx t in
  emit ctx (Printf.sprintf "call void @march_task_cancel_by_id(ptr %s)" tp);
  ("i64", "0")
```

### `runtime/march_runtime.c` — `march_task_spawn_with_cancel_thunk`

```c
void *march_task_spawn_with_cancel_thunk(void *clo_ptr, void *tok_ptr) {
    if (!g_sched_initialized) { march_sched_init(); g_sched_initialized = 1; }
    march_ensure_sched_started();
    march_cancel_token *tok = (march_cancel_token *)tok_ptr;
    march_proc *p = march_sched_spawn_with_cancel(march_thunk_trampoline, clo_ptr, tok);
    int64_t *task = (int64_t *)march_alloc(32);  /* rc+tag+proc_ptr+result_ptr */
    if (task) {
        task[2] = (int64_t)(uintptr_t)p;
        task[3] = 0;
    }
    return (void *)task;
}

void march_task_cancel_by_id(void *task_obj) {
    if (!task_obj) return;
    /* Cancel by writing to the proc's cancel token if it has one.
     * For now: set the proc status to DEAD directly (simplified). */
    int64_t *task = (int64_t *)task_obj;
    march_proc *p = (march_proc *)(uintptr_t)task[2];
    if (p) atomic_store_explicit(&p->status, PROC_DEAD, memory_order_release);
}
```

---

## Test Plan

| Test | File | What | Pass criterion |
|---|---|---|---|
| `compile_task_spawn_await_basic` | `test/test_march.ml` | `task_spawn(fn _ -> 42)` then `task_await` | stdout = `Ok(42)` |
| `compile_task_await_blocks_until_done` | `test/test_march.ml` | Spawned task does heavy work; await returns correct result | No hang, correct value |
| `compile_task_cancel_token_roundtrip` | `test/test_march.ml` | `token_new` + `cancel` + `is_cancelled` | IR has all three declares; binary returns `true` |
| `compile_task_spawn_with_cancel_precancelled` | `test/test_march.ml` | Pre-cancel token, then spawn | Binary stdout = `Err("cancelled")` |
| `compile_task_yield_actually_yields` | `test/test_march.ml` | Two tasks alternating via yield | IR contains `call void @march_sched_yield()`; both tasks run |
| `compile_non_http_program_links_scheduler` | `test/test_march.ml` | Compile a non-HTTP task_spawn program | No linker error; binary exits 0 |
| `compile_task_reductions_reads_tls` | `test/test_march.ml` | IR for `task_reductions()` | IR contains `load i64, ptr @march_tls_reductions` |
| `c_test_task_spawn_await_result` | `test/test_scheduler.c` | C-level: trampoline stores result; await retrieves it | Asserts pass |
| `c_test_cancel_token_spawn_trampoline` | `test/test_scheduler.c` | Pre-cancel skips user_fn body | Flag NOT set after scheduler runs |

---

## Documentation Plan

| Section | File | What |
|---|---|---|
| Phase 5 (this section) | This file | Document blocking issues and fixes — done above |
| OCaml `lib/scheduler/` scope | Header of each `.ml` file | Add comment: "interpreter-only; not wired to C runtime" |
| `task_await` semantics | `specs/features/scheduler.md` | Update: "blocks calling green thread until task complete; returns Ok(result)" |
| Cancel tokens in compiled mode | `specs/features/scheduler.md` | Add section documenting the C runtime API and LLVM codegen |
| `bin/main.ml` compile path | `CLAUDE.md` or inline comment | Note that `march_scheduler.c` is always included in compiled binaries |

---

## Build Integration

C runtime files (`runtime/`) are not part of the OCaml dune build — they are emitted
alongside compiled March programs by the LLVM code generator.

For testing the C scheduler standalone, `test/dune` contains a `(rule)` that uses `%{cc}`
to compile and run `test/test_scheduler.c` as part of `dune runtest`.

```dune
(rule
 (targets test_scheduler_runner)
 (deps    test_scheduler.c
          ../runtime/march_scheduler.c
          ../runtime/march_scheduler.h)
 (action  (run %{cc} -std=gnu11 -Wall -Wextra -I../runtime
               -o %{targets}
               test_scheduler.c ../runtime/march_scheduler.c)))
```

---

## Note on OCaml `lib/scheduler/` Modules

The four OCaml modules under `lib/scheduler/` (`scheduler.ml`, `task.ml`, `mailbox.ml`,
`work_pool.ml`) are **interpreter-only scaffolding**. They are not wired to the C green-
thread runtime at any level. The only live consumer is `lib/eval/eval.ml`, which uses
`March_scheduler.Scheduler.tick/reset_budget` for cooperative reduction-counting in the
tree-walking interpreter.

In compiled programs:
- Tasks are C `march_proc*` handles, not OCaml `Task.task` values.
- The Chase-Lev deque in `work_pool.ml` is duplicated logic already implemented in
  `runtime/march_deque.h`.
- `mailbox.ml` is completely unreferenced outside the package.

`work_pool.ml` and `mailbox.ml` should be deleted. `scheduler.ml` and `task.ml` should
have header comments making their scope explicit.
