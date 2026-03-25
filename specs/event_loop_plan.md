# Plan: Event-Loop HTTP Server (The Architectural Ceiling)

## Status
**Phases 1–2 complete.** Non-blocking I/O infrastructure + kqueue/epoll event loop
with SO_REUSEPORT implemented. Phases 3–4 (per-thread arena, io_uring) are optional
future work. Thread-per-connection fallback retained via compile flag.

---

## Why the Current Model Hits a Ceiling

The current server is `thread-per-connection + mutex-protected work queue`:

```
accept() ──► mutex enqueue ──► worker wakeup ──► recv/parse/send ──► close/loop
```

At ~50k req/s with 100 keep-alive connections, each second involves:
- 50k mutex lock/unlock pairs (queue enqueue + dequeue)
- 50k `pthread_cond_signal` calls
- ~16–64 threads, most sleeping on `pthread_cond_wait`
- Each `recv()` and `writev()` is a blocking syscall on a per-thread fd

The fundamental limit: **one thread per concurrent connection**. To handle
10,000 concurrent connections you would need 10,000 threads. The OS context
switch overhead and per-thread memory (~8 MB stack each) make this impossible
at TechEmpower scale.

TechEmpower Round 23 top entries (Actix, ntex, may-minihttp) achieve
**6–7 million req/s** on 28-core Linux servers using an event-loop model: a
small fixed pool of threads (one per core), each running a non-blocking
event loop that multiplexes thousands of connections via `epoll`/`kqueue`.

---

## Target Architecture

```
                     ┌─────────────────────────────────────┐
  port 8080          │  Core 0            Core 1  ...  Core N│
  SO_REUSEPORT ──►   │  ┌───────────┐    ┌───────────┐      │
  (N listener fds)   │  │ event loop│    │ event loop│      │
                     │  │ kqueue/   │    │ kqueue/   │      │
                     │  │ epoll     │    │ epoll     │      │
                     │  │           │    │           │      │
                     │  │ accept()  │    │ accept()  │      │
                     │  │ recv()    │    │ recv()    │      │
                     │  │ pipeline()│    │ pipeline()│      │
                     │  │ send()    │    │ send()    │      │
                     │  └───────────┘    └───────────┘      │
                     └─────────────────────────────────────┘
```

### Key properties
- **`SO_REUSEPORT`**: N threads each hold their own listener fd on the same
  port. The kernel distributes `accept()` calls across them. No accept mutex.
- **Non-blocking fds**: All connections are `O_NONBLOCK`. `recv()`/`send()`
  return `EAGAIN` instead of blocking. The event loop re-registers the fd and
  moves on.
- **One event loop per core**: `kqueue` (macOS) or `epoll` (Linux). Each loop
  owns a subset of connections; no cross-thread fd sharing in the common case.
- **No connection queue**: No mutex, no `pthread_cond_signal`. Accept → add to
  kqueue/epoll → handle inline.
- **Synchronous pipeline**: The March pipeline (`Conn -> Conn`) remains
  synchronous — the event loop calls it inline. This avoids needing async/await
  in March at this stage.

### Expected gain
| Model | macOS ARM64 | Linux (projected) | TechEmpower-class Linux |
|---|---|---|---|
| Current thread-per-conn | ~50k req/s | ~150k req/s | — |
| Event loop (this plan) | ~200k req/s | ~500k–1M req/s | ~3–6M req/s |

The gap to TechEmpower top is mostly: (a) 28-core server vs 8-core laptop,
(b) Linux vs macOS network stack, (c) `io_uring` (optional phase 3).

---

## Implementation Phases

### Phase 1 — Non-blocking recv/send infrastructure (prereq)

**Files**: `runtime/march_http.c`, new `runtime/march_io.h`

1. Add `march_set_nonblocking(int fd)` helper: `fcntl(fd, F_SETFL, O_NONBLOCK)`.
2. Add `march_recv_nonblocking(conn_state_t *c)` that reads into a per-connection
   buffer and returns:
   - `RECV_COMPLETE` — full request buffered
   - `RECV_PARTIAL` — need more data (re-arm event)
   - `RECV_ERROR` — close connection
3. Add `march_send_nonblocking(conn_state_t *c)` symmetric to recv:
   - Tracks how many bytes of the response iovec have been sent
   - Returns `SEND_COMPLETE`, `SEND_PARTIAL`, `SEND_ERROR`
4. `conn_state_t` — new per-connection struct that holds:
   ```c
   typedef struct conn_state {
       int      fd;
       uint8_t  phase;        /* READING | WRITING | KEEP_ALIVE_WAIT */
       int      keep_alive;
       recv_buf_t rbuf;       /* already exists as tl_recv_buf but now per-conn */
       march_response_t resp; /* already zero-alloc, move here */
       /* parsed request fields (valid during WRITING phase) */
       void    *pipeline_result;
   } conn_state_t;
   ```
5. Pool `conn_state_t` objects using a free-list per thread to avoid malloc
   per connection.

**Milestone**: `march_recv_nonblocking` + `march_send_nonblocking` pass unit
tests; existing blocking server still works.

---

### Phase 2 — kqueue/epoll event loop (core change)

**Files**: `runtime/march_http_evloop.c` (new), `runtime/march_http.c`

1. Introduce `march_evloop_t` — thin wrapper around `kqueue`/`epoll_create1`:
   ```c
   #if defined(__APPLE__)
   #  include <sys/event.h>
   #  define MARCH_USE_KQUEUE
   #elif defined(__linux__)
   #  include <sys/epoll.h>
   #  define MARCH_USE_EPOLL
   #endif
   ```
