# macOS `--cap-sandbox` / `forge cap run`: `IO.NetListen` split from `IO.NetConnect`

Done 2026-09-28. Filed 2026-09-21 as
`specs/todos/2026-09-21-cap-sandbox-macos-netlisten-not-split.md`, alongside the
Linux fix (`specs/progress/2026-09-21-cap-sandbox-linux-netlisten.md`).

## The problem

Both SBPL builders (`bin/main.ml` `cap_sandbox_define`, and forge's
`Cap_sandbox.profile_for`) emitted `(allow network*)` whenever the program held
anything on the `IO.Network` branch. The "holds" test is bidirectional, so a
program holding only `IO.NetConnect` got `network*`, which includes
`network-bind`: a connect-only program could bind and listen.

## Measurement (macOS 26, arm64, `sandbox-exec` over real compiled March binaries)

Baseline = the deny-default profile both builders share. Client probe: a
NetConnect-only program doing `tcp_connect("example.com", 80)` and
`Tls.https_get("example.com", 443, "/")` (verify_peer on).

| extra clauses | client (DNS + TCP + TLS) |
|---|---|
| none | `getaddrinfo failed` |
| `(allow network*)` | ok, `HTTP/1.1 200 OK` |
| `(allow network-outbound)` | ok |
| `(allow network-outbound (remote ip))` | `getaddrinfo failed` |
| `(allow network-outbound (literal "/private/var/run/mDNSResponder"))` | DNS ok, connect `EPERM` |
| `(remote ip)` + the mDNSResponder literal | ok |
| `(allow network-bind)(allow network-inbound)` | `getaddrinfo failed` |

So name resolution is `network-outbound` to mDNSResponder's unix socket, not a
`mach-lookup` (`mach*` is already in the baseline and does not help). TLS needs
nothing beyond the TCP connect plus the baseline's file reads (CA bundle).
`localhost` resolves without mDNSResponder, which is what lets the hermetic test
below use it.

Server probe: `examples/http_hello.march` (NetListen only) on a fixed port,
hit with `curl` from outside the sandbox.

| extra clauses | server |
|---|---|
| `(allow network-bind)(allow network-inbound)` | serves `Hello from compiled March!` |
| `(allow network-outbound)` | `SO_REUSEPORT listener[0] failed: Operation not permitted` |
| `(allow network*)` | serves |

## The change

Both builders now emit, instead of `network*`:

- `(allow network-outbound)` when the program holds `IO.NetConnect` (or a
  descendant: `.TLS`, `IO.WebSocket`, `IO.Database`; or an ancestor);
- `(allow network-bind)(allow network-inbound)` when it holds `IO.NetListen`
  (or an ancestor).

`IO.Network` or `IO` makes both true. Every child of `IO.Network` in
`lib/caps/cap_lattice.ml` sits under one of the two, so nothing lost access.
Linux is unchanged: the seccomp `MARCH_CAP_DENY_*` flags and forge's
`bwrap_args` were not touched.

## Tests

- `test/test_cap_sandbox_runtime.ml`: new macOS fixtures. NetConnect only:
  a real `tcp_connect("localhost", port)` + `tcp_send_all` to a listener the
  test opens outside the sandbox succeeds, `bind`/`listen` return `EPERM`,
  a refused connect returns `ECONNREFUSED` (61). NetListen only: `bind`/`listen`
  succeed, outbound `connect` returns `EPERM`. The existing deny-process and
  deny-write fixtures (NetConnect held) probed `bind` expecting 0, which
  pinned the bug; they now probe a refused connect expecting `ECONNREFUSED`.
- `test/test_cap_sandbox_profile.ml`: NetConnect-only and NetListen-only
  fixtures; the embedded clause set must equal `profile_for`'s, and the
  direction of each grant is pinned on both sides.
- `forge/test/test_cap_sandbox.ml`: `profile_for` unit tests for the split.

RED on origin/main's builders with the new tests: 4 failures
(both profile split tests; NetConnect-only `bind = 0` where 1 was expected;
NetListen-only `connect = 61` where 1 was expected). GREEN with the change.
