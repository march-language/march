# Linux `--cap-sandbox`: threads started before `march_sandbox_install` are now filtered (fixed 2026-09-30)

Filed 2026-09-21 while adding the `IO.NetListen` deny
(`specs/progress/2026-09-21-cap-sandbox-linux-netlisten.md`).

## The hole

`march_sandbox_install` (`runtime/march_runtime.c`, Linux branch) installed the
seccomp filter with `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ...)`, which
covers the calling thread and the threads it creates later, not the ones that
already exist. It runs from `spawn_main_impl`, but by then `@main` has run the
hot-reload setup (`lib/tir/llvm_toplevel.ml`, `hr_setup` before
`march_spawn_main`), whose `march_reload_server_start` creates the reload
server thread, the one that accepts deploys and `dlopen`s new code. A linked C
library's constructor can start threads before `main` too. All of these ran
unfiltered.

## Decision: `SECCOMP_FILTER_FLAG_TSYNC`, not moving the install

The filter is installed with
`syscall(__NR_seccomp, SECCOMP_SET_MODE_FILTER, SECCOMP_FILTER_FLAG_TSYNC, &prog)`
after `PR_SET_NO_NEW_PRIVS`. TSYNC attaches it to every thread of the process
atomically. The kernel propagates `no_new_privs` to them, and a positive return
names a thread it could not synchronise, which fails closed like every other
install error.

Why not install before `hr_setup`:
- it would only cover threads that `@main` creates afterwards. A thread
  started by a C constructor (or any other pre-`main` code) would still escape.
  TSYNC covers every thread that exists, whoever started it.
- it would run the HCR boot (`march_dispatch_init`/`publish`,
  `replay_state`) under the filter and change `@main`'s order. TSYNC leaves
  `@main` and `lib/tir/llvm_toplevel.ml` untouched, so no HCR code or ordering
  changed.
- it matches the macOS backend, where `sandbox_init` is process-wide.

The raw syscall is used rather than libc's `seccomp()` because glibc added
the wrapper only in 2.38 and musl has none.

## Consequence for hot reload under the sandbox

The reload server thread is now inside the filter on Linux, as it already
was on macOS. It binds its Unix socket on its own thread after
`march_reload_server_start` returns, so in a `--hot-reload --cap-sandbox` binary
that withholds `IO.NetListen` (or `IO.Network`) the listener can be denied,
depending on which thread gets there first. That race already existed on macOS.
Nothing tests the combination. Fixing it means changing
`march_reload.c` (bind before the install and hand the fd to the thread),
which belongs to the HCR owners: filed as
`specs/todos/2026-09-30-hcr-reload-listener-races-cap-sandbox-install.md`.
Builds without `--cap-sandbox` are unaffected (`march_sandbox_install` is a
no-op there).

## Verification

`test/test_cap_sandbox_runtime.ml`, new case `linux+macos: a thread started
before the install is filtered after it`. The FFI shim's
`__attribute__((constructor))` starts a thread before `main`, so before the
install, and parks it on a pipe. After the install, March releases it and it
runs `socket()` + `bind()` to loopback. The fixture withholds `IO.Network`.
The case asserts that the constructor thread started (`started=1`), that the
main thread is filtered (`main=1`, unchanged behaviour), and that the
pre-existing thread is filtered too (`early=1`, EPERM).

- **Linux** (Docker, `march-amdr-repro`, ubuntu arm64). The suite was run
  with `MARCH_RUNTIME_DIR` pinned and a fresh CAS and `HOME` for each leg.
  - RED with origin/main's `march_runtime.c`: `early = 1` FAILs,
    `Received: 0`. The thread started before the install ran unfiltered.
  - GREEN with the branch runtime: all 6 Linux cases pass (the 5 existing
    ones and the new one).
- **macOS**: all 10 non-skipped cases pass, the new one included, and it
  reports `early=1` there as well. The runtime change is entirely inside the
  `#elif defined(__linux__)` branch, so the macOS runtime compiles to the same
  code as before.
