# Foreign-Thread Actor Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `spawn` / `send` / `task_spawn`+`task_await` / `actor_call` work correctly and efficiently when called from non-scheduler OS threads — specifically the HTTP evloop pthreads — so downstream apps (forgepm + conduit) can enqueue jobs and use depot's actor-based Pool from HTTP request handlers.

**Architecture:** The runtime already half-supports foreign threads: `march_sched_spawn` pushes onto a lock-free external stack (`g_ext_spawn_head`) when called off-scheduler, `march_ensure_sched_started` auto-starts a background scheduler, and `march_task_await` has a spin fallback. The prime defect is `march_sched_wake`, which pushes into scheduler 0's Chase-Lev deque from non-owner threads — a data race (the deque is documented owner-push-only) that loses wakeups, leaving green threads parked forever → handler hangs → 503. The plan: diagnose to confirm, route foreign wakes through the same external stack, drain that stack every scheduler-loop iteration, replace the foreign `task_await` busy-spin with a condvar, add a C-level foreign-caller bridge to `march_actor_call` (with a real timeout via `pthread_cond_timedwait`), and enforce the (currently ignored) `actor_call` timeout on the green-thread path.

**Tech Stack:** C11 atomics + pthreads (`runtime/march_scheduler.c`, `runtime/march_runtime.c`), March native tests (`test/native/*.march` + dune compile-and-diff rules).

**Reference spec:** forgepm repo `specs/conduit-background-jobs.md`, sub-project 1.

## Global Constraints

