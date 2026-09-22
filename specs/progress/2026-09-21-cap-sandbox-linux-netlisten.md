# DONE 2026-09-21: `--cap-sandbox` on Linux denies `bind`/`listen` without `IO.NetListen`

From `specs/todos/2026-08-03-cap-sandbox-remaining.md` (the `IO.FileRead` /
Landlock bullet stays open there).

## The gap

`bin/main.ml`'s `holds` is bidirectional, so a program holding only
`IO.NetConnect` makes `holds "IO.Network"` true and clears
`MARCH_CAP_DENY_NET`: `socket()` is allowed (it has to be, to connect), and
nothing denied `bind`/`listen`. An HTTP client could accept connections.

## The change

Exactly the shape `specs/2026-08-10-cap-tier5-investigation.md` sketched:

- `bin/main.ml`: `^ deny "LISTEN" (holds "IO.NetListen")` in the one shared
  `deny_flags` decision.
- `runtime/march_runtime.c`, `march_sandbox_install`: `#ifdef
  MARCH_CAP_DENY_LISTEN` -> `DENY_NR(__NR_bind); DENY_NR(__NR_listen);`.
  `listen` is denied separately because `listen()` on an unbound socket
  auto-binds an ephemeral port, so a `bind`-only deny would not stop a
  listener. Filter length stays well under `MAX_FILTER` (96).

Who else calls `bind`/`listen` in the runtime: only the two `tcp_listen` paths
(`march_http.c`, `march_http_evloop.c`, both behind `IO.NetListen` builtins)
and the hot-reload server (`march_reload.c`). The reload server is not
affected, but only because it runs outside the filter: its thread is created
in `@main` before `march_spawn_main` installs the sandbox, and
`PR_SET_SECCOMP` filters only the calling thread and its later children.
That is a pre-existing hole of its own, filed as
`specs/todos/2026-09-21-cap-sandbox-linux-reload-thread-unfiltered.md`.

## Verification (Docker, ubuntu arm64 / aarch64, `march-amdr-repro` image)

`test/test_cap_sandbox_runtime.ml`, two new Linux fixtures compiled and run
under `--cap-sandbox`:

- NetConnect held, NetListen withheld: `socket=0`, `bind=1` (EPERM),
  `listen=1` (EPERM, on an unbound socket), `connect=111` (ECONNREFUSED to a
  closed loopback port, i.e. the client half is untouched).
- NetListen held: `bind=0`, `listen=0`.

All 5 Linux cap_sandbox_runtime cases pass. Red controls, each in the
container:

| perturbation | result |
|---|---|
| `deny "LISTEN"` removed from `bin/main.ml` | deny-listen FAILs: `bind` expected 1, got 0 |
| only `DENY_NR(__NR_listen)` removed from the runtime | deny-listen FAILs: `listen` expected 1, got 0 |

macOS: the 8 macOS/profile cap_sandbox cases still pass (the SBPL profile does
not read the new flag). Verified in Docker, not on a bare Linux host; x86_64
was not run (the syscall numbers come from `<sys/syscall.h>`, and
ECONNREFUSED is 111 on both arches).

---

## Original bullet

- [ ] **`IO.NetListen` on Linux is advisory — re-scoped 2026-08-10, see
  `specs/2026-08-10-cap-tier5-investigation.md`.** Traced the exact cause:
  `bin/main.ml`'s `holds` check is bidirectional, so holding `IO.NetConnect`
  alone clears the seccomp NET-deny flag entirely (since NetConnect is a
  descendant of Network), which allows `socket()` outright — and nothing
  denies `bind`/`listen` specifically, so a NetConnect-only program can also
  listen. This is a small, well-understood extension of the EXISTING
  `DENY_NR`/`MARCH_CAP_DENY_*` pattern in `runtime/march_runtime.c`
  (`march_sandbox_install`) — NOT a new mechanism, contrary to how this was
  filed. The investigation doc has a near-complete code sketch. What's
  actually blocking it: no Linux machine was available to verify.

  **Unblocked 2026-09-08:** the other blocker, "land the CI job first," is
  done — `specs/todos/2026-08-10-cap-sandbox-no-runtime-enforcement-ci.md`
  landed as `test/test_cap_sandbox_runtime.ml`
  (`specs/progress/2026-08-12-cap-sandbox-runtime-enforcement-ci.md`), which
  verifies real syscall-level enforcement for the `IO.Network`/`IO.Process`/
  `IO.FileWrite` deny classes on both Linux (seccomp-bpf) and macOS
  (Seatbelt) as part of `scripts/run-tests.sh`. That file's own "Still open"
  note names `IO.NetListen` and Landlock as the next classes to extend it
  with when they land — i.e. this item's own remaining work, not a
  prerequisite for it. `IO.NetListen` itself is NOT implemented here; a Linux
  machine to verify against is still needed.
