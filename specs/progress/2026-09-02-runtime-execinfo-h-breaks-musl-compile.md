# `march --compile` works on musl (Alpine)

Filed 2026-08-31 as `[P2]`, fixed 2026-09-02. Background:
`specs/progress/2026-08-31-linux-aarch64-release-build-native-arm64.md`.

## The defect

The musl-targeted `linux-aarch64` prebuilt could interpret March but could not
compile it. Two separate breakages, one behind the other — the second only
became visible once the first was fixed, which is why the original report
called `execinfo.h` "the only remaining blocker".

**1. Compile stage.** `runtime/march_runtime.c:27` did an unconditional
`#include <execinfo.h>`. That header is a glibc extension; musl has no such
file, so compiling the bundled runtime died at the first header:

```
runtime/march_runtime.c:27:10: fatal error: 'execinfo.h' file not found
```

**2. Link stage.** With the header fixed, the link failed instead:

```
march_scheduler.c:(.text.sched_spawn_common+0x17c): undefined reference to `getcontext'
march_scheduler.c:(.text.sched_loop+0x468):         undefined reference to `swapcontext'
...
```

musl removed the `ucontext` family from libc while still *declaring* it in
`<ucontext.h>` — so `runtime/march_scheduler.c` (green threads) compiles
cleanly and only fails at link. Alpine ships the implementations separately, in
`libucontext`.

## The fix

`runtime/march_runtime.c`: guard the include and its two uses.

```c
#if !defined(__linux__) || defined(__GLIBC__)
#define MARCH_HAVE_EXECINFO 1
#include <execinfo.h>
#endif
```

glibc defines `__GLIBC__` via `<features.h>`, which the `<stdio.h>` above has
already pulled in, so the test is decided by the time it is reached. Darwin and
the BSDs keep the header (the condition only excludes non-glibc Linux). The
only casualty on musl is the symbolic C backtrace inside the **opt-in**
`MARCH_DEBUG_OOM` forensics, which now prints
`backtrace: unavailable (no <execinfo.h> on this libc)`. March's own stack trace
(`march_print_backtrace`) walks our own frame table and is unaffected — it was
never an `execinfo` consumer.

`bin/toolchain.ml`: new `is_musl_host` / `ucontext_link_flags`, emitting
`-lucontext` when the host is musl and a `libucontext` is present. musl is
detected by its dynamic loader (`/lib/ld-musl-<arch>.so.1`) — there is no
`__MUSL__`-style macro to test. The flag is threaded into both link paths: the
native `--compile` command in `bin/main.ml`, and the runtime `.so` command in
`bin/toolchain.ml` (where it also joins `flags_sig`, i.e. the cache key, so a
cached `.so` built without it is not reused).

It is emitted only when a `libucontext` is actually found: on a musl box
without one, adding the flag would replace the accurate "undefined reference to
`getcontext`" with a less informative "cannot find -lucontext".

## Verification

`alpine:3.21` under Docker on an arm64 Mac — native, no QEMU, ~2 minutes per
cycle rather than a ~100-minute CI round trip.

- **RED control.** The pre-fix `march_runtime.c` (from `git show HEAD:`) still
  fails with `fatal error: 'execinfo.h' file not found` in the same container
  where the patched file compiles clean. The oracle was proven to go red before
  any green was trusted.
- **Acceptance (aarch64), end to end.** A `march` built in Alpine, arranged in
  the release-archive layout (`bin/ stdlib/ runtime/`), compiles and runs a
  hello-world using only the bundled runtime sources:
  `compiled /tmp/hello` → `hello from march`.
- **x86_64.** Every `runtime/*.c` compiles under musl/clang-19 on
  `alpine:3.21` amd64, and all objects link into a running program with
  `-lucontext`. The single exception is `march_runtime_wasm.c`
  (`__builtin_wasm_memory_size`), which is WASM-target-only and is not in the
  native source list.
- macOS is unaffected: `--compile` + run of the same hello-world still works,
  and `scripts/run-tests.sh -q` passes.

## Related

The same investigation fixed the release archives not being statically linked —
see `2026-09-02-linux-release-binaries-are-not-static.md`.
