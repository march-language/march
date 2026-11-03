# `[P3]` Under ASAN, `march_sched_getaddrinfo` creates its resolver thread from a green thread

**Filed** 2026-10-12, follow-up to
`specs/progress/2026-10-12-asan-ffi-blocking-worker-spawn-sigsegv.md`, which
fixed the same failure in the blocking-FFI pool and listed this site as "not
changed, same failure class".

## Symptom

`march_sched_getaddrinfo` (`runtime/march_scheduler.c`; `tcp_connect` and
`tcp_connect_timeout` call it) `pthread_create`s a detached resolver thread
from the calling green thread whenever preemption is active, i.e. always once
the scheduler runs.

Under ASAN, `pthread_create` runs with every signal blocked. Green stacks grow
lazily: a touch of a not-yet-grown page raises SIGSEGV and the scheduler's
handler extends the stack. Inside `pthread_create` that SIGSEGV cannot be
delivered, so the kernel kills the process: exit 139, no ASAN report, no
`march: fatal` line.

Reproduced deterministically (Docker `march-ci-ubuntu-step6b`, arm64,
glibc 2.39, clang 18) with `test/test_scheduler_fdwait.c` compiled with
`-fsanitize=address` against the runtime's scheduler: case 7 calls
`march_sched_getaddrinfo` from a fresh green thread and dies, 3 runs of 3:

```
#0 __interceptor_calloc ()          si_addr == sp: a stack-growth fault
#1 calloc (b=16, a=19)              rtld-malloc.h:44
#2 allocate_dtv                     elf/dl-tls.c:370
#3 _dl_allocate_tls
#4 allocate_stack                   nptl/allocatestack.c:429
#5 __pthread_create_2_1
#6 __interceptor_pthread_create ()
#7 march_sched_getaddrinfo          runtime/march_scheduler.c:4648
#8 resolver                         test/test_scheduler_fdwait.c:100
```

Compiled March programs did not hit it in practice: `tcp_connect_impl` calls
`snprintf` before the lookup, and ASAN's `printf_common` reaches ~4.7 KiB
deeper than `pthread_create` does, so the pages are already grown. That is
luck, not a guarantee.

## Same class, also reachable from a green thread

`march_http_server_listen` runs on the green thread that called
`HttpServer.listen`, and starts threads from it: `march_evloop_server_listen`
(`runtime/march_http_evloop.c`, one event-loop thread per core) and
`march_http_pool_start_max` (`runtime/march_http.c`, the initial pool
workers).

## Fixed (2026-10-12)

All three now create their threads through `march_sched_run_on_sched_stack`
(added for the blocking-FFI fix), so `pthread_create` runs on the scheduler's
native OS-thread stack while the calling green thread is suspended:

- `runtime/march_scheduler.c`: `resolve_spawn_thread`. The request and the
  spawn result live on the caller's green stack, which stays put until the
  spawn returns. A resolver that finishes before the caller parks leaves a
  wake permit, which the park consumes (`march_sched_wake` on a RUNNABLE proc).
  The no-helper fallback (plain `getaddrinfo` with preemption masked) is
  unchanged.
- `runtime/march_http_evloop.c`: `evloop_spawn_all` opens the listeners and
  starts the event-loop threads; the caller still joins them.
- `runtime/march_http.c`: `pool_spawn_initial` starts the initial workers.

Verification (Docker `march-ci-ubuntu-step6b`, arm64):

- `test_scheduler_fdwait.c` with `-fsanitize=address`, `detect_leaks=1`: base
  runtime exit 139 in 3 runs of 3; fixed runtime "all passed" in 3 runs of 3.
- `scripts/native-sanitize-sweep.sh -l -s "1 14"` over the new fixture
  `test/native/getaddrinfo_green_thread.march` (dials `localhost` on a closed
  port from main and from 160 tasks at depths 0..159, each must resolve and be
  refused), plus `tcp_connect_refused_after_park` and `ffi_blocking`: OK at 1
  and 14 schedulers. The new fixture is also OK on the base runtime, for the
  `snprintf` reason above; it pins the resolver path from many green threads
  rather than reproducing the crash.
- An ASAN-built `HttpServer.listen` program in pool and event-loop modes at 1
  and 14 schedulers serves `GET /ping` on base and fixed runtimes alike
  (the green stack was already grown there too).
- gdb (run from the start, not attached) confirms the resolver's
  `pthread_create` now comes from `resolve_spawn_thread` <- `sched_loop`.

## Not changed

Every other `pthread_create` in `runtime/` runs on a real OS thread:

- `march_scheduler.c`: scheduler threads and the preemption daemon, from
  `march_sched_run` on the main OS thread before any green thread runs.
- `march_runtime.c` `march_ensure_sched_started`: returns early inside the
  scheduler (`march_sched_in_scheduler`).
- `march_http.c` `pool_grow_if_starved`: called from `pool_worker`, an OS thread.
- `march_http_evloop.c` WebSocket handler threads: from `evloop_run`, an OS
  thread.
- `march_ffi.c` blocking workers: already fixed (see the FFI progress file).
- Out of scope, left alone (HCR / observe): `march_reload.c` reload server and
  `march_shell.c` shell accept thread are started from `@main` before
  `march_spawn_main` (the shell's per-session threads from its accept thread);
  `march_observe.c` and `march_observe_snapshot.c` document that their threads
  are created from the main OS thread or their accept thread.
