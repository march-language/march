# `[P2]` `native_actor_enumeration` aborts on the ubuntu CI leg: glibc `tcache_thread_shutdown(): unaligned tcache chunk detected`

Filed 2026-09-14. A compiled-only, Linux-only, intermittent abort of
`test/native/actor_enumeration.march` under `@test/runtest`, after the program
has printed its output (the golden diff is not what fails; the process is):

```
(cd _build/default/test && /usr/bin/sh -c ./native_actor_enumeration) > …/native_actor_enumeration.out
tcache_thread_shutdown(): unaligned tcache chunk detected
Aborted (core dumped)
```

Seen on `main` (CI runs 34897714430 at `d0667633`, 34896389148 at `6dc8c23f`)
and on a branch with no runtime change (34901635867 at `0286cd64`); the
macOS leg and the local runs are clean. glibc's tcache check fires when a
chunk being freed at thread exit is not 16-byte aligned — i.e. something
`free()`d a pointer that `malloc` never returned (a March heap pointer, an
interior pointer, or a tagged one) from a thread that is shutting down. The
fixture enumerates actors (`actor_pid_indices` / `pid_of_int`) and lets them
die; the thread-exit path points at the scheduler's per-thread teardown.

## What to do

- Reproduce in the ubuntu container (`ci/Dockerfile.ubuntu`, build only
  `bin/main.exe`; see memory on ASAN needing Docker locally) with
  `MALLOC_CHECK_=3` and, if it reproduces, under ASAN — the sweep in
  `scripts/sanitize.sh` covers the native corpus.
- Until then it is a rerun: `gh run rerun <id> --failed` has cleared it
  every time. Do not quarantine it without the reproduction; the abort is
  real memory corruption and the fixture is the only thing seeing it.
