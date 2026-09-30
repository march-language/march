# `--hot-reload --cap-sandbox`: the reload server's listener races the sandbox install

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
