# Runtime: a live actor was freed when the program dropped its last pid

Found 2026-09-14 as `native_actor_enumeration` aborting on the ubuntu CI leg
(`tcache_thread_shutdown(): unaligned tcache chunk detected`, runs
34897714430 and 34896389148 on `main`, 34901635867 twice on a branch), fixed
the same day.

## Reproduction

Deterministic in a Linux/arm64 container (glibc 2.39): 100/100 runs abort,
with or without `MALLOC_CHECK_=3`; macOS never aborts because the freed
block is neither reused nor checked. `gdb` on the abort only shows glibc
walking a corrupted tcache list at a worker thread's exit — the corrupting
write happened earlier. Valgrind: an invalid 8-byte write in
`do_actor_death` 24 bytes into a freed 40-byte `calloc` block, plus reads of
it in `actor_green_thread` and `march_decrc`, and a double `free()`. ASAN
(`MARCH_SANITIZE=1`, works in the container) named the frees: the block is an
actor record allocated by `spawn` in `march_main` and freed by a Perceus
`march_decrc_local` in `march_main`.

## Cause

The runtime held **no reference of its own** to a running actor's record.
`march_spawn` returned the record with the refcount the allocation gave it,
and only the program's pids kept it alive. `let a = spawn(W)` with `a` never
used again drops the only reference right after spawn; the actor's green
thread then reads and writes its `alive` word — and `do_actor_death` its
terminal fields — in freed memory. Every program that kept using its pids
was kept safe by a leak: `send` consumes its pid and `march_send` never
releases it ([[2026-09-13-send-leaks-a-reference-to-a-live-pid]]), so a
pid that was sent to stayed alive by accident.

## Fix

`runtime/march_runtime.c`: `march_spawn_common` takes one reference for the
live actor (`march_incrc(actor)`); `actor_green_thread` releases it as its
very last action on both exit paths (normal and crash-trap), after
`do_actor_death` and the `green_thread = NULL` store. A pid is a handle to a
running actor; the actor's lifetime is its own.

Verified in the container: 100/100 clean, ASAN clean on the fixture, and an
ASAN sweep of every actor-related native fixture clean (see the commit).
The three refcount-probe fixtures (`actor_send_to_self`,
`actor_dispatch_rc_window`, `actor_crash_rc_restore`) assert relative
properties and still pass. The `send` half of the ownership question in
[[2026-09-13-send-leaks-a-reference-to-a-live-pid]] is unchanged: it is
still a leak, no longer the thing standing between a program and a
use-after-free.