2. Per-thread event loop function `evloop_run(int listener_fd, void *pipeline)`:
   ```
   kq = kqueue() / epq = epoll_create1()
   register listener_fd for EVFILT_READ / EPOLLIN
   loop:
     n = kevent(kq, ...) / epoll_wait(epq, ...)
     for each ready event:
       if fd == listener_fd:
         accept() → set O_NONBLOCK → add to kq/epoll → alloc conn_state
       else:
         c = conn_state for fd
         if READABLE:  handle_read(c)
         if WRITABLE:  handle_write(c)
         if ERROR/HUP: close_conn(c)
   ```
3. `handle_read(c)`:
   - Call `march_recv_nonblocking(c)`
   - On `RECV_COMPLETE`: call `march_http_parse_request()`, call pipeline,
     build response into `c->resp`, arm fd for write
   - On `RECV_PARTIAL`: re-arm fd for read (already armed)
4. `handle_write(c)`:
   - Call `march_send_nonblocking(c)`
   - On `SEND_COMPLETE` + keep_alive: reset conn_state, re-arm for read
   - On `SEND_COMPLETE` + !keep_alive: close and free conn_state
   - On `SEND_PARTIAL`: re-arm for write
5. `march_http_server_listen` spawns N threads (`nproc` count) each calling
   `evloop_run` with its own `SO_REUSEPORT` listener fd:
   ```c
   for (int i = 0; i < ncpus; i++) {
       int lfd = create_listener(port);  /* SO_REUSEPORT each time */
       pthread_create(..., evloop_run, {lfd, pipeline});
   }
   ```

**Milestone**: server passes all existing HTTP tests under the event loop.
Benchmark shows ≥3× improvement over thread-per-conn on the same machine.

---

### Phase 3 — Connection state pool + per-thread arena (optional)

**Files**: `runtime/march_http_evloop.c`

Once the event loop is working, the remaining malloc pressure is in the March
pipeline itself (headers, Conn object, etc. — ~25–35 allocs per request).

1. Per-thread arena allocator: a 64 KB bump-pointer slab reset between
   requests. All `march_string_lit` and `march_alloc` calls during request
   parsing route through the arena. The arena is freed as a unit when the
   response is sent. Requires tagging arena-allocated objects so Perceus
   skips them.
2. Connection state free-list: recycle `conn_state_t` objects instead of
   `malloc`/`free` per connection.

**Milestone**: malloc profiler shows ≤2 allocations per request on the hot
path (arena + result string).

---

### Phase 4 — io_uring (Linux only, optional)

**Files**: new `runtime/march_http_uring.c`

`io_uring` eliminates the `epoll_wait` + `recv()` + `send()` syscall chain:
- `IORING_OP_ACCEPT` — async accept, no `kevent`/`epoll_wait` loop
- `IORING_OP_RECV` — async recv directly into response buffer
- `IORING_OP_SEND` — async send without leaving userspace
- `IORING_OP_LINK` — chain recv → process → send in one submission

This brings per-request syscall count from 2 (`recv`+`send`) to 0 on the
hot path (ring buffer polling mode). Expected gain on Linux: 2–5×.

**Milestone**: Linux-only build path; same API as Phase 2 event loop.
Benchmark ≥500k req/s on 8-core Linux.

---

## Compatibility Constraints

- The March pipeline function pointer (`Conn -> Conn`) stays synchronous.
  The event loop calls it inline in the worker thread — no March language
  changes needed for Phase 1 and 2.
- `march_http_server_listen` signature stays unchanged (March code calls it).
- `march_response_t` / `send_response_with_ka` already zero-alloc; they
  slot directly into `conn_state_t.resp`.
- The blocking server path (`connection_thread`) is kept as a compile-time
  fallback (`MARCH_HTTP_USE_BLOCKING`) for platforms without `kqueue`/`epoll`.

---

## Files Touched

| File | Change |
|---|---|
| `runtime/march_http.c` | Replace `march_http_server_listen` accept loop; keep `connection_thread` as fallback |
| `runtime/march_http_evloop.c` | New: kqueue/epoll event loop implementation |
| `runtime/march_http_io.c` | New: non-blocking recv/send state machine |
| `runtime/march_http_io.h` | New: `conn_state_t`, `recv_buf_t`, phase enums |
| `runtime/march_http.h` | Add `MARCH_HTTP_USE_EVLOOP` compile flag |
| `specs/progress.md` | Update after each phase |

---

## Benchmarking Plan

After each phase, run the standard suite:

```bash
# Build
clang -O2 -msse4.2 -DMARCH_HTTP_USE_EVLOOP ...

# Sanity
curl -v http://localhost:8080/

# Throughput (same parameters as current baseline)
wrk -t4 -c100 -d30s --latency http://localhost:8080/

# Concurrency stress (reveal event loop correctness issues)
wrk -t8 -c1000 -d30s http://localhost:8080/

# Compare against thread-per-conn baseline
wrk -t4 -c100 -d10s http://localhost:8080/   # event loop
wrk -t4 -c100 -d10s http://localhost:8081/   # thread-per-conn (port 8081)
```

Reference numbers to beat:
- Current March (thread-per-conn): ~50k req/s
- Hyper 1.x (Rust, macOS): ~49k req/s
- Target Phase 2: ≥150k req/s macOS, ≥500k req/s Linux
