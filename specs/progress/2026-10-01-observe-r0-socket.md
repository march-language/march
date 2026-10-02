# Observe R0: the observe socket, its JSON writer, test harness and forge client

**Date:** 2026-10-01
**Plan:** [`plans/2026-09-28-observe-recon-shell-plan.md`](../plans/2026-09-28-observe-recon-shell-plan.md), item R0.
**Tracking todo:** [`todos/2026-09-24-observe-recon-shell.md`](../todos/2026-09-24-observe-recon-shell.md).

## What exists now

- **`runtime/march_observe.c` / `.h`** (role `core`, `jit`): a Unix-socket server
  separate from the hot-reload server, so an observer can never block a deploy
  (the reload server serves one client at a time on one thread).
  - Started once from `march_run_scheduler` when `MARCH_OBSERVE_SOCKET` is set,
    or at `<MARCH_HOT_RELOAD_SOCKET>.observe` when only the reload socket is.
  - One accept thread plus one short-lived thread per connection, at most 8 at
    once; the ninth client gets `"error":"busy"`. Every observe thread blocks all
    signals (so `SO_RCVTIMEO` is not restarted away) and is created from the
    main OS thread or the accept thread, never from a green thread.
  - One request line in (max 4096 bytes, `\r\n` accepted), one JSON line out,
    then close. A silent client is dropped after `MARCH_OBSERVE_IDLE_MS`
    (default 5000).
  - Every reply is the envelope `{"proto":"march.observe/1","node","at_ms",
    "took_us","truncated","data"}`, or the same with `"error"` in place of
    `data` (`unknown_verb`, `busy`, `line_too_long`).
  - Verbs: `HELP` (the verb table with tiers) and `PING`. R1 adds rows to the
    same table.
  - The socket is created mode 0600. A stale socket at the path is replaced; any
    other file there is left alone and the server does not start. The socket is
    unlinked at exit.
- **The JSON writer** (`march_jw_*`, same file): automatic commas, RFC 8259
  string escaping, non-finite floats as `null`, and a hard size limit past which
  it stops and reports truncation (the envelope then carries `"data":null`,
  `"truncated":true`).
- **`forge/lib/observe_client.ml`**: `query : Remote.transport -> Hosts.host ->
  string -> (Yojson.Safe.t, string) result` over the existing local and ssh
  transports, plus `parse_reply`, `data_of`, `truncated`, `socket_of`.

## Deviations from the plan

1. **Started from the runtime, not from compiled code.** The plan put the
   `getenv` + start call in `@main` (`lib/tir/llvm_toplevel.ml`). It is in
   `march_run_scheduler` instead: every compiled `main` and the JIT's
   `run_program` call it, on the main OS thread before any green thread exists,
   and it needs no compiler change. A `--compile-so` patch never calls it.
2. **One source file, not two.** The plan split the JSON writer into
   `march_json_out.c`. Every runtime `.c` must be named in the driver lists, the
   JIT list and each full-runtime C harness in `test/dune` (11 harnesses here),
   so the writer lives in `march_observe.c`.
3. **Errors are JSON too.** The plan's busy reply was the bare text `ERR busy`;
   every reply is now one envelope, so a client parses one format.
4. **No new host field.** The forge client derives the observe path as
   `<socket>.observe`; a configurable `observe_socket` can come with R3's
   commands if a deployment needs it.

## Verification

- `test/test_observe.c` (dune rule `test_observe_runner`): 32 checks over the
  JSON writer (nesting, escaping, non-finite floats, the size limit, an unclosed
  object), every reply validated as JSON by an in-test parser, `PING`, `HELP`, a
  CRLF client, an unknown verb, an over-long line, eight held connections
  followed by a busy ninth and recovery after they close, the idle timeout, mode
  0600, and refusing to remove a regular file or accept an over-long path. Red on
  a perturbed server whose cap check is off by one.
- `test/native/observe_ping.march` with `test/observe_client.c`: an ordinary
  compiled program (no `--hot-reload`) answers `PING` and `HELP` while it runs.
  Red with the `march_run_scheduler` hook removed (both lines read
  `no socket`).
- `forge/test/test_observe_client.ml`: reply parsing (ok, error, malformed,
  wrong protocol) and a round trip to a forked fake server over the local
  transport, which also proves the request goes to `<socket>.observe`.
- All eleven C harnesses that link the full runtime build with the new file;
  `scripts/check-runtime-sources.sh` passes.
