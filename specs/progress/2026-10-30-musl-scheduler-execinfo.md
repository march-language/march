# Every compile on musl failed: `march_scheduler.c` included `<execinfo.h>` unguarded

Fixed 2026-10-30. `44ad3edbc` (2026-10-12, "report SIGILL/SIGTRAP with pc, lr and a frame walk")
added `#include <execinfo.h>` and a `backtrace_symbols_fd` call to `runtime/march_scheduler.c`.
musl has no `execinfo.h`, so from then on every `march --compile` on an Alpine host died
compiling the runtime (`fatal error: 'execinfo.h' file not found`). Nothing on the PR path builds
on musl; it surfaced when `.github/workflows/build.yml`'s "Verify --static output runs in an empty
container" step (added 2026-10-19, release and nightly only) went red on the 2026-10-29 and
2026-10-30 nightlies, both Linux legs.

Fix: the include and the call are guarded with `!defined(__linux__) || defined(__GLIBC__)`, the
condition `march_runtime.c` already uses for `MARCH_HAVE_EXECINFO` (and documents). On musl the
fatal-fault frame walk is still written, unsymbolised; `MARCH_FATAL_BACKTRACE` has no effect there.

Verified: the unfixed file fails with exactly the CI error under `zig cc -target
x86_64-linux-musl`; the fixed `march_scheduler.c` and `march_runtime.c` compile for that target.
The next nightly's scratch-container step is the end-to-end check.
