# `[P3]` Under ASAN, the first `blocking` extern call dies of a silent SIGSEGV (Linux arm64)

**Found** 2026-10-12 by the native sanitizer sweep
(`scripts/native-sanitize-sweep.sh`, Docker `march-ci-ubuntu-step6b`, arm64,
glibc 2.39, clang 18). Only fixture affected: `test/native/ffi_blocking.march`.

## Symptom

```
MARCH_SANITIZE=1 MARCH_DEBUG_RUNTIME=1 march --compile -o ffi_blocking native/ffi_blocking.march
ASAN_OPTIONS=detect_leaks=0 MARCH_NUM_SCHEDULERS=1 ./ffi_blocking   # also at 14
==N==WARNING: ASan doesn't fully support makecontext/swapcontext ...
Segmentation fault      (exit 139, no output, no ASAN report, no "march: fatal" line)
```

The same program compiled WITHOUT `MARCH_SANITIZE` prints `42` / `200` and exits 0.

## Where (gdb, not attached: run under gdb from the start)

```
#0 __interceptor_calloc ()
#1 calloc (b=16, a=19)                       rtld-malloc.h:44
#2 allocate_dtv                              elf/dl-tls.c:370
#3 _dl_allocate_tls
#4 allocate_stack                            nptl/allocatestack.c:429
#5 __pthread_create_2_1 (start_routine=asan_thread_start)
#6 __interceptor_pthread_create ()
#7 march_run_blocking ()                     runtime/march_ffi.c:380
#8 march_run_blocking_i ()
#9 march_main ()
#10 proc_trampoline ()
```

`march_run_blocking` spawns a pool worker with `pthread_create` **from the calling
green thread's stack**. That is the same failure class as
`march_hcr_drain`'s timer (memory note "ASAN: pthread_create from a green thread
= silent SIGSEGV", 2026-09-23), which was fixed by not creating the thread from a
green thread. `runtime/march_observe.c` documents the same rule in its header.

## Why it is not fixed here

The blocking pool genuinely needs OS threads, and it spawns them lazily from the
caller, which is always a green thread. A fix means moving the spawn off the
green stack (a pre-spawned minimum pool created from `march_sched_init`, or a
spawner thread the caller signals), which changes the pool's elasticity contract
(the comment above `march_run_blocking` explains why a busy worker must never be
reused). That is a design decision, not a one-liner.

## Impact

ASAN builds only: no non-sanitized run has ever shown it. But it makes every
program that calls a `blocking` extern unsanitizable, so the sanitize gate
cannot cover that path at all (it is not in `specs/lang/golden/sanitize.sh`'s
curated list today).
