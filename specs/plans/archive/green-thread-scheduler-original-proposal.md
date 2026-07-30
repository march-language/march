# Green Thread Scheduler — Comprehensive Implementation Plan

**Date:** March 24, 2026
**Status:** Proposal
**Goal:** Replace March's current pthread-based actor runtime with a BEAM-class green thread scheduler capable of sustaining 1M+ concurrent connections and competing at the top of TechEmpower Framework Benchmarks.

---

## Table of Contents

1. [Motivation and Current State](#1-motivation-and-current-state)
2. [BEAM Reference Architecture](#2-beam-reference-architecture)
3. [Part 1: Green Thread Runtime](#3-part-1-green-thread-runtime)
4. [Part 2: HTTP Server Optimizations for TechEmpower](#4-part-2-http-server-optimizations-for-techempower)
5. [Part 3: Implementation Phases](#5-part-3-implementation-phases)
6. [Appendix: Key Numbers and Targets](#6-appendix-key-numbers-and-targets)

---

## 1. Motivation and Current State

### What We Have Today

The March runtime (`runtime/march_runtime.c`, ~880 lines) implements actors on top of pthreads with these characteristics:

- **Global run queue** protected by `g_run_mu` mutex — all scheduler threads contend on a single lock.
- **Fixed 4-thread worker pool** (`MARCH_NUM_WORKERS = 4`) dequeuing actors from the global queue.
- **MPSC Treiber stack mailboxes** — lock-free enqueue, but the scheduler reverses the stack under a per-actor `scheduled` CAS, dispatching up to `MARCH_BATCH_MAX = 64` messages per turn with a 5ms wall-clock quantum (`MARCH_TIME_QUANTUM_NS`).
- **No I/O integration** — the scheduler has no concept of file descriptors, polling, or sleeping on I/O. The HTTP server (`march_http.c`) uses a separate thread pool with a ring-buffer work queue (`MARCH_HTTP_QUEUE_CAPACITY = 4096`), running one connection per pool worker thread (blocking `recv`/`send`).
- **Atomic reference counting** (Perceus) with no per-process heaps — every `march_incrc`/`march_decrc` is a global atomic operation.
- **No reduction counting in compiled code** — the OCaml scheduler module has reduction budgets (`max_reductions = 4000`), but this is not wired into the LLVM-compiled path.

### Why This Must Change

The current design cannot scale beyond ~4096 concurrent connections (bounded by the HTTP ring buffer and blocking I/O model). A single global run queue becomes a bottleneck at scale. Atomic RC on a shared heap means every message send and every allocation contends on cache lines across cores.

To hit 1M concurrent connections and competitive TechEmpower scores, we need:

1. Per-core scheduler threads with per-core run queues (eliminate global lock contention).
2. Kernel I/O integration (epoll/kqueue) so processes sleep on file descriptors instead of blocking OS threads.
3. Lightweight process representation (~2–4 KB per process, not one pthread per connection).
4. Reduction counting in LLVM-compiled code for preemptive fairness.
5. Process-local reference counting (no atomics for process-local data).

---

## 2. BEAM Reference Architecture

This section summarizes the BEAM design we're drawing from, with the specific numbers that inform our targets.

### 2.1 Process Model

BEAM processes are ~2.5 KB at minimum: a 300-byte Process Control Block (PCB) plus a 233-word (~1.9 KB) initial heap. Stack and heap live in the same contiguous allocation, growing toward each other. Each process has its own generational copying garbage collector — young heap and old heap, with a fullsweep threshold controlling promotion. This per-process GC is *the* key to BEAM's soft real-time guarantees: no global stop-the-world pause, only microsecond-scale per-process collections.

Spawn time is in the low microseconds. The practical limit is millions of concurrent processes, bounded only by RAM.

### 2.2 Scheduler Architecture

BEAM runs one scheduler thread per CPU core (plus dirty scheduler threads for blocking NIFs). Each scheduler owns a multi-level run queue with four priority levels: `max` (internal only), `high` (exclusive — blocks normal/low), `normal`, and `low` (interleaved with normal at reduced frequency).

Each process gets a **reduction budget of 4,000** (increased from 2,000 in OTP 20). One reduction ≈ one function call. After exhausting its budget, a process yields and is re-enqueued. This provides cooperative preemption at function-call granularity — the equivalent of a 1–2ms time slice in practice.

When a scheduler's run queue empties, it **steals work** from peer schedulers. A periodic migration/compaction algorithm (running every 2000 × `CONTEXT_REDS` reductions) rebalances load across schedulers, consolidating work onto fewer cores when load is light (to allow the OS to power-gate idle cores) and spreading when load is heavy.

### 2.3 I/O Model

BEAM integrates I/O polling directly into the scheduler loop. After each process turn, the scheduler calls `check_io` which polls epoll (Linux) or kqueue (macOS) for ready file descriptors. When a process calls `gen_tcp:recv`, it suspends (removed from the run queue) and registers interest in the socket's fd with the poller. When the fd becomes ready, the polling thread wakes the process by placing it back on the run queue. This means a process waiting on I/O consumes only its ~2.5 KB of memory — no OS thread is blocked.

The async thread pool (default 64 threads, configurable via `+A`) handles file I/O and other blocking operations that can't be polled.

### 2.4 Message Passing

Messages are **copied** from sender's heap to receiver's heap (or to an off-heap fragment in OTP 19+). This copy-on-send design means processes share nothing and can be GC'd independently. Off-heap message fragments avoid expanding the receiver's heap on every message arrival and reduce GC pressure for high-throughput mailboxes.

Selective receive uses a **save pointer** to avoid rescanning already-examined messages. Signal ordering is guaranteed per process pair: if A sends signals S1 then S2 to B, B sees S1 before S2.

### 2.5 TechEmpower Context

The top TechEmpower frameworks (Round 23, 2025) achieve:
- **Plaintext**: 7–12M req/s (pipelined, 16 depth) — dominated by Rust (ntex, actix), Go (Fiber), C++ (drogon), and JS (Just).
- **JSON**: 600K–1M+ req/s.
- **Database benchmarks**: Connection pooling, prepared statement caching, and query pipelining are essential.

Key techniques from the leaders: io_uring (10%+ throughput over epoll), thread-per-core architecture, SIMD HTTP parsing (picohttpparser uses SSE4.2/AVX2), arena allocators for per-request memory, zero-copy response building (writev/sendfile), and response precomputation.

BEAM/Elixir frameworks (Phoenix/Bandit) sit in the middle of the pack — strong concurrency (2M simultaneous connections) but lower raw req/s than Rust/C. March's advantage: we compile to native code via LLVM (no VM overhead), have Perceus RC (no GC pauses), and can adopt BEAM's scheduling model while retaining Rust-class throughput.

---

## 3. Part 1: Green Thread Runtime

### 3.1 Process Representation

#### Decision: Stackful Coroutines with Segmented Stacks

We use **stackful coroutines** (like BEAM, like Go goroutines) rather than stackless (like Rust async/await). Rationale:

- BEAM compatibility: actors can yield at any point (function call boundary), not just at explicit `.await` points.
- Simpler compiler integration: reduction checks are inserted at function calls; a yield suspends the entire call stack.
- Segmented/growable stacks avoid pre-allocating large stacks: start at 4 KB, grow in segments as needed.

Stackless coroutines (state machines) would give smaller per-process overhead but require transforming every function into a state machine at the compiler level — far more invasive to the compiler and incompatible with calling C FFI functions that expect a real stack.

#### Process Control Block (PCB)

```c
typedef struct march_process {
    /* Identity */
    uint64_t            pid;            // Unique process ID (monotonic counter)
    uint8_t             priority;       // 0=low, 1=normal, 2=high
    uint8_t             state;          // RUNNING, RUNNABLE, WAITING, DEAD
    uint16_t            flags;          // TRAP_EXIT, MONITOR_ACTIVE, etc.

    /* Scheduling */
    int32_t             reductions;     // Remaining reductions this quantum
    struct march_process *run_next;     // Intrusive run queue link

    /* Stack (segmented) */
    void               *stack_base;     // Current stack segment base
    void               *stack_ptr;      // Saved stack pointer (on yield)
    void               *stack_limit;    // End of current segment
    uint32_t            stack_size;     // Total stack bytes allocated

    /* Coroutine context */
    march_context_t     context;        // Platform-specific register save area
                                        // (rsp, rbp, rip, callee-saved regs)

    /* Mailbox */
    _Atomic(march_msg_node *) mbox_head; // MPSC Treiber stack (lock-free)
    march_msg_node     *mbox_local;     // Scheduler-local receive queue (FIFO)
    march_msg_node     *mbox_save;      // Selective receive save pointer
    uint32_t            mbox_len;       // Approximate message count

    /* I/O */
    int                 waiting_fd;     // fd this process is blocked on (-1 if none)
    uint32_t            io_events;      // EPOLLIN | EPOLLOUT mask

    /* Memory */
    march_heap_t       *heap;           // Per-process heap (see §3.4)

    /* Lifecycle */
    void               *result;         // Return value (for Task(a) await)
    struct march_process *link_head;    // Linked processes (for crash propagation)
    struct march_monitor_node *monitors;// Monitor list
} march_process;
```

**Target size**: ~192 bytes for the PCB + 4 KB initial stack = **~4.2 KB per process**. At 1M processes, that's ~4 GB of RAM — well within a server's capacity.

#### Context Switching

We implement `march_context_switch(from, to)` in assembly (x86-64 and aarch64):

```asm
; x86-64 context switch
; Save callee-saved registers + rsp to `from->context`
; Restore from `to->context`
; ret jumps to `to`'s saved rip
march_context_switch:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov  [rdi + CTX_RSP], rsp    ; save stack pointer
    mov  rsp, [rsi + CTX_RSP]    ; restore stack pointer
    pop  r15
    pop  r14
    pop  r13
    pop  r12
    pop  rbx
    pop  rbp
    ret
```

This is ~10ns per context switch (just register save/restore, no kernel transition). Comparable to BEAM's internal switch cost.

#### Stack Segments

Initial stack: **4 KB**. When a function prologue detects the stack pointer is within a guard zone (64 bytes from the segment limit), it calls `march_stack_grow()` which allocates a new segment (doubling: 4→8→16→32 KB, capped at 1 MB) and chains it to the previous segment. On function return, if the stack pointer crosses back into the previous segment, the current segment is freed.

For the LLVM-compiled path, stack probes are inserted as part of the function prologue (LLVM's `probe-stack` attribute handles this for segmented stacks).

### 3.2 Scheduler Design

#### M:N Threading Model

**N = number of CPU cores** (detected at startup via `sysconf(_SC_NPROCESSORS_ONLN)`). Each scheduler thread is pinned to a core via `pthread_setaffinity_np` (Linux) or equivalent.

**M = number of green threads** (processes). Millions of green threads multiplexed onto N OS threads.

#### Per-Scheduler Structure

```c
typedef struct march_scheduler {
    uint32_t            id;              // Scheduler index [0, N)
    pthread_t           os_thread;       // Underlying OS thread

    /* Run queues — one per priority level */
    march_runq_t        high_q;          // High-priority processes
    march_runq_t        normal_q;        // Normal-priority processes
    march_runq_t        low_q;           // Low-priority processes
    uint32_t            low_counter;     // Counts normal turns; run 1 low per 8 normal

    /* Work stealing */
    march_deque_t       steal_deque;     // Chase-Lev deque for stealable work
    uint64_t            steal_seed;      // PRNG seed for random victim selection

    /* I/O poller */
    int                 poll_fd;         // epoll_fd (Linux) or kqueue_fd (macOS)
    march_timer_wheel_t timers;          // Hierarchical timing wheel for timeouts

    /* Statistics */
    uint64_t            total_reductions;
    uint64_t            total_context_switches;
    uint64_t            total_messages_delivered;

    /* Current process */
    march_process      *current;         // Currently executing process (NULL if idle)
} march_scheduler;
```

#### Scheduler Main Loop

```
loop:
    1. Poll I/O (non-blocking): epoll_wait(poll_fd, events, max_events, timeout=0)
       — Wake any processes whose fds are ready, enqueue them.

    2. Check timers: advance timing wheel, fire expired timers
       — Enqueue timed-out processes (e.g., receive...after).

    3. Select next process:
       a. If high_q is non-empty → dequeue from high_q (exclusive priority)
       b. Else if normal_q is non-empty → dequeue from normal_q
          (every 8th turn, dequeue from low_q instead if non-empty)
       c. Else if low_q is non-empty → dequeue from low_q
       d. Else → try work stealing from random peer
       e. Else → blocking epoll_wait (sleep until I/O or new work)

    4. Run process:
       a. Set process.reductions = MARCH_REDUCTION_BUDGET (4000)
       b. Context switch to process
       c. Process runs until:
          — reductions hit 0 (preemption) → re-enqueue
          — process calls receive with no matching message → move to WAITING
          — process does I/O → register fd with poller, move to WAITING
          — process terminates → clean up, notify monitors/links

    5. Process any signals (monitor notifications, exit signals)

    6. Periodically (every MIGRATION_INTERVAL reductions):
       — Run load balancing / migration algorithm
```

#### Reduction Counting

**Budget**: 4,000 reductions per quantum (matching BEAM).

**What counts as a reduction**:
- Each function call/return: 1 reduction
- Each pattern match arm evaluated: 1 reduction
- Each message send: 1 reduction
- Each message receive (checking one message): 1 reduction
- Allocation of a heap object > 256 bytes: 1 reduction per 256 bytes

**Interpreter path** (OCaml evaluator): The existing `reduction_ctx` in `lib/scheduler/scheduler.ml` already tracks this. Wire `tick ctx` into the `eval` function at every `EApp`, `EMatch`, `ESend`, and `EReceive` node.

**Compiled path** (LLVM IR): The compiler (`lib/tir/llvm_emit.ml`) must insert reduction checks at function prologues:

```llvm
define void @user_function(%args...) {
entry:
    ; Load scheduler thread-local reduction counter
    %reds = load i32, i32* @march_tls_reductions
    %done = icmp sle i32 %reds, 0
    br i1 %done, label %yield, label %body

yield:
    call void @march_yield()  ; saves context, returns to scheduler
    br label %body

body:
    ; Decrement reduction counter
    %new_reds = sub i32 %reds, 1
    store i32 %new_reds, i32* @march_tls_reductions
    ; ... actual function body ...
}
```

The `@march_tls_reductions` is a thread-local variable (one per scheduler thread). `@march_yield()` performs the context switch back to the scheduler.

**Optimization**: For leaf functions (no calls, no allocation, known to terminate quickly), the reduction check can be omitted. The compiler can analyze this statically.

#### Work Stealing

When a scheduler's run queues are all empty:

1. Pick a random peer scheduler (using the `steal_seed` PRNG).
2. Try to steal from the peer's `steal_deque` (Chase-Lev algorithm — lock-free, the thief steals from the opposite end of the deque from the owner).
3. If the steal fails (empty or contention), try up to 2 more random peers.
4. If all steals fail, fall back to blocking `epoll_wait` — the scheduler sleeps until I/O wakes it or another scheduler enqueues work and signals the sleeping scheduler via an eventfd/pipe.

**Migration/compaction** (periodic, every ~8M total reductions across the system): Examine load across all schedulers. If load is concentrated, spread it. If load is sparse, compact onto fewer schedulers so the OS can idle unused cores.

#### Integration with OCaml 5 Effect Handlers

For the interpreter path, OCaml 5's algebraic effect handlers provide a natural mechanism for cooperative yielding:

```ocaml
effect Yield : unit

let run_process proc =
  match_with (fun () -> eval proc.code proc.env) ()
    { retc = (fun v -> proc.state <- Done v);
      exnc = (fun e -> proc.state <- Failed e);
      effc = (fun (type a) (eff : a Effect.t) ->
        match eff with
        | Yield -> Some (fun (k : (a, _) continuation) ->
            proc.continuation <- Some k;
            proc.state <- Runnable;
            enqueue proc)
        | _ -> None) }
```

This lets the interpreter yield at reduction boundaries without any manual CPS transformation.

### 3.3 I/O Integration

#### Per-Scheduler Event Loop

Each scheduler thread owns an epoll (Linux) or kqueue (macOS) instance:

```c
// At scheduler init:
sched->poll_fd = epoll_create1(EPOLL_CLOEXEC);  // Linux
// or: sched->poll_fd = kqueue();                // macOS
```

#### Process I/O Suspension

When a process calls a blocking I/O operation (e.g., `tcp_recv`):

```c
void march_io_wait(march_scheduler *sched, march_process *proc, int fd, uint32_t events) {
    proc->state = WAITING;
    proc->waiting_fd = fd;
    proc->io_events = events;

    struct epoll_event ev = {
        .events = events | EPOLLONESHOT,  // One-shot: must re-arm after wake
        .data.ptr = proc                   // Store process pointer for fast wakeup
    };
    epoll_ctl(sched->poll_fd, EPOLL_CTL_ADD, fd, &ev);

    // Context switch back to scheduler — process is now suspended
    march_yield();
}
```

#### I/O Wakeup

In the scheduler loop's poll phase:

```c
struct epoll_event events[256];
int n = epoll_wait(sched->poll_fd, events, 256, timeout);
for (int i = 0; i < n; i++) {
    march_process *proc = (march_process *)events[i].data.ptr;
    proc->state = RUNNABLE;
    proc->waiting_fd = -1;
    enqueue(sched, proc);  // Put back on this scheduler's run queue
}
```

#### Cross-Scheduler I/O

If a process migrated to a different scheduler than the one that registered its fd, we have two options:

1. **Option A (simpler)**: Always register fds with the process's current scheduler. On migration, re-register the fd with the new scheduler's poll_fd. Cost: one `epoll_ctl` delete + add per migration of an I/O-waiting process.
2. **Option B (zero-cost migration)**: Use a shared epoll fd (via `EPOLL_CTL_ADD` from any thread). The waking scheduler enqueues the process onto the correct scheduler's run queue via a lock-free inter-scheduler queue.

We start with **Option A** for simplicity. Most processes won't migrate while waiting on I/O.

#### io_uring (Future Optimization)

For maximum TechEmpower performance on Linux 5.6+:

```c
// Instead of epoll for accept + recv + send:
struct io_uring ring;
io_uring_queue_init(4096, &ring, IORING_SETUP_SQPOLL);

// Submit accept:
struct io_uring_sqe *sqe = io_uring_get_sqe(&ring);
io_uring_prep_accept(sqe, listen_fd, NULL, NULL, 0);
io_uring_sqe_set_data(sqe, accept_process);

// Submit recv:
sqe = io_uring_get_sqe(&ring);
io_uring_prep_recv(sqe, conn_fd, buf, len, 0);
io_uring_sqe_set_data(sqe, conn_process);

io_uring_submit(&ring);
```

io_uring eliminates syscall overhead by using shared ring buffers between userspace and kernel. With `IORING_SETUP_SQPOLL`, the kernel polls the submission queue in a dedicated kernel thread — zero syscalls in the hot path. This provides ~10% throughput improvement over epoll.

### 3.4 Memory Model

#### Decision: Per-Process Heaps with Process-Local RC

This is the single most impactful architectural decision. We adopt BEAM's per-process heap model, adapted for Perceus reference counting:

**Per-process heap**: Each process allocates from its own bump-allocator arena. This means:
- `march_alloc` within a process is a simple pointer bump (no mutex, no atomic).
- `march_incrc` / `march_decrc` within a process are **non-atomic** operations (just increment/decrement a plain integer). No cache-line contention.
- Cross-process references require atomic RC (but these only occur via message passing, which copies data — see §3.5).

```c
typedef struct march_heap {
    char       *base;       // Heap base address
    char       *ptr;        // Current allocation pointer (bump upward)
    char       *limit;      // End of heap
    uint32_t    size;       // Current heap size in bytes
    uint32_t    generation; // For generational collection
} march_heap_t;

// Fast allocation — no atomics, no locks:
static inline void *march_process_alloc(march_heap_t *heap, size_t sz) {
    sz = (sz + 7) & ~7;  // Align to 8 bytes
    if (heap->ptr + sz > heap->limit) {
        return march_heap_grow_and_alloc(heap, sz);  // Slow path: grow or GC
    }
    void *p = heap->ptr;
    heap->ptr += sz;
    // Initialize RC header — non-atomic, this is process-local!
    *(int64_t *)p = 1;  // rc = 1
    return p;
}
```

**Heap sizing**: Start at 4 KB (matching the stack). Grow by doubling: 4→8→16→32→64 KB, then by 50% increments. When a process terminates, its entire heap is freed in one `free()` call (no individual object deallocation needed).

#### Interaction with Perceus RC

Perceus already generates `march_incrc` / `march_decrc` calls. We split these into two variants:

- `march_incrc_local(p)` / `march_decrc_local(p)` — non-atomic, for objects known to be process-local.
- `march_incrc_shared(p)` / `march_decrc_shared(p)` — atomic, for objects that have crossed a process boundary (message passing, shared immutable data).

The compiler can determine locality statically in most cases: any value that hasn't been sent in a message and hasn't been received from a message is process-local. The type system's linear types (see §3.5) make this even more precise.

#### GC Strategy

With per-process bump allocation, we can use a **simple semi-space copying collector**:

1. When the heap is full, allocate a new heap (2× current size).
2. Copy all live objects (traced from the process's stack roots) to the new heap.
3. Free the old heap.

This is essentially BEAM's minor GC. Because March uses RC (not tracing GC), we can be even simpler: objects with RC > 0 that are reachable from the stack are live. The RC handles most deallocation eagerly; the semi-space copy handles heap compaction and reclaiming fragmented space.

**Cycle detection**: March's type system can statically prevent most cycles (functional data structures are acyclic by construction). For cases where cycles are possible (mutable references, if ever added), a per-process cycle detector can run as part of the semi-space copy.

### 3.5 Message Passing

#### Copy vs. Move: Leveraging Linear Types

BEAM always copies messages between process heaps. This is safe but expensive for large messages. March has **linear types** — a value with a linear type is used exactly once. This enables a crucial optimization:

- **Linear message send**: If the sent value has a linear type, the compiler knows the sender will not use it after sending. The value can be **moved** (transferred) to the receiver's heap with a single memcpy, and the sender's reference is invalidated. No RC increment or decrement needed.
- **Non-linear message send**: If the sent value might be used after sending, it must be **deep-copied** into the receiver's heap (like BEAM). The sender retains its copy.

```march
// Linear send — zero-copy transfer:
let msg: Linear(Request) = build_request(data)
send(actor, msg)
// `msg` is consumed here — compiler error to use it after send

// Non-linear send — deep copy:
let msg: Request = build_request(data)
send(actor, msg)
println(msg.id)  // Still valid — msg was copied, not moved
```

This gives March a significant advantage over BEAM for large messages: process-to-process communication of large payloads (buffers, parsed ASTs, etc.) can be zero-copy.

#### Mailbox Implementation

Each process has an **MPSC (multi-producer, single-consumer) lock-free queue** built from a Treiber stack (matching the current runtime) plus a local receive queue:

```
Senders (any thread):  CAS-push onto mbox_head (Treiber stack, LIFO)
                           ↓
Receiver (owning scheduler): atomic_exchange(mbox_head, NULL)
                           → reverse to FIFO order
                           → append to mbox_local (process-local linked list)
                           ↓
Selective receive:     scan mbox_local for matching pattern
                       use mbox_save pointer to skip already-examined messages
```

The `mbox_save` pointer implements BEAM's selective receive optimization: after a receive that didn't match, the save pointer advances past the examined messages. The next receive starts from the save pointer, not from the head. This prevents the O(n²) rescanning problem.

#### Mailbox Overflow Protection

To prevent a single process from consuming unbounded memory via its mailbox:

- **Soft limit** (default 10,000 messages): Log a warning, set a process flag.
- **Hard limit** (default 1,000,000 messages): Sender blocks (backpressure) or message is dropped (configurable per-process). This is stricter than BEAM (which has no built-in limit) but prevents the common "mailbox explosion" bug.

---

## 4. Part 2: HTTP Server Optimizations for TechEmpower

### 4.1 Connection Handling: Process Per Connection

With the green thread scheduler, we replace the current thread-pool model with **one process per connection**:

```march
fn handle_connection(socket: TcpSocket) -> Unit {
    loop {
        match tcp_recv_http(socket) {
            Ok(request) -> {
                let response = router(request)
                tcp_send(socket, serialize_response(response))
            }
            Err(_) -> {
                tcp_close(socket)
                break
            }
        }
    }
}
```

Each `tcp_recv_http` call that would block instead suspends the process via `march_io_wait` — the process consumes only ~4 KB while waiting. At 1M connections, that's ~4 GB of RAM for connection state alone, well within a 32 GB server.

### 4.2 Accept Pool

Multiple acceptor processes spread across scheduler threads to avoid accept contention:

```march
fn start_acceptors(listen_fd: Int, count: Int, handler: TcpSocket -> Unit) -> Unit {
    // One acceptor per scheduler thread
    for i in 0..count {
        spawn(fn() {
            loop {
                match tcp_accept(listen_fd) {
                    Ok(client_fd) -> spawn(fn() { handler(client_fd) })
                    Err(_) -> break
                }
            }
        })
    }
}
```

On Linux, use `SO_REUSEPORT` so each acceptor has its own listen socket — the kernel distributes incoming connections across them, eliminating the thundering herd problem. This achieves ~99K accepts/second (per BEAM/Ranch benchmarks with `SO_REUSEPORT`).

### 4.3 Database Connection Pooling

A pool of persistent database connections, managed as a set of processes:

```
Pool architecture:
    [Pool Manager Process]
        ├── [Conn Process 1] — holds persistent TCP connection to PostgreSQL
        ├── [Conn Process 2]
        ├── ...
        └── [Conn Process N]

Checkout flow:
    1. Request handler sends `checkout` message to Pool Manager
    2. Pool Manager sends back a connection handle (or queues the request if all busy)
    3. Request handler uses the connection for queries
    4. Request handler sends `checkin` message when done
```

**Pool sizing**: N = number of scheduler threads × 2 (enough parallelism without overwhelming PostgreSQL). For TechEmpower's 28-core test hardware, that's ~56 connections.

**Prepared statement caching**: Each connection process maintains a hash map of SQL → prepared statement handle. First execution prepares the statement; subsequent executions reuse the prepared handle. This eliminates repeated parsing/planning overhead.

### 4.4 Prepared Statements

```march
type DbConn = {
    fd: Int,
    prepared: Map(String, PreparedStmt),
}

fn query(conn: DbConn, sql: String, params: List(DbValue)) -> Result(Rows, DbError) {
    let stmt = match map_get(conn.prepared, sql) {
        Some(s) -> s
        None -> {
            let s = pg_prepare(conn.fd, sql)
            conn.prepared = map_insert(conn.prepared, sql, s)
            s
        }
    }
    pg_execute(conn.fd, stmt, params)
}
```

For the TechEmpower fortune benchmark, the query `SELECT id, message FROM fortune` is prepared once and executed thousands of times per second.

### 4.5 Response Pipeline

#### Zero-Copy Response Building

March already has `writev` support. We extend this with pre-serialized response components:

```c
// Pre-compute static response parts at server startup:
static const char PLAINTEXT_HEADERS[] =
    "HTTP/1.1 200 OK\r\n"
    "Content-Type: text/plain\r\n"
    "Content-Length: 13\r\n"
    "Server: March\r\n"
    "\r\n";

static const char PLAINTEXT_BODY[] = "Hello, World!";

// Hot path — single writev, no allocation:
struct iovec iov[2] = {
    { .iov_base = (void*)PLAINTEXT_HEADERS, .iov_len = sizeof(PLAINTEXT_HEADERS) - 1 },
    { .iov_base = (void*)PLAINTEXT_BODY,    .iov_len = 13 }
};
writev(fd, iov, 2);
```

For dynamic responses, build the response in a process-local scratch buffer (part of the process heap), then `writev` the header and body segments without copying into a single contiguous buffer.

#### SIMD HTTP Parsing

Replace the current character-by-character HTTP parser with a SIMD-accelerated parser based on picohttpparser techniques:

```c
// Use SSE4.2 PCMPESTRI to find delimiters in 16-byte chunks:
__m128i delimiters = _mm_setr_epi8('\r', '\n', ':', ' ', 0,0,0,0,0,0,0,0,0,0,0,0);
__m128i chunk = _mm_loadu_si128((__m128i*)buf);
int idx = _mm_cmpestri(delimiters, 4, chunk, 16, _SIDD_UBYTE_OPS | _SIDD_CMP_EQUAL_ANY);
```

This processes 16 bytes per instruction cycle vs 1 byte in the current parser. For the plaintext benchmark (which is HTTP-parsing-bound), this is critical.

### 4.6 io_uring for Ultimate Performance

For the plaintext and JSON benchmarks, io_uring provides the final throughput edge:

```
Architecture with io_uring:
    Each scheduler thread:
        ├── io_uring instance (ring size 4096)
        ├── Submission queue: pre-loaded with accept/recv/send operations
        └── Completion queue: polled in scheduler loop

    Hot path (zero syscalls with SQPOLL):
        1. Completion arrives: "recv complete on fd X, N bytes in buffer"
        2. Scheduler wakes process X, gives it the buffer
        3. Process parses HTTP, builds response in-place
        4. Process submits "send" to the SQ ring (just a memory write)
        5. Process submits "recv" for next request (memory write)
        6. Process yields — no syscalls made!
```

With `IORING_FEAT_FAST_POLL` and `IORING_SETUP_SQPOLL`, the entire accept→recv→parse→send cycle involves zero syscalls in steady state. The kernel's SQ poll thread handles submission, and completions appear in shared memory.

---

## 5. Part 3: Implementation Phases

### Phase 1: Basic Green Thread Scheduler (Stackful Coroutines in C Runtime)

**Scope**: Replace the current global-run-queue scheduler with per-core schedulers and stackful coroutines.

**Deliverables**:
- `march_context_switch` assembly for x86-64 and aarch64
- `march_process` struct with 4 KB segmented stacks
- Per-scheduler run queues (single priority level initially)
- `march_spawn` creates a green thread (not a pthread)
- `march_yield` saves context and returns to scheduler
- Basic round-robin scheduling within each scheduler thread
- All scheduler threads started at runtime init, pinned to cores

**Key files**:
- `runtime/march_context.S` — context switch assembly
- `runtime/march_scheduler.c` — scheduler loop, run queues
- `runtime/march_process.c` — process creation, stack management
- `runtime/march_runtime.c` — update `march_spawn`/`march_send` to use new scheduler

**Estimated complexity**: ~1,500 lines of C + ~100 lines of assembly.
**Estimated time**: 2–3 weeks.

**Validation**: Spawn 100K processes that each increment a shared atomic counter, verify all complete. Measure spawn time (target: <5μs) and context switch time (target: <50ns).

### Phase 2: I/O Integration (epoll/kqueue)

**Scope**: Integrate kernel I/O polling into the scheduler loop so processes can sleep on file descriptors.

**Deliverables**:
- Per-scheduler epoll/kqueue instance
- `march_io_wait(fd, events)` suspends the calling process
- `march_io_poll()` called in the scheduler loop, wakes ready processes
- Platform abstraction layer: `march_poller_t` with epoll (Linux) and kqueue (macOS) backends
- Timer wheel for `receive...after` timeouts
- Update `march_tcp_recv`, `march_tcp_send`, `march_tcp_accept` to use `march_io_wait` instead of blocking

**Key files**:
- `runtime/march_poller.c` — epoll/kqueue abstraction
- `runtime/march_timer.c` — hierarchical timing wheel
- `runtime/march_http.c` — rewrite HTTP server to use green threads + polling instead of thread pool

**Estimated complexity**: ~1,200 lines of C.
**Estimated time**: 2 weeks.

**Validation**: HTTP server handling 10K concurrent connections with `wrk` benchmark. Verify no fd leaks under sustained load. Verify all connections get fair service (no starvation).

### Phase 3: Work Stealing + Load Balancing

**Scope**: Implement Chase-Lev work-stealing deques and periodic load migration.

**Deliverables**:
- Chase-Lev lock-free deque per scheduler (local push/pop + remote steal)
- Random-victim work stealing when a scheduler's queues are empty
- Periodic migration algorithm: examine all schedulers' queue depths, migrate processes from overloaded to underloaded schedulers
- Inter-scheduler wakeup via eventfd (Linux) or pipe (macOS)
- Priority queues (high, normal, low) with the normal:low ratio (8:1)

**Key files**:
- `runtime/march_deque.c` — Chase-Lev deque
- `runtime/march_scheduler.c` — extend with stealing, migration, priority queues

**Estimated complexity**: ~800 lines of C.
**Estimated time**: 1.5 weeks.

**Validation**: Benchmark with unbalanced workload (90% of work on 1 scheduler). Verify work stealing distributes load. Measure tail latency under mixed high/normal/low priority processes.

### Phase 4: Reduction Counting in Compiled Code

**Scope**: Insert reduction checks into LLVM-compiled March code for preemptive scheduling.

**Deliverables**:
- Thread-local `march_tls_reductions` variable
- Reduction check insertion at function prologues in `llvm_emit.ml`
- `march_yield()` from compiled code: save LLVM-generated stack frame, switch to scheduler
- Leaf function optimization: omit reduction checks for provably-terminating leaf functions
- Budget of 4,000 reductions per quantum

**Key files**:
- `lib/tir/llvm_emit.ml` — insert reduction check IR at function entry
- `runtime/march_scheduler.c` — `march_yield` implementation for compiled code path

**Estimated complexity**: ~200 lines of OCaml + ~100 lines of C.
**Estimated time**: 1 week.

**Validation**: Compile a CPU-intensive loop (e.g., fibonacci(40)) and verify it yields every ~4000 function calls. Run multiple CPU-bound processes and verify fair scheduling (each gets roughly equal CPU time).

### Phase 5: Per-Process Heaps + Message Passing with Linear Type Optimization

**Scope**: Switch from shared heap to per-process heaps. Implement copy-on-send with linear-type move optimization.

**Deliverables**:
- `march_heap_t` per-process bump allocator
- `march_process_alloc` (non-atomic, process-local)
- `march_incrc_local` / `march_decrc_local` (non-atomic RC for process-local objects)
- `march_msg_copy(src_heap, dst_heap, value)` — deep copy a value between heaps
- Linear message send: compiler emits `march_msg_move` instead of `march_msg_copy` when the value has a linear type
- MPSC mailbox with selective receive (save pointer)
- Semi-space copying collector for per-process heap compaction

**Key files**:
- `runtime/march_heap.c` — per-process heap allocator
- `runtime/march_message.c` — message copy/move
- `runtime/march_gc.c` — semi-space collector
- `lib/tir/llvm_emit.ml` — emit local vs shared RC calls based on linearity analysis
- `lib/scheduler/mailbox.ml` — update OCaml-side mailbox to match

**Estimated complexity**: ~2,000 lines of C + ~300 lines of OCaml.
**Estimated time**: 3 weeks.

**Validation**: Measure message throughput: 1M messages/sec target for small messages (64 bytes). Verify no memory leaks under sustained messaging (processes that spawn, exchange messages, and die). Benchmark RC overhead reduction: measure `march_incrc` call count with and without process-local optimization.

### Phase 6: TechEmpower Benchmark Harness + Optimization

**Scope**: Build a TechEmpower-compliant benchmark implementation and optimize for competitive scores.

**Deliverables**:
- TechEmpower benchmark implementations in March:
  - **Plaintext**: Pre-serialized response, SIMD HTTP parser, writev
  - **JSON**: Fast JSON serializer (process-local scratch buffer)
  - **Single DB query**: Connection pool, prepared statements
  - **Multiple queries**: Pipelined queries
  - **Fortunes**: Template rendering, HTML escaping, sort
  - **Updates**: Batch UPDATE statements
- PostgreSQL wire protocol client (March native, using green threads for async I/O)
- Connection pool manager process
- SIMD HTTP request parser (SSE4.2 fast path)
- Benchmark runner scripts (wrk2, h2load)
- io_uring backend (Linux only, feature-gated)

**Key files**:
- `runtime/march_http_parse_simd.c` — SIMD HTTP parser
- `runtime/march_postgres.c` — PostgreSQL wire protocol
- `runtime/march_uring.c` — io_uring backend (optional)
- `bench/techempower/` — benchmark implementations
- `bench/scripts/` — automation scripts

**Estimated complexity**: ~3,000 lines of C + ~500 lines of March.
**Estimated time**: 4 weeks.

**Targets** (on 32-core server):
- Plaintext: >5M req/s (pipelined) — competitive with top 20
- JSON: >500K req/s
- Single query: >200K req/s
- Fortunes: >100K req/s

---

## 6. Appendix: Key Numbers and Targets

### BEAM Reference Numbers

| Metric | BEAM | March Target |
|---|---|---|
| Process spawn time | ~3 μs | <5 μs |
| Process memory overhead | ~2.5 KB | ~4.2 KB |
| Context switch time | ~10 ns (internal) | <50 ns |
| Max concurrent processes | Millions | 1M+ (4 GB RAM) |
| Reduction budget | 4,000 | 4,000 |
| Scheduler threads | 1 per core | 1 per core |
| I/O mechanism | epoll/kqueue integrated | epoll/kqueue + io_uring |

### TechEmpower Reference Numbers (Round 23, 32-core)

| Benchmark | Top Score | March Target | Notes |
|---|---|---|---|
| Plaintext (pipelined) | ~12M req/s | 5M+ req/s | Rust/C dominate; we target top 20 |
| JSON | ~1M req/s | 500K+ req/s | Serialization-bound |
| Single query | ~500K req/s | 200K+ req/s | DB-bound |
| Fortunes | ~300K req/s | 100K+ req/s | Full-stack test |

### Architecture Summary

```
┌─────────────────────────────────────────────────────────────────┐
│                        March Application                        │
│                  (compiled March → LLVM → native)               │
├─────────────────────────────────────────────────────────────────┤
│                     Green Thread Runtime                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐          │
│  │Scheduler │ │Scheduler │ │Scheduler │ │Scheduler │  ...      │
│  │Thread 0  │ │Thread 1  │ │Thread 2  │ │Thread 3  │          │
│  │          │ │          │ │          │ │          │          │
│  │ RunQ(hi) │ │ RunQ(hi) │ │ RunQ(hi) │ │ RunQ(hi) │          │
│  │ RunQ(nm) │ │ RunQ(nm) │ │ RunQ(nm) │ │ RunQ(nm) │          │
│  │ RunQ(lo) │ │ RunQ(lo) │ │ RunQ(lo) │ │ RunQ(lo) │          │
│  │          │ │          │ │          │ │          │          │
│  │ epoll/kq │ │ epoll/kq │ │ epoll/kq │ │ epoll/kq │          │
│  │ TimerWhl │ │ TimerWhl │ │ TimerWhl │ │ TimerWhl │          │
│  │          │ │          │ │          │ │          │          │
│  │◄──steal──►│◄──steal──►│◄──steal──►│◄──steal──►│          │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘ └────┬─────┘          │
│       │             │             │             │               │
│  ┌────┴─────────────┴─────────────┴─────────────┴────┐         │
│  │              Green Threads (Processes)              │         │
│  │  ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐ ┌───┐      │         │
│  │  │P1 │ │P2 │ │P3 │ │P4 │ │P5 │ │...│ │Pn │      │         │
│  │  │4KB│ │4KB│ │8KB│ │4KB│ │4KB│ │   │ │4KB│      │         │
│  │  └───┘ └───┘ └───┘ └───┘ └───┘ └───┘ └───┘      │         │
│  │  Each: own stack + own heap + own RC + mailbox     │         │
│  └────────────────────────────────────────────────────┘         │
├─────────────────────────────────────────────────────────────────┤
│  Per-Process Heaps │ MPSC Mailboxes │ Perceus RC (local+shared) │
├─────────────────────────────────────────────────────────────────┤
│               OS: Linux (epoll/io_uring) / macOS (kqueue)       │
└─────────────────────────────────────────────────────────────────┘
```

### Total Estimated Implementation Effort

| Phase | Scope | Estimated Time |
|---|---|---|
| Phase 1 | Basic green thread scheduler | 2–3 weeks |
| Phase 2 | I/O integration | 2 weeks |
| Phase 3 | Work stealing + load balancing | 1.5 weeks |
| Phase 4 | Reduction counting (compiled) | 1 week |
| Phase 5 | Per-process heaps + messages | 3 weeks |
| Phase 6 | TechEmpower optimization | 4 weeks |
| **Total** | | **~13.5 weeks** |

### Risk Assessment

1. **Segmented stacks + C FFI**: C functions called from March expect a contiguous stack. Mitigation: switch to a large "C call stack" (per scheduler thread) when entering FFI, or use `mmap` with guard pages for stack segments.

2. **Reduction counting overhead**: A branch at every function entry is ~2% overhead in microbenchmarks. Mitigation: omit for leaf functions; batch reduction checks (decrement by N at loop headers instead of 1 per call).

3. **Per-process heap fragmentation**: Bump allocation wastes space if objects have varied lifetimes. Mitigation: semi-space GC compacts periodically; process heaps are small so copies are fast.

4. **io_uring maturity**: io_uring APIs are still evolving. Mitigation: io_uring is Phase 6 (optional); epoll is the stable default.

5. **Linear type coverage**: Not all March types are linear; non-linear messages still require deep copy. Mitigation: encourage linear types for message payloads via documentation and linting; the copy path is still correct, just slower.
