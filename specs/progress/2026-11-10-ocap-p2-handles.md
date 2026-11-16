# Ocap phase 2b: handles for files, sockets and processes; name scopes; no handles across nodes (2026-11-10 to 2026-11-13)

Ocap phase 2b (Tasks 1-14 of `specs/plans/2026-11-10-ocap-p2-handles-plan.md`; Task 15, the
whole-branch verification, is separate). Spec: `specs/2026-11-10-object-capability-design.md`.
Tasks 1-4 shipped as phase 2a (PR march-language/march#1244); Tasks 5-14 are PR #1245 on
`claude/ocap-p2b-handles`. The per-task detail is in the dated files this one summarises:
`2026-11-10-ocap-p2a-handle-box-types.md`, `-p2b-file-dir-handle.md`, `-p2b-gate-raw-builtins.md`,
`-p2b-process-handles.md`, `2026-11-11-ocap-p2b-http-on-handles.md`, `2026-11-11-ocap-p2b-merge-p1-wrapping.md`,
`2026-11-12-ocap-p2b-cluster-fd-internal.md`, `-file-dir-checked-open.md`, `-scope-grammar.md`,
`-io-registry-name-scopes.md`, `2026-11-13-ocap-p2b-handles-not-cross-node.md`.

## What shipped

- **Handle boxes.** `File.Handle`, `File.Dir`, `Socket`, `Listener`, `Udp.UdpSocket`, `Tls.TlsConn`,
  `Tls.TlsCtx`, `WebSocket.WsSocket` and `Process` are reference-counted boxes (C `march_handle_*`,
  tag -10, kinds 1-9), not `Int` descriptors. A use after `close` is `Err(Closed)`, a handle dropped
  without `close` releases its descriptor, and closing a socket another task is parked on wakes it
  (macOS included). Opens return `Result(Result(Handle, E), CapError)`.
- **Raw builtins are stdlib-only.** The Int-descriptor builtins (`tcp_*`, `udp_*`, `tls_*`,
  `file_open*`, `dir_*`, `process_*_proc`, `http_server_*`, ...) are `stdlib_internal`: user code naming
  one gets an error that names the wrapper. `@[stdlib_internal]` is also on `Socket.raw_fd/adopt/borrow`,
  `HttpServer.fd` and the cluster plumbing (Task 9); `use`/`alias` cannot bypass it (R8).
  Using a handle needs no capability (a `needs ()` function may read a `File.Handle`).
- **`File.Dir`** (Task 7): opens beneath a directory (`openat2(RESOLVE_BENEATH)` on Linux, per-component
  `O_NOFOLLOW` walk on macOS, which refuses every symlink); `FileError.Escapes`.
- **HTTP on handles** (Task 6): client and server use `Socket`; the server's per-connection `Socket` is
  borrowed (closing it never closes the server's descriptor). `HttpServer.test_conn` replaces direct
  `Conn(...)` construction.
- **`Process.spawn_async` returns a `Process` handle** (Task 8); its release kills (TERM, then KILL) and
  reaps the child.
- **Name scopes** (Tasks 11-12): `needs` scopes take several strings and string-valued options;
  `IO.Mut("a", "b")`, new capability `IO.Registry` (`Actor.register/unregister/whereis/registered`),
  `prefix("w.")`. `cap_scope_violation` for a literal name outside the scope or a computed one. One
  spelling per scope, `march --fmt` round-trips.
- **Handles are unsendable across nodes** (Task 13): `handle_not_sendable` at `derive Json`,
  `Node.send`/`enqueue` and `@[remote]` handlers; one list, `Cap_surface_ty.handle_type_spellings`.
- **Renames / compat.** `Channel.Socket` became `Channel.ChannelSocket` (R5). The five builtin handle
  TCons lower to one reserved TIR type (R7); a user type named `Socket`/`Process`/... is a distinct type.

## Rulings and decisions

R1 `==` on a handle stays a type error (already `missing_impl`). R2 the second of phase 1 / phase 2b to
land wraps the opens as `Result(Result(H, E), CapError)` (2b wrapped, with `Authority.check`). R3 the
macOS `shutdown()` wake gap is closed in Task 5. R4 every handle kind has a releaser (process kills and
reaps). R5 `Channel.Socket` renamed. R6 `canon_type_name` never folds a module type into a builtin
handle name. R7 one reserved `$Handle` TIR type. R8 `use`/`alias` skip `@[stdlib_internal]` members from
user code. R9 "handle needs no capability" tests use the per-function `needs ()` bound. R10 borrowed
sockets are refused by `Tls.connect` and detach refuses while another use is in flight. R11
`Cap_attrib.owner_of` resolves a lifted stdlib lambda by its lowering host (Provenance), not the entry
module. R12 no `fd_cancel_waits` for a borrowed `Conn` (known limit, todo). R13 `with_connection`
keep-alive after a failure is a todo. R14 `File.open_dir_write` is charged `IO.FileWrite` only. R15
Process-release SIGKILL escalation, EINTR and the racing `wait_proc` in fix round 1. R16 scope
encoding collisions carried into Task 12. R17 oracles and the full suite for Task 12 deferred to Task 15
and CI (load 83-372). R18 every stdlib type wrapping a handle box (incl. `Process`) is unsendable.

## Tests (names; the per-task reports under `.superpowers/sdd/2026-11-10-ocap-p2-handles-plan/` have the rest)

- `test_compiler` suite "handle types": `handle_name_tables_agree`, `handle_send_direct`,
  `handle_send_at_depth`, `handle_derive_refused`, `handle_remote_actor`, `handle_user_types_send`,
  `handle_use_charges_nothing`, `registry_kind_required`; `test_stdlib_only`: `cluster_plumbing_internal`.
- `test/errors/handle_not_sendable_1`, `cap_*` scope cases; `test_cap_ops`, `test_cap_symbols`,
  `test_cap_check_coverage`, `test_cap_mode_parity` (R11 lambda owner), host_scope (50, incl. idempotence).
- `test_stdlib_march` groups `file_handle`, `file_dir` (12), `tls`, `socket`; `test_file_handle_compiled`,
  `test_process_compiled` (13); C `test_handle.c` (detach, use-after-close, wake-on-close).
- Native/golden: `file_handle_leak_probe`, `process_handle_leak_probe`, `live_process_registry`,
  `tcp_accept_timeout`, `getaddrinfo_green_thread`; `process_release_reaps_child`, `process_wait_race_src`;
  `dir_beneath_symlink_linux` (Linux only).

## Follow-ups filed

`2026-11-13-listen-address-parameter`, `2026-11-13-http-server-spawn-n-handle-int`,
`2026-11-13-macos-dir-symlinks-refused`, `2026-11-13-cluster-record-types-hold-raw-fds`,
`2026-11-12-path-scope-not-checked-at-wrappers`, `2026-11-13-name-scope-bypasses`,
`2026-11-12-march-caps-misses-stdlib-mediated-caps`, `2026-11-12-stdlib-internal-per-function-hint`,
`2026-11-12-ocap-p2b-demos-off-stdlib-source`, `2026-11-11-conn-socket-field-exposed`,
`2026-11-10-file-handle-close-flush-error`, `2026-11-11-with-connection-keepalive-after-failure`,
`2026-11-12-ocap-capture-checking`. `IO.WebSocket` stays declaration-only.

## Downstream sweep (2026-11-13, this branch's compiler, `--check`, `MARCH_LIB_PATH`, read-only)

Each repo was checked with `main.exe --check ENTRY` under a private `HOME` and a scratch cwd, with
`MARCH_LIB_PATH` set to the dependency `lib`/`src` directories, and no `forge build` cache. Only the
`stdlib_internal` diagnostics are this phase's; `cap_result_unhandled` is phase 1 (`Result(_, CapError)`
on `Vault.new/whereis` and the like) and the rest (type_mismatch, unknown_qualified_name, int_overflow,
ambiguous_constructor, refinement_unverified, cap_ceiling) were not attributed: the dependency checkouts
are not pinned to this compiler's era.

| Repo (entry) | Result | Phase 2b breakage |
|---|---|---|
| `depot` (`lib/depot.march`) | exit 1: 9 `stdlib_internal`, 17 `cap_result_unhandled` | `lib/wire/connection.march` (7) and `lib/wire/decode.march` (2) call `tcp_connect`, `tcp_send_all`, `tcp_recv_exact`, `tcp_close` on an `Int` fd that `Connection` stores in its `fd` field. |
| `conduit` (`lib/conduit.march`, + depot) | exit 1: the same 9 (all inside depot), 104 `cap_result_unhandled`, 3 `type_mismatch`, 2 `cap_ceiling` | None of its own: conduit never names a raw socket builtin; it inherits depot's wire client. |
| `test_conduit_app` (`src/test_conduit_app.march`) | exit 1: one `syntax_error` at `src/test_conduit_app.march:25` (a record literal), so nothing past the parse was judged | Unknown; the sweep stops at the parse. It reaches sockets only through conduit and depot. |
| `forgepm` (`lib/forgepm.march`, + depot, conduit, march_doc, bastion) | exit 1: 19 `stdlib_internal` (depot's 9 plus 10 in `lib/forgepm/http/client.march`), 221 `cap_result_unhandled`, others unattributed | `lib/forgepm/http/client.march` hand-rolls an HTTP client over `tcp_connect`, `tcp_send_all`, `tcp_recv_http` (the diagnostic points at `HttpClient` / `HttpTransport.request`), `tcp_close`. |
| `depot` as a dep of the three above | see row 1 | one migration fixes all four repos |

**Migration.** Depot's wire client holds a `Socket` instead of an `Int`: `Connection.fd : Int`
becomes `sock : Socket`, `tcp_connect(h, p)` becomes `Socket.connect(h, p)` (a `Result(Result(Socket,
SocketError), CapError)`; `Authority.must(...)` or `let?` on the outer layer), `tcp_send_all(fd, s)` becomes
`Socket.write(sock, s)`, `tcp_recv_exact(fd, n)` becomes `Socket.recv_exact(sock, n)` (returns `Bytes`), and
`tcp_close(fd)` becomes `Socket.close(sock)`. Depot also needs the phase 1 wrapping of its `Vault`
calls. forgepm's `http/client.march` should use `HttpClient.get/post` (or `HttpTransport.request`) rather
than its own socket client. No repo was edited, committed or built into; `forge.lock` toolchain pins
(`local-main-b26bacf0` in forgepm) predate this branch, so each needs a toolchain bump with the migration.
