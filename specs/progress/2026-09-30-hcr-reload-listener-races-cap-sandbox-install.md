# `--hot-reload --cap-sandbox`: the reload server's listener raced the sandbox install — FIXED 2026-10-18

Filed 2026-09-30 with
`specs/progress/2026-09-30-cap-sandbox-linux-reload-thread-unfiltered.md`.

`march_reload_server_start` (`runtime/march_reload.c`) only creates the reload
server thread; that thread then calls `socket`, `unlink`, `bind` and `listen`
on its own schedule. `@main` meanwhile goes on to `march_spawn_main`, whose
`march_sandbox_install` now covers every thread on both backends (Linux via
`SECCOMP_FILTER_FLAG_TSYNC`, macOS because `sandbox_init` has always been
process-wide). So in a `--hot-reload --cap-sandbox` binary that withholds
`IO.NetListen` (Linux also `IO.Network`), whether the reload server gets its
listener depends on which thread wins, and its later state writes need
`IO.FileWrite`. On macOS this was already the case before the TSYNC change;
on Linux the thread used to escape the filter entirely.

No test combines `--hot-reload` with `--cap-sandbox` today.

Fix options (HCR-owner decision): create and bind the listening socket
synchronously in `march_reload_server_start`, before the install, and hand
the fd to the thread; or document that a sandboxed hot-reloadable program
must grant `IO.NetListen`/`IO.FileWrite`, and make the compiler say so. In
either case, add a test that runs the combination.

## Decision (owner, 2026-10-11)

Take the first option: `march_reload_server_start` creates, binds and
listens on the reload socket SYNCHRONOUSLY, before `march_sandbox_install`
runs, and hands the listening fd to the reload thread. Not implemented yet;
the HCR session owns `runtime/march_reload.c` and will land it, with the
`--hot-reload --cap-sandbox` test above. The reload thread's later state
writes (`IO.FileWrite`) still need an answer when this is done.

## Fixed 2026-10-18

As decided: `march_reload_server_start` now creates, binds, chmods and listens on
the reload socket on @main's thread (`reload_listen`, `runtime/march_reload.c`),
before `spawn_main_impl` runs `march_sandbox_install`, and hands the listening fd
to the server thread, which only accepts. `accept` is not filtered on either
backend, so the listener keeps working under the sandbox. The epoch-counter load
moved with it, and the thread's duplicate `load_pubkey_from_hex` went (the start
function already does it).

Two more found while testing:

- **The observe socket never came up under `--cap-sandbox`.** It is derived from
  the reload socket (`<socket>.observe`) and started in `spawn_main_impl` AFTER
  the install, so its bind was refused on every run, not just sometimes
  ("march: observe socket bind ...: Operation not permitted"). It now starts
  just before the install. The shell listener (`march_shell.c`) already bound
  synchronously from `march_reload_server_start`, so it was not affected.
- **An over-long reload socket path was silently truncated** (`strncpy` into the
  256-byte buffer, then `strncpy` again into the 104/108-byte `sun_path`), so the
  server bound at a name nobody asked for while the shell and observe listeners
  refused the same path. It is now refused with a message, like theirs.

Test: `test/test_cap_sandbox_runtime.ml`, "--hot-reload under --cap-sandbox keeps
the reload and observe sockets": a program holding only `IO.Console` and
`IO.Foreign`, compiled `--cap-sandbox --hot-reload`, must answer `PING` on its
reload socket and accept on its observe socket after `main` has started. The test
sets `MARCH_TEST_RELOAD_BIND_DELAY_MS=300` (a test hook at the top of the reload
thread), so a bind moved back onto that thread fails it at once: verified red on
the old code ("march_reload: bind: Operation not permitted"), green 3/3 after, on
macOS arm64. The Linux (seccomp) leg was not run locally (no Docker daemon); CI's
Linux jobs run it.

Still open, filed separately: the reload server's later file writes under a
withheld `IO.FileWrite`
(`specs/todos/2026-10-18-hcr-reload-writes-under-cap-sandbox.md`).
