# Linux `--cap-sandbox`: threads started before `march_sandbox_install` run unfiltered

Filed 2026-09-21 while adding the `IO.NetListen` deny
(`specs/progress/2026-09-21-cap-sandbox-linux-netlisten.md`).

`march_sandbox_install` (`runtime/march_runtime.c`) installs the seccomp
filter with `prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, ...)`, which applies
to the calling thread and threads it creates afterwards, not to threads that
already exist. It runs from `spawn_main_impl`, but `@main` runs the
hot-reload setup first (`lib/tir/llvm_toplevel.ml`, `hr_setup` before
`march_spawn_main`), and `march_reload_server_start` creates the reload
server thread there. So in a `--hot-reload --cap-sandbox` binary, the thread
that accepts deploys and `dlopen`s new code has no filter at all.

Options, to be measured: install with `seccomp(SECCOMP_SET_MODE_FILTER,
SECCOMP_FILTER_FLAG_TSYNC, ...)` so every existing thread is covered (then
the reload server's own `bind` on its Unix socket needs `IO.NetListen` or an
exemption, since it binds on its thread after start), or move the sandbox
install ahead of `hr_setup`. Either way, add a runtime test that makes a
denied syscall from a thread created before the install.
