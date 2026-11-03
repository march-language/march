# DONE 2026-10-07: a green-thread spawn before `march_sched_init` mprotect'ed the page past its stack

## Symptom

`MARCH_CI_RUNTEST_SPLIT=1 dune runtest --root . -j 4` in the Ubuntu 24.04 arm64
CI image dumped core from `test_reload_activate4_runner reload_keys.txt`:
SIGSEGV at `__march_init` (`test/hcr_stub_so.c:20`) <- `activate_items`
(`runtime/march_reload.c`) <- the `COMMIT_BATCH` arm of `handle_line` <-
`handle_client` <- `reload_server_thread`, with the main thread blocked in
`read` waiting for the reply. It looked like a dlopen/dlclose race (the stub
`.so` unmapped under the server).

## Root cause

It was not a dlopen/dlclose race. `LD_DEBUG=files` shows the stub opened three
times and closed once, so its refcount never reached 0. In the same container
the crash is **deterministic**: every run, no load needed. Under gdb the faulting
pc is `__march_init`'s FIRST instruction (`sub sp, sp, #0x10`), not the store
to `g_epoch`, and `info proc mappings` shows the stub's text page mapped
`rw-p`. So this was an instruction-fetch fault on a page that had lost
`PROT_EXEC`. Directly below it sat a 1 MiB `---p` region: a green-thread stack
reservation.

`runtime/march_scheduler.c` cached the page size (`g_page_size`) only in
`march_sched_init()`. The test's signed `DRAIN … hard_ms:600000` makes
`march_hcr_drain` spawn its hard-deadline timer (`hcr_hard_proc`) through
`march_sched_spawn_daemon_unpinned` on the reload-server thread. This harness
never initialises the scheduler, so that spawn saw page 0. `stack_alloc_lazy`
then:

1. reserved `MARCH_STACK_MAX + 0` bytes, with no guard page;
2. `mprotect`ed `[mem + MARCH_STACK_MAX, +4 KiB)` read/write. That page is one
   **past** its own reservation.

Linux hands out mmap addresses top-down, so the new 1 MiB reservation landed
directly below the most recent mapping: the stub `.so` dlopen'd moments
earlier by `ACTIVATE5`. Step 2 succeeded on the stub's text page and stripped
exec from it. The next call into the stub, `__march_init` at the batch commit,
faulted. On macOS the page past the reservation was unmapped, so the
`mprotect` failed and the spawn quietly returned NULL ("failed to allocate
process stack"). That is the benign face of the same bug, and why it only
showed on Linux.

This exposure is not limited to the harness. In a compiled `--hot-reload`
program, `@main` starts the reload server (`llvm_toplevel.ml`'s `hr_setup`)
before `march_spawn_main` runs `march_sched_init`, so a signed `DRAIN`
arriving in that window takes the same path.

## Fix

`runtime/march_scheduler.c`: `sched_page_size()` caches the page size under a
`pthread_once`. `stack_alloc_lazy`, `stack_reuse`, `stack_retire` and
`march_sched_init` go through it. The SIGSEGV handler still reads the cached
`g_page_size` directly (sysconf is not async-signal-safe). That is sound
because every stack is allocated through `sched_page_size()`, so the value is
set before any green stack can fault.

## Test

`test/test_scheduler_preinit_spawn.c` (dune rule `test_scheduler_preinit_spawn_runner`)
spawns before `march_sched_init` and checks the geometry, which unlike the
crash's adjacency does not depend on address-space layout. It asserts that
the reservation is `MARCH_STACK_MAX` plus one page and that the initial window
lies inside it, then repeats the check for a second pre-init spawn and a
post-init one. Against the old scheduler it is red on both platforms: on
macOS the spawn fails, and on Linux arm64 three checks fail.

`test_reload_activate4_runner` in the `march-ci-ubuntu-step6b` container went
from segfaulting on 5/5 runs to 20/20 green. The four modes (plain, `policy`,
`policy-all`, `restore`) running concurrently under 8 busy-loop CPU hogs then
went 100/100 green.

The "one unrelated C harness" crash noted in
`specs/todos/2026-10-07-flake-bare-sigsegv-native-fixtures-linux.md` is this
bug. That todo's own bare-SIGSEGV flake stays open: compiled programs init
the scheduler before any user spawn, so this fix does not explain it.