- Repo: `/Users/80197052/code/march`, worktree `.claude/worktrees/foreign-thread-actor-bridge`, branch `foreign-thread-actor-bridge` (based on `main`). All paths below are relative to the worktree root.
- NOTE: cited line numbers were taken from an older tree and have drifted (e.g. `march_sched_wake`'s foreign push is at ~`march_scheduler.c:867-871` on this branch, `march_actor_call` at ~`march_runtime.c:1809`). Locate code by the quoted symbols/snippets, not line numbers. All anchors (`g_ext_spawn_head`, `last_yielded`, owner-only deque comments, `"not in scheduler context"`, `"timeout not yet enforced"`) are verified present on this branch.
- macOS + Linux portability: any new libc usage must follow the existing guard pattern (`#if defined(__APPLE__)` / `#if defined(__linux__)`; see top of `march_scheduler.c`).
- No new external dependencies; C11 `<stdatomic.h>` + `<pthread.h>` only.
- The full suite must stay green: `dune runtest` (compiler 321 / eval 224 / stdlib 786 counts per `specs/todos.md` — exact counts may have moved; the bar is "no new failures").
- Chase-Lev deque discipline: `march_deque_push`/`march_deque_pop` are OWNER-ONLY (`runtime/march_deque.h:31,43`); `march_deque_steal` is the only cross-thread op. No change may violate this.
- Green threads must never block an OS scheduler thread (no mutex/condvar waits on the scheduler path — park/yield only). Foreign threads must never busy-spin unboundedly.
- Values crossing thread boundaries need atomic refcounts — evloop threads already force atomic-local RC (see `march_http_evloop.c:508` and the RRB.Vec precedent in `specs/todos.md`). Any new cross-thread value handoff must not introduce non-atomic RC traffic.

---

### Task 1: Reproduce the hang and confirm the root cause

**Files:**
- Create: `test/native/foreign_actor_http.march`
- Create: `test/native/foreign_actor_http.expected`
- (temporary, reverted in this task): diagnostic logging in `runtime/march_scheduler.c`

**Interfaces:**
- Produces: the repro program used (as-is) by Task 6's dune wiring. Its client mode prints exactly two lines: `task_ok=50/50` and `direct_ok=50/50`.
- Produces: a written diagnosis section appended to this plan file (below this task) stating the confirmed failure mode.

**Background for the implementer:** HTTP handlers run on raw pthreads created by `http_server_listen` (`runtime/march_http_evloop.c:502` `evloop_run`; handler invoked at line 348 `fn(pipeline, conn)`). These threads have `tl_sched == NULL`. depot's Pool wraps `actor_call` in a task (`~/code/depot/lib/wire/pool.march:229-244`): `task_spawn(fn _ -> actor_call(pool, Checkout(0), 5000)) |> task_await_unwrap`. The repro does the same shape against a Counter actor, plus a direct `Actor.call` endpoint (which today returns `Err("actor_call: not in scheduler context")` — `march_runtime.c:1816`).

- [ ] **Step 1: Write the repro program**

`test/native/foreign_actor_http.march`:

```march
mod ForeignActorHttp do
  -- Zero-arg sentinel for Actor.call; tag 0 dispatches to the FIRST handler.
  type CallGet = CallGet

  actor Counter do
    state { value : Int }
    init { value: 0 }
    -- tag 0: actor_call target. Runtime injects the caller proc as `ref`.
    on GetValue(ref) do
      Actor.reply(ref, state.value)
      state
    end
    -- tag 1: fire-and-forget increment.
    on Increment(n : Int) do
      { state with value: state.value + n }
    end
  end

  -- depot-Pool-style shim: run actor_call on a fresh green thread; the
  -- caller (an HTTP evloop pthread) only touches task_spawn/task_await.
  fn call_via_task(c) : Int do
    let t = task_spawn(fn _ ->
      match Actor.call(c, CallGet, 5000) do
      Ok(v)  -> v
      Err(_) -> 0 - 1
      end)
    task_await_unwrap(t)
  end

  fn run_server() : Unit do
    let c = spawn(Counter)
    let _ = send(c, Increment(5))
    let handler = fn conn ->
      if HttpServer.path(conn) == "/direct" do
        -- direct Actor.call from the evloop pthread (Task 4's bridge)
        match Actor.call(c, CallGet, 5000) do
        Ok(v)  -> HttpServer.send_resp(conn, 200, "direct=" ++ int_to_string(v))
        Err(_) -> HttpServer.send_resp(conn, 500, "err")
        end
      else
        -- depot-style task shim from the evloop pthread (Tasks 2+3)
        HttpServer.send_resp(conn, 200, "task=" ++ int_to_string(call_via_task(c)))
      end
    HttpServer.new(29940)
    |> HttpServer.plug(handler)
    |> HttpServer.listen()
  end

  pfn get_loop(path : String, want : String, i : Int, n : Int, acc : Int) : Int do
    if i >= n do acc else
      let hit = match HttpTransport.simple_get("http://127.0.0.1:29940" ++ path) do
                Ok(Response(Status(code), _, body)) ->
                  if code == 200 && body == want do 1 else 0 end
                _ -> 0
                end
      get_loop(path, want, i + 1, n, acc + hit)
    end
  end

  fn run_client() : Unit do
    let n = 50
    println("task_ok="   ++ int_to_string(get_loop("/", "task=5", 0, n, 0))
            ++ "/" ++ int_to_string(n))
    println("direct_ok=" ++ int_to_string(get_loop("/direct", "direct=5", 0, n, 0))
            ++ "/" ++ int_to_string(n))
  end

  fn main() : Unit do
    if Env.get("FAH_MODE", "server") == "client" do
      run_client()
    else
      run_server()
    end
  end
end
```

Notes for the implementer:
- `Response`/`Status` are `HttpTransport`'s constructors (`stdlib/http_transport.march:96`). If the compiler requires qualification in patterns, write `HttpTransport.Response(HttpTransport.Status(code), _, body)`.
- `Env.get(name, default)` is `stdlib/env.march`.
- One-process-with-fork (`HttpServer.spawn_n`) is NOT usable here: the forked child loses the parent's scheduler threads, so the pre-spawned Counter actor would never run in the child and the test would hang for an unrelated reason. Two processes (server + client, same binary, `FAH_MODE` env switch) is the faithful forgepm shape.

`test/native/foreign_actor_http.expected`:

```
task_ok=50/50
direct_ok=50/50
```

- [ ] **Step 2: Compile and run it — verify it FAILS today**

```bash
cd /Users/80197052/code/march
dune build bin/main.exe
dune exec bin/main.exe -- --compile -o /tmp/fah test/native/foreign_actor_http.march
/tmp/fah & SRV=$!
sleep 1
FAH_MODE=client timeout 60 /tmp/fah
kill $SRV 2>/dev/null
```

Expected today: `task_ok` well below 50/50 — requests hang until `simple_get`'s recv fails, or the client stalls entirely (hence the `timeout 60`). `direct_ok=0/50` (every direct call returns the "not in scheduler context" error → 500). Record the exact observed output.

If the task-shim path unexpectedly passes 50/50: increase pressure (n=500, and run 4 client processes concurrently) — the deque race is probabilistic. Do not proceed to Step 3 until you have a reproducible failure or have exhausted the pressure options (in which case: still proceed, but note that the race did not reproduce on this machine/OS and the fix is justified by code inspection alone).

- [ ] **Step 3: Confirm the root cause with targeted diagnostics**

Hypothesis: `march_sched_wake` (`runtime/march_scheduler.c:755-759`) does `march_deque_push(&g_scheds[0].local_queue, target)` from a foreign thread. `march_deque_push` is owner-only (`runtime/march_deque.h:31` — non-atomic RMW on `bottom` races with the owner's push/pop). Lost wakeup → the green thread parked in `march_sched_recv` never resumes → `task_await` spins forever on the evloop thread.

Add temporary logging to the foreign branch of `march_sched_wake`:

```c
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, target);
    } else {
        fprintf(stderr, "[diag] foreign wake pid=%lld -> g_scheds[0] deque\n",
                (long long)target->pid);
        march_deque_push(&g_scheds[0].local_queue, target);
    }
```

Rebuild, re-run Step 2. Confirm (a) foreign wakes DO occur during the task-shim path (the evloop thread's `march_sched_send` → wake when delivering to the pool/counter actor, and the actor's reply-send back), and (b) hangs correlate with them. If the diagnostics point somewhere else entirely (e.g. `march_ensure_sched_started` never fires, or the wake CAS never reaches the push), follow the evidence — update the fix tasks before executing them, and record what you found.

- [ ] **Step 4: Revert the diagnostics, commit the repro**

```bash
cd /Users/80197052/code/march
git checkout runtime/march_scheduler.c
git add test/native/foreign_actor_http.march test/native/foreign_actor_http.expected
git commit -m "test(native): repro for foreign-thread actor ops hanging from HTTP evloop threads

Not yet wired into dune runtest (fails until the foreign-thread bridge
lands). Documents the depot-Pool task-shim shape and direct Actor.call
from handler pthreads."
```

- [ ] **Step 5: Append a diagnosis note to this plan**

Below this task, add `#### Diagnosis findings (Task 1)` with: observed failure output, whether the deque-race hypothesis was confirmed, and anything that changes later tasks. Commit with `docs(plan): record foreign-thread actor diagnosis`.

---

### Task 2: Route foreign wakes through the external ready stack

**Files:**
- Modify: `runtime/march_scheduler.c:76-79` (comment), `:494-509` (drain), `:732-760` (`march_sched_wake`)
- Test: `test/native/foreign_actor_http.march` (from Task 1, run manually)

**Interfaces:**
- Consumes: `g_ext_spawn_head` lock-free stack and its `march_proc::next` intrusive link (`march_scheduler.c:76-79`); the spawn-side push pattern (`march_scheduler.c:428-436`).
- Produces: `static march_proc *try_claim_external(void)` — claims one externally-enqueued proc (spawned OR woken), called every `sched_loop` iteration. Foreign `march_sched_wake` never touches a deque.

- [ ] **Step 1: Verify `march_proc::next` is free for parked procs**

Read the `march_proc` struct in `runtime/march_scheduler.h` and every use of `->next` in `march_scheduler.c`. Confirm `next` is only used as the external-stack link (procs in deques are stored by pointer in the ring array, not intrusively; mailboxes use their own node type). If `next` has another live use for WAITING procs, add a dedicated `ext_next` field instead and use it in both the spawn path and the new wake path.

- [ ] **Step 2: Extract the drain helper and call it every iteration**

In `march_scheduler.c`, above `sched_loop`, add:

```c
/* Claim one proc pushed by a non-scheduler thread (foreign spawn OR foreign
 * wake).  Chase-Lev deques are owner-push-only, so foreign threads enqueue
 * here and scheduler threads claim from it.  Checked every loop iteration
 * (one acquire load when empty) so foreign work is not starved while local
 * deques stay busy. */
static march_proc *try_claim_external(void) {
    march_proc *ext = atomic_load_explicit(&g_ext_spawn_head, memory_order_acquire);
    while (ext) {
        march_proc *nxt = ext->next;
        if (atomic_compare_exchange_weak_explicit(
                &g_ext_spawn_head, &ext, nxt,
                memory_order_acq_rel, memory_order_acquire)) {
            return ext;  /* claimed */
        }
        /* CAS failed; ext was refreshed by the failed CAS — retry. */
    }
    return NULL;
}
```

In `sched_loop`, change the top of the while body so the external stack is checked FIRST, and delete the old idle-only drain block (lines 494-509):

```c
    while (!atomic_load_explicit(&g_all_done, memory_order_acquire)) {
        /* Foreign spawns/wakes first: they have no other path onto a
         * scheduler, and under load the idle-only check starved them. */
        march_proc *p = try_claim_external();

        if (!p) {
            if (g_num_scheds <= 1) {
                p = (march_proc *)march_deque_steal(&sched->local_queue);
            } else if (last_yielded) {
                /* ... existing steal-first-else-pop block, unchanged ... */
            } else {
                p = (march_proc *)march_deque_pop(&sched->local_queue);
            }
        }
        last_yielded = 0;

        /* Try to steal from another scheduler if local deque is empty. */
        if (!p && g_num_scheds > 1) {
            /* ... existing steal loop, unchanged ... */
        }

        if (!p) {
            /* existing g_live_procs/g_sched_shutdown check + 1ms idle sleep,
               with the old inline external-stack drain REMOVED (it is now
               try_claim_external at the top) */
        }
        /* ... rest unchanged ... */
```

Keep the existing declaration `march_proc *p;` from being doubly declared — fold into the new structure.

- [ ] **Step 3: Fix `march_sched_wake`'s foreign branch**

Replace `march_scheduler.c:755-759`:

```c
    if (tl_sched) {
        march_deque_push(&tl_sched->local_queue, target);
    } else {
        /* Foreign thread (evloop pthread, FFI thread, main before scheduler):
         * deques are owner-push-only, so push onto the external ready stack.
         * Same protocol as the foreign-spawn path above. */
        march_proc *old_head;
        do {
            old_head = atomic_load_explicit(&g_ext_spawn_head, memory_order_relaxed);
            target->next = old_head;
        } while (!atomic_compare_exchange_weak_explicit(
                     &g_ext_spawn_head, &old_head, target,
                     memory_order_release, memory_order_relaxed));
    }
```

Also update the comment at `march_scheduler.c:76-78` to say the stack carries foreign spawns AND foreign wakes.

- [ ] **Step 4: Run the repro — task-shim path passes**

```bash
cd /Users/80197052/code/march
dune build bin/main.exe
dune exec bin/main.exe -- --compile -o /tmp/fah test/native/foreign_actor_http.march
/tmp/fah & SRV=$!; sleep 1
FAH_MODE=client timeout 60 /tmp/fah
kill $SRV 2>/dev/null
```

Expected: `task_ok=50/50`. (`direct_ok=0/50` still — that's Task 4.) Re-run the client 3 times against a fresh server to shake out flakes.

- [ ] **Step 5: Run the full suite**

```bash
dune runtest 2>&1 | tail -20
```

Expected: no new failures (the scheduler change affects every actor test — `sched_stress`, `node_*` loopback tests, etc.).

- [ ] **Step 6: Commit**

```bash
git add runtime/march_scheduler.c
git commit -m "fix(scheduler): route foreign-thread wakes through the external ready stack

march_sched_wake pushed into g_scheds[0]'s Chase-Lev deque from
non-owner threads — a data race with the owner's push/pop that lost
wakeups, leaving green threads parked forever (observed as HTTP
handlers hanging on depot Pool checkouts -> 503). Foreign wakes now
use the same lock-free stack as foreign spawns, and sched_loop claims
from that stack every iteration instead of only when idle."
```

---

### Task 3: Condvar wait for foreign `task_await`

**Files:**
- Modify: `runtime/march_runtime.c:1620-1645` (`march_task_await`, `march_task_await_value`) and the trampoline that release-stores the done flag (`march_thunk_trampoline`, near `march_task_spawn_thunk` at `:1583`)
- Test: `test/native/foreign_actor_http.march` (manual run) + CPU observation

**Interfaces:**
- Consumes: task object layout — `task[3]` tagged result, `task[4]` done flag (`march_runtime.c:1531,1606-1608`); `march_sched_in_scheduler()` (`march_scheduler.h:145`).
- Produces: `static void task_wait_done(int64_t *task)` used by both await functions; a global `g_task_done_mu`/`g_task_done_cv` pair broadcast by the trampoline.

- [ ] **Step 1: Add the condvar pair and the wait helper**

In `march_runtime.c` near the task functions:

```c
/* Foreign-thread task_await support: green threads yield-wait (they must
 * never block an OS scheduler thread), but foreign threads (evloop pthreads)
 * previously busy-spun with sched_yield, burning a core per in-flight
 * request.  A single global condvar is broadcast on every task completion;
 * foreign waiters do a timed wait and re-check their own done flag, so a
 * broadcast that fires before a waiter registers is harmless (50ms bound). */
static pthread_mutex_t g_task_done_mu = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t  g_task_done_cv = PTHREAD_COND_INITIALIZER;

static void task_wait_done(int64_t *task) {
    if (march_sched_in_scheduler()) {
        while (atomic_load_explicit((_Atomic int64_t *)&task[4],
                                    memory_order_acquire) == 0) {
            march_sched_yield();
        }
        return;
    }
    pthread_mutex_lock(&g_task_done_mu);
    while (atomic_load_explicit((_Atomic int64_t *)&task[4],
                                memory_order_acquire) == 0) {
        struct timespec ts;
        clock_gettime(CLOCK_REALTIME, &ts);          /* cond waits use REALTIME */
        ts.tv_nsec += 50 * 1000000L;                  /* 50ms re-check bound */
        if (ts.tv_nsec >= 1000000000L) { ts.tv_sec += 1; ts.tv_nsec -= 1000000000L; }
        pthread_cond_timedwait(&g_task_done_cv, &g_task_done_mu, &ts);
    }
    pthread_mutex_unlock(&g_task_done_mu);
}
```

- [ ] **Step 2: Use it in both awaits; broadcast in the trampoline**

`march_task_await` body (`:1620`) becomes:

```c
void *march_task_await(void *task_obj) {
    if (!task_obj) return mk_err_cstr("task_await: null task");
    int64_t *task = (int64_t *)task_obj;
    task_wait_done(task);
    void *result = (void *)(uintptr_t)task[3];
    return mk_ok(result);
}
```

`march_task_await_value` (`:1637`) likewise: replace its spin loop with `task_wait_done(task);`.

In `march_thunk_trampoline`, immediately AFTER the existing release-store of `done=1` into `task[4]` (and after the existing `march_decrc(task)` ordering — read the current code and keep its RC sequence intact; the broadcast needs no task access):

```c
    pthread_mutex_lock(&g_task_done_mu);
    pthread_cond_broadcast(&g_task_done_cv);
    pthread_mutex_unlock(&g_task_done_mu);
```

Apply the same broadcast to the cancel-token trampoline if it has its own done-store path (check `march_task_spawn_with_cancel_thunk`'s trampoline).

- [ ] **Step 3: Verify behavior + CPU**

Repro run as in Task 2 Step 4 → still `task_ok=50/50`. While the server sits idle after the run, `top -pid $SRV` (macOS) should show ~0% CPU for the server process (previously an in-flight await burned a full core; idle it was already fine — the observable win is during a slow in-handler await; optionally add a temporary handler `sleep`-style job to observe, then discard).

```bash
dune runtest 2>&1 | tail -20
```

Expected: no new failures.

- [ ] **Step 4: Commit**

```bash
git add runtime/march_runtime.c
git commit -m "perf(runtime): condvar wait for task_await from foreign threads

Foreign (non-scheduler) threads busy-spun on the task done flag with
sched_yield — one full core per in-flight await on an evloop thread.
Task completion now broadcasts a global condvar; foreign waiters do a
50ms-bounded timed wait re-checking the done flag. Green-thread path
unchanged (yield-wait; scheduler threads must never block)."
```

---

### Task 4: Foreign-thread `actor_call` bridge with timeout

**Files:**
- Modify: `runtime/march_runtime.c:1798-1838` (`march_actor_call`)
- Test: `test/native/foreign_actor_http.march` `/direct` endpoint (manual run)

**Interfaces:**
- Consumes: `march_ensure_sched_started()` (`march_runtime.c:1216`, same file — static is fine), `march_sched_spawn` (`march_scheduler.h:125`), the call protocol (augmented msg: tag + caller proc in field 0; reply via `march_actor_reply` → caller mailbox).
- Produces: `march_actor_call` works from any thread. Green-thread path refactored into `static void *actor_call_green(void *actor, march_actor_meta *meta, int32_t msg_tag, int64_t timeout_ms)` (Task 5 adds the timeout logic inside it; in this task it ignores `timeout_ms`, preserving current behavior).

- [ ] **Step 1: Refactor the green path out of `march_actor_call`**

```c
/* Perform the call protocol from the current green thread.
 * Precondition: march_sched_current() != NULL.  timeout_ms handled in
 * Task 5; <=0 means wait forever. */
static void *actor_call_green(void *actor, march_actor_meta *meta,
                              int32_t msg_tag, int64_t timeout_ms) {
    (void)actor; (void)timeout_ms;
    march_proc *caller = march_sched_current();

    void *call_msg = march_alloc(24);
    MARCH_SET_TAG(call_msg, msg_tag);
    MARCH_FIELD(call_msg, 0) = (int64_t)(uintptr_t)caller;

    march_sched_send(meta->green_thread, call_msg);

    void *result = march_sched_recv();
    if (result == MARCH_RECV_NO_MSG) return mk_err_cstr("actor_call: no reply");
    return mk_ok(result);
}
```

`march_actor_call` keeps: liveness check (`a[3]`), meta lookup, tag read + `march_decrc(inner_msg)` — then branches on `march_sched_current()`.

- [ ] **Step 2: Add the foreign bridge**

```c
/* Foreign-caller bridge: the calling OS thread has no green-thread context,
 * so a helper green thread performs the call protocol and hands the result
 * back over a one-shot condvar.  The waiter enforces timeout_ms with
 * pthread_cond_timedwait; on timeout it marks the ctx abandoned and the
 * helper green thread frees it (and drops the unclaimed result) instead. */
typedef struct {
    void             *actor;
    march_actor_meta *meta;
    int32_t           msg_tag;
    int64_t           timeout_ms;
    void             *result;
    int               done;
    int               abandoned;
    pthread_mutex_t   mu;
    pthread_cond_t    cv;
} foreign_call_ctx;

static void foreign_call_entry(void *arg) {
    foreign_call_ctx *ctx = (foreign_call_ctx *)arg;
    /* Pass the same bound the waiter uses so a never-replying actor cannot
     * leak this green thread: once Task 5 lands, actor_call_green returns
     * Err(timeout) here, we see abandoned=1, and we free ctx.  (Until Task 5,
     * timeout_ms is ignored on the green path — transitional, bounded by
     * this plan's task ordering.) */
    void *res = actor_call_green(ctx->actor, ctx->meta, ctx->msg_tag,
                                 ctx->timeout_ms);
    pthread_mutex_lock(&ctx->mu);
    if (ctx->abandoned) {
        pthread_mutex_unlock(&ctx->mu);
        march_decrc(res);  /* unclaimed Ok/Err — drop our reference */
        pthread_mutex_destroy(&ctx->mu);
        pthread_cond_destroy(&ctx->cv);
        free(ctx);
        return;
    }
    ctx->result = res;
    ctx->done   = 1;
    pthread_cond_signal(&ctx->cv);
    pthread_mutex_unlock(&ctx->mu);
}
```

In `march_actor_call`, replace the `if (!caller) { ... return mk_err_cstr("actor_call: not in scheduler context"); }` block (`:1813-1817`) with:

```c
    if (!march_sched_current()) {
        foreign_call_ctx *ctx = (foreign_call_ctx *)calloc(1, sizeof(*ctx));
        if (!ctx) return mk_err_cstr("actor_call: oom");
        ctx->actor = actor; ctx->meta = meta; ctx->msg_tag = msg_tag;
        ctx->timeout_ms = timeout_ms > 0 ? timeout_ms : 5000;
        pthread_mutex_init(&ctx->mu, NULL);
        pthread_cond_init(&ctx->cv, NULL);

        march_ensure_sched_started();
        march_sched_spawn(foreign_call_entry, ctx);

        int64_t wait_ms = timeout_ms > 0 ? timeout_ms : 5000;
        struct timespec deadline;
        clock_gettime(CLOCK_REALTIME, &deadline);
        deadline.tv_sec  += wait_ms / 1000;
        deadline.tv_nsec += (wait_ms % 1000) * 1000000L;
        if (deadline.tv_nsec >= 1000000000L) { deadline.tv_sec += 1; deadline.tv_nsec -= 1000000000L; }

        pthread_mutex_lock(&ctx->mu);
        int timed_out = 0;
        while (!ctx->done && !timed_out) {
            if (pthread_cond_timedwait(&ctx->cv, &ctx->mu, &deadline) == ETIMEDOUT)
                timed_out = !ctx->done;
        }
        if (timed_out) {
            ctx->abandoned = 1;   /* helper green thread now owns ctx */
            pthread_mutex_unlock(&ctx->mu);
            return mk_err_cstr("actor_call: timeout");
        }
        void *r = ctx->result;
        pthread_mutex_unlock(&ctx->mu);
        pthread_mutex_destroy(&ctx->mu);
        pthread_cond_destroy(&ctx->cv);
        free(ctx);
        return r;
    }
    return actor_call_green(actor, meta, msg_tag, timeout_ms);
```

Add `#include <errno.h>` if not already present (for `ETIMEDOUT`). Note the tag-read/decrc of `inner_msg` must happen BEFORE this branch (both paths need `msg_tag`; the current code already reads it before building the message — keep that ordering).

- [ ] **Step 3: Run the repro — direct path passes**

As Task 2 Step 4. Expected: `task_ok=50/50` AND `direct_ok=50/50`.

- [ ] **Step 4: Full suite**

```bash
dune runtest 2>&1 | tail -20
```

Expected: no new failures (`actor_counter` exercises the green path through the refactor).

- [ ] **Step 5: Commit**

```bash
git add runtime/march_runtime.c
git commit -m "feat(runtime): actor_call from foreign threads via green-thread bridge

Actor.call from a non-scheduler thread (HTTP evloop pthread) previously
returned Err(\"not in scheduler context\"). A helper green thread now
performs the call protocol and hands the result back over a one-shot
condvar; the foreign waiter enforces timeout_ms via
pthread_cond_timedwait (default 5000ms when <=0). On timeout the ctx is
abandoned to the helper for cleanup — no use-after-free on late replies."
```

---

### Task 5: Enforce `actor_call` timeout on the green-thread path

**Files:**
- Modify: `runtime/march_scheduler.c` + `runtime/march_scheduler.h` (add `march_sched_try_recv2`)
- Modify: `runtime/march_runtime.c` (`actor_call_green`)
- Create: `test/native/actor_call_timeout.march`, `test/native/actor_call_timeout.expected`

**Interfaces:**
- Consumes: `actor_call_green(actor, meta, msg_tag, timeout_ms)` from Task 4; mailbox internals (`mbox_lock_acquire`/`mbox_pop`, `march_scheduler.c:689-729`).
- Produces: `int march_sched_try_recv2(void **out)` — returns 1 and writes the message to `*out` if the mailbox has a node, else returns 0. (The existing `march_sched_try_recv` cannot distinguish "empty" from a legitimate NULL message — zero-arg constructors are `msg=NULL`, see `march_scheduler.c:684-686`.)

**Known limitation to document in the commit:** on timeout, a late reply still lands in the caller's mailbox. For the depot/conduit pattern (a fresh task green thread per call) this is safe — the thread exits and sends to dead procs are dropped. A long-lived green thread mixing `Actor.call` and raw `receive` could observe a stale reply after a timeout. Documented, not fixed here.

- [ ] **Step 1: Write the failing test**

`test/native/actor_call_timeout.march`:

```march
mod ActorCallTimeout do
  type CallGet = CallGet

  actor Silent do
    state { value : Int }
    init { value: 0 }
    -- tag 0: receives the call but never replies.
    on GetValue(_ref) do
      state
    end
  end

  fn main() : Unit do
    let c = spawn(Silent)
    match Actor.call(c, CallGet, 300) do
    Ok(_)  -> println("fail:expected_timeout")
    Err(_) -> println("timeout_ok")
    end
    kill(c)
  end
end
```

`test/native/actor_call_timeout.expected`:

```
timeout_ok
```

- [ ] **Step 2: Run to verify it fails (hangs) today**

```bash
dune exec bin/main.exe -- --compile -o /tmp/act test/native/actor_call_timeout.march
timeout 10 /tmp/act; echo "exit=$?"
```

Expected today: no output, `exit=124` (killed by timeout) — the compiled runtime ignores `timeout_ms` (`march_runtime.c:1799`, documented divergence in `specs/lang/actors.md:19`).

- [ ] **Step 3: Add `march_sched_try_recv2`**

`runtime/march_scheduler.h`, next to `march_sched_try_recv` (`:175`):

```c
/* Non-blocking receive that distinguishes "empty mailbox" from a legitimate
 * NULL message (zero-arg constructors are msg=NULL).  Returns 1 and writes
 * the message to *out if a mailbox node existed, else returns 0. */
int march_sched_try_recv2(void **out);
```

`runtime/march_scheduler.c`, after `march_sched_try_recv`:

```c
int march_sched_try_recv2(void **out) {
    march_proc *p = tl_sched ? tl_sched->current : NULL;
    if (!p) return 0;
    mbox_lock_acquire(p);
    if (!p->mailbox) {          /* node existence, not message value */
        mbox_lock_release(p);
        return 0;
    }
    *out = mbox_pop(p);
    mbox_lock_release(p);
    return 1;
}
```

(Match the actual mailbox field/lock names against `march_sched_recv` at `:680-721` — use exactly what that function uses.)

- [ ] **Step 4: Implement the deadline loop in `actor_call_green`**

Replace the tail of `actor_call_green` (send + blocking recv) with:

```c
    march_sched_send(meta->green_thread, call_msg);

    if (timeout_ms <= 0) {
        /* Preserve wait-forever semantics for callers that opt out. */
        void *result = march_sched_recv();
        if (result == MARCH_RECV_NO_MSG) return mk_err_cstr("actor_call: no reply");
        return mk_ok(result);
    }

    /* Timed wait: poll the mailbox with cooperative yields until the
     * deadline.  A parked-with-deadline mechanism needs timer support the
     * scheduler doesn't have; replies are normally immediate, so the yield
     * loop only spins for the (rare) slow-actor case, bounded by timeout_ms. */
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t deadline_ms = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000
                          + timeout_ms;
    for (;;) {
        void *msg = NULL;
        if (march_sched_try_recv2(&msg)) {
            if (msg == MARCH_RECV_NO_MSG) return mk_err_cstr("actor_call: no reply");
            return mk_ok(msg);
        }
        clock_gettime(CLOCK_MONOTONIC, &ts);
        int64_t now_ms = (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
        if (now_ms >= deadline_ms)
            return mk_err_cstr("actor_call: timeout");
        march_sched_yield();
    }
```

Also delete the now-stale `(void)timeout_ms;` from Task 4's version, and update the stale comment at `march_runtime.c:1799` ("timeout not yet enforced").

- [ ] **Step 5: Run the new test and the repro**

```bash
dune exec bin/main.exe -- --compile -o /tmp/act test/native/actor_call_timeout.march
timeout 10 /tmp/act
```

Expected: `timeout_ok` printed in ~300ms.

Re-run the Task 1 repro end-to-end (both endpoints 50/50 — replies are immediate there, so the poll loop exits on first or second iteration).

- [ ] **Step 6: Full suite + update the divergence doc**

```bash
dune runtest 2>&1 | tail -20
```

Expected: no new failures. Then update `specs/lang/actors.md` line ~19: the `Actor.call` timeout IS now enforced in the compiled runtime (yield-poll; stale-reply caveat for long-lived callers mixing call and receive).

- [ ] **Step 7: Commit**

```bash
git add runtime/march_scheduler.c runtime/march_scheduler.h runtime/march_runtime.c \
        test/native/actor_call_timeout.march test/native/actor_call_timeout.expected \
        specs/lang/actors.md
git commit -m "feat(runtime): enforce Actor.call timeout in the compiled runtime

timeout_ms was accepted but ignored (documented divergence). The green
path now does a deadline-bounded yield-poll via new march_sched_try_recv2
(which, unlike try_recv, distinguishes an empty mailbox from a legitimate
NULL message). timeout_ms <= 0 preserves wait-forever. Known limitation:
a late reply after timeout still lands in the caller's mailbox — safe for
per-call task green threads (depot Pool), documented for long-lived ones."
```

---

### Task 6: Wire the e2e test into dune, record follow-ons

**Files:**
- Modify: `test/dune` (new rules; mirror the `node_call_loopback` shape at `test/dune:1686-1716`)
- Modify: `test/native/actor_call_timeout` dune rules (same shape)
- Create: `specs/2026-07-09-http-handlers-as-green-threads.md` (B1 follow-on note)
- Modify: `specs/todos.md` (entry for this work)

**Interfaces:**
- Consumes: `test/native/foreign_actor_http.march` + `.expected` (Task 1), `test/native/actor_call_timeout.march` + `.expected` (Task 5).

- [ ] **Step 1: Add dune rules**

Append to `test/dune`, mirroring `node_call_loopback`'s dep list exactly (copy its `(deps ...)` block, adjusting only the `.march` file), plus `../stdlib/http_server.march`, `../stdlib/http_transport.march`, `../stdlib/http.march`, `../stdlib/env.march`, `../stdlib/socket.march`, and `../runtime/march_http_evloop.c`:

```lisp
; ── Foreign-thread actor bridge: HTTP evloop pthread drives actor ops ──
(rule
 (targets native_foreign_actor_http native_foreign_actor_http.out)
 (deps (file %{exe:../bin/main.exe})
       ; ... copy node_call_loopback's runtime deps, plus the files above ...
       (file native/foreign_actor_http.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_foreign_actor_http
        native/foreign_actor_http.march)
   (with-stdout-to native_foreign_actor_http.out
        (system "./native_foreign_actor_http & SRV=$!; sleep 1; FAH_MODE=client ./native_foreign_actor_http; kill $SRV 2>/dev/null; true")))))

(rule
 (alias runtest)
 (action (diff native/foreign_actor_http.expected native_foreign_actor_http.out)))

; ── Actor.call timeout enforcement (compiled runtime) ──
(rule
 (targets native_actor_call_timeout native_actor_call_timeout.out)
 (deps (file %{exe:../bin/main.exe})
       ; ... same runtime deps ...
       (file native/actor_call_timeout.march))
 (action
  (progn
   (run %{exe:../bin/main.exe} --compile -o native_actor_call_timeout
        native/actor_call_timeout.march)
   (with-stdout-to native_actor_call_timeout.out
        (system "./native_actor_call_timeout")))))

(rule
 (alias runtest)
 (action (diff native/actor_call_timeout.expected native_actor_call_timeout.out)))
```

- [ ] **Step 2: Run the suite twice (flake check)**

```bash
dune runtest 2>&1 | tail -5
dune runtest --force 2>&1 | tail -5
```

Expected: green both times. If the HTTP test flakes on port 29940 collisions or the 1s startup sleep, bump the sleep to 2 and/or pick a quieter port — then re-run twice more.

- [ ] **Step 3: Write the B1 follow-on note**

`specs/2026-07-09-http-handlers-as-green-threads.md`:

```markdown
# Follow-on: HTTP handlers as green threads (B1)

**Status:** filed, not started. Prereq work (foreign-thread actor bridge)
landed 2026-07 — see specs/plans/2026-07-09-foreign-thread-actor-bridge.md.

Today `march_http_evloop.c` calls the March pipeline inline on evloop
pthreads (evloop_run -> fn(pipeline, conn)); the bridge makes actor ops
*work* from there, but handlers still aren't actors (no receive), a slow
handler blocks an entire evloop thread, and an actor_call blocks the
evloop thread for its duration.

B1 (the BEAM architecture, steps 1-3): at the dispatch point, spawn a
green thread per request instead of calling inline; completion signals
the evloop (eventfd/pipe) which serializes and writes the response.
Evloop threads stop running March code entirely (drop the atomic-RC
forcing). Handlers become full actor citizens. Hard parts: per-request
pending state, out-of-order completion within pipelined keep-alive
batches, backpressure, preserving the iovec-batching fast path.
Full BEAM parity (B2) additionally parks green threads on socket
readiness via a poll set — separable, not needed for conduit.

Driver: forgepm conduit integration (forgepm specs/conduit-background-jobs.md)
runs on the bridge alone; B1 is wanted for slow-handler isolation and
retiring forgepm's direct-connection Repo workaround under load.
```

- [ ] **Step 4: Update `specs/todos.md`**

Add a ✅ entry (matching the file's style) summarizing: foreign-wake deque race fixed via external ready stack drained every iteration; condvar foreign task_await; foreign actor_call bridge with real timeout; compiled Actor.call timeout enforced (+ try_recv2); e2e HTTP-evloop actor test + timeout test in dune. Reference the B1 note.

- [ ] **Step 5: Commit**

```bash
git add test/dune specs/2026-07-09-http-handlers-as-green-threads.md specs/todos.md
git commit -m "test(native): wire foreign-thread actor bridge e2e + timeout tests into dune; file B1 follow-on"
```

---

## After this plan

Sub-project 2 (conduit integration in forgepm — see forgepm repo `specs/conduit-background-jobs.md`) gets its own implementation plan once this one is verified: depot Pool checkouts from forgepm HTTP handlers should now succeed, which is the acceptance gate. Quick smoke: temporarily point one forgepm read path at depot's Pool instead of `Forgepm.Repo.with_conn` and hit it over HTTP.
