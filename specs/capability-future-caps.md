# Future Capability Types — Design Spec

**Date:** 2026-06-20
**Status:** Planned — not yet implemented
**Depends on:** Capability system Phase 1 & 2 (implemented), body-scan enforcement (implemented)

---

## Overview

This spec covers six capabilities identified as high-value but deferred from the first implementation wave (IO.Spawn, IO.Mut, IO.NetConnect.TLS, IO.Telemetry). They are ranked here from most to least urgency.

All six follow the same implementation pattern as the existing caps:
1. Add to `io_cap_hierarchy` in `lib/typecheck/typecheck.ml`
2. Add builtins to `builtin_cap_table` (except declaration-only caps)
3. Annotate the relevant stdlib module(s) with `needs X`
4. Add 3–4 compiler tests per cap
5. Update `docs/capabilities.md` and `specs/todos.md`

---

## 1. IO.NetListen — TCP/port binding

**Hierarchy:** child of `IO.Network`
**Status:** already in `io_cap_hierarchy`; no builtins wired yet

### Rationale

`IO.NetConnect` (outbound connections) and `IO.NetListen` (inbound binding) are logically different. A proxy or load-balancer needs both; a pure API client only needs outbound. Wiring builtins lets the compiler verify the distinction.

### Builtins to wire

```ocaml
("tcp_listen",       "IO.NetListen");
("tcp_accept",       "IO.NetListen");
("tcp_bind",         "IO.NetListen");
```

### Stdlib annotation

`stdlib/http_server.march` — add `needs IO.NetListen` (already uses these builtins implicitly via the C runtime).

### Tests (3)

1. `tcp_listen` without `needs IO.NetListen` → body-scan warning
2. `needs IO.NetListen` declared → no warning
3. `needs IO.Network` (parent) → no warning

### Notes

`tcp_connect` stays under `IO.NetConnect` (outbound). There is no ambiguity: the caller of `tcp_connect` initiates, the caller of `tcp_listen` binds a server port.

---

## 2. IO.Database — database connections

**Hierarchy:** child of `IO.NetConnect` (declared; declaration-only today)
**Status:** in `io_cap_hierarchy`; no builtins wired; no stdlib module yet

### Rationale

Database connections are a high-value specific case of network IO. Requiring `needs IO.Database` (rather than just `IO.NetConnect`) makes it trivially auditable which modules touch a database. This matters for security reviews, multi-tenant isolation, and least-privilege enforcement in microservices.

Currently `IO.Database` exists in the hierarchy but is declaration-only (identical to IO.Telemetry's current state). The upgrade path is to wire Depot builtins when those are available in the March compiler rather than the Depot library.

### Builtins to wire (when Depot builtins land)

```ocaml
("db_query",         "IO.Database");
("db_exec",          "IO.Database");
("db_begin",         "IO.Database");
("db_commit",        "IO.Database");
("db_rollback",      "IO.Database");
("db_prepare",       "IO.Database");
```

These names are placeholders — the actual builtin names should be confirmed from the Depot runtime when that work proceeds.

### Stdlib annotation

`stdlib/depot/repo.march` — add `needs IO.Database` when the depot stdlib lands.

### Tests (2)

Since Depot builtins are not yet in the compiler, only declaration tests are possible now:

1. `needs IO.Database` parses and typechecks cleanly (no errors)
2. `needs IO.NetConnect` (parent) also covers IO.Database in transitive checks

### Notes

Do not wire IO.Database builtins until the Depot runtime is part of the march stdlib proper. For now it remains declaration-only, identical to IO.Telemetry.

---

## 3. IO.IPC — inter-process communication

**Hierarchy:** leaf under `IO.Process`
**Status:** not in hierarchy yet

### Rationale

Pipes, Unix domain sockets, and POSIX signals are lower-level than network TCP but are real side effects. A sandboxed computation module should be prevented from spawning pipes to child processes or sending signals. `IO.Process` is coarser (covers all process-level ops including `exit` and env vars); `IO.IPC` narrows to the communication-specific subset.

### Proposed hierarchy placement

```
IO.Process
├── IO.IPC    — pipes, unix sockets, POSIX signals
```

### Builtins to wire

```ocaml
("pipe_open",        "IO.IPC");
("pipe_read",        "IO.IPC");
("pipe_write",       "IO.IPC");
("pipe_close",       "IO.IPC");
("unix_socket",      "IO.IPC");
("send_signal",      "IO.IPC");
```

These builtins do not exist yet in the March runtime. This cap is therefore **dependent on IPC runtime work** and cannot be wired until those builtins land. When they do, this is a mechanical add.

### Stdlib annotation

No stdlib module exists for IPC yet. When `stdlib/ipc.march` is written, add `needs IO.IPC`.

### Tests (3, after builtins land)

1. `pipe_open` without `needs IO.IPC` → body-scan warning
2. `needs IO.IPC` → no warning
3. `needs IO.Process` (parent) → no warning

---

## 4. IO.Timer — scheduled callbacks

**Hierarchy:** leaf under `IO` (alongside IO.Clock)
**Status:** not in hierarchy yet

### Rationale

Reading the current time (`IO.Clock`) is passive. Scheduling a future callback or a recurring timer is active — it registers a closure into the runtime scheduler. A module that reads the wall clock should not implicitly be allowed to schedule arbitrary future work. `IO.Timer` enforces this distinction.

### Relationship to IO.Clock

```
IO
├── IO.Clock    — read current time (passive)
└── IO.Timer    — register future callbacks (active)
```

Declaring `needs IO.Timer` does not cover `IO.Clock`; they are siblings. A module that both reads time and schedules work needs both.

### Builtins to wire

```ocaml
("timer_after",      "IO.Timer");
("timer_interval",   "IO.Timer");
("timer_cancel",     "IO.Timer");
("sleep_ms",         "IO.Timer");
```

`sleep_ms` is a blocking yield into the scheduler and fits here rather than `IO.Clock` — it registers a wake-up event, not merely a read.

### Stdlib annotation

`stdlib/duration.march` or a future `stdlib/timer.march` — add `needs IO.Timer`.

### Tests (3, after builtins land)

1. `timer_after` without `needs IO.Timer` → body-scan warning
2. `needs IO.Timer` → no warning
3. `needs IO` (root) → no warning

---

## 5. IO.WebSocket — WebSocket sessions

**Hierarchy:** child of `IO.NetConnect`
**Status:** not in hierarchy yet

### Rationale

WebSocket is a distinct protocol from plain TCP — it requires an HTTP upgrade handshake and has its own framing. A module that speaks WebSocket is categorically different from a module that opens raw TCP connections. Separating the two makes `needs IO.NetConnect` mean "raw TCP/HTTP" and `needs IO.WebSocket` mean "upgraded bidirectional WebSocket sessions".

### Proposed hierarchy placement

```
IO.NetConnect
├── IO.NetConnect.TLS   — encrypted transport ✅ implemented
└── IO.WebSocket        — WebSocket sessions (this cap)
```

A WebSocket session can be TLS-secured; in that case a module would declare both:
```march
needs IO.WebSocket
needs IO.NetConnect.TLS
```

There is no implicit parent-child relationship between the two — they are orthogonal protocol dimensions under `IO.NetConnect`.

### Builtins to wire

```ocaml
("ws_connect",       "IO.WebSocket");
("ws_send",          "IO.WebSocket");
("ws_recv",          "IO.WebSocket");
("ws_close",         "IO.WebSocket");
("ws_upgrade",       "IO.WebSocket");   -- server-side upgrade from HTTP
("ws_ping",          "IO.WebSocket");
```

### Stdlib annotation

`stdlib/websocket.march` — add `needs IO.WebSocket`.

### Tests (3, after builtins land)

1. `ws_connect` without `needs IO.WebSocket` → body-scan warning
2. `needs IO.WebSocket` → no warning
3. `needs IO.NetConnect` (parent) → no warning

---

## 6. IO.Crypto — cryptographic operations

**Hierarchy:** leaf under `IO` (NOT under IO.Random)
**Status:** not in hierarchy yet

### Rationale

The existing `IO.Random` covers the CSPRNG (random bytes and UUIDs). But cryptographic operations — key derivation, HMAC, symmetric encryption, asymmetric signing — are a separate and higher-stakes category. `IO.Crypto` narrows to "this module performs active cryptographic computation" rather than mere entropy reading.

### Why not a child of IO.Random?

Random bytes are an input to cryptography but are not inherently cryptographic. A game that needs `random_bytes` for a seed is not doing cryptography. `IO.Crypto` should be a sibling of `IO.Random`, not a child:

```
IO
├── IO.Random    — entropy source (random_bytes, uuid_v4)
└── IO.Crypto    — cryptographic operations (hash, HMAC, encrypt, sign)
```

### Builtins to wire

The `Crypto` stdlib already calls these underlying builtins; wire them to `IO.Crypto`:

```ocaml
("crypto_sha256",      "IO.Crypto");
("crypto_sha512",      "IO.Crypto");
("crypto_hmac",        "IO.Crypto");
("crypto_hash_pw",     "IO.Crypto");   -- bcrypt/argon2 key derivation
("crypto_verify_pw",   "IO.Crypto");
("crypto_secure_cmp",  "IO.Crypto");
```

`random_bytes` stays under `IO.Random`. `base64_encode`/`base64_decode` are pure transformations (no IO side effects) and should not be under any cap.

### Stdlib annotation

`stdlib/crypto.march` — add `needs IO.Crypto` (currently annotated with `needs IO.Random` only; the crypto operations themselves need the new cap).

### Tests (3, after builtins confirmed)

1. `crypto_sha256` without `needs IO.Crypto` → body-scan warning
2. `needs IO.Crypto` → no warning
3. `needs IO` (root) → no warning

---

## Implementation Order

| Cap | Blocker | Effort | Priority |
|-----|---------|--------|----------|
| IO.NetListen | none — builtins exist in runtime | XS | do first |
| IO.Database | Depot builtins not yet in compiler | XS (when unblocked) | do when Depot lands |
| IO.WebSocket | need to confirm ws_* builtin names in runtime | S | do next |
| IO.Crypto | need to confirm crypto_* builtin names in runtime | S | do with WebSocket |
| IO.Timer | timer/sleep builtins may not exist yet | S | do when builtins land |
| IO.IPC | IPC runtime not yet written | M | do when IPC runtime lands |

### IO.NetListen is immediately actionable

The TCP listen/bind/accept builtins already exist in the runtime. This cap can be wired in an afternoon: add to hierarchy, add 3 entries to `builtin_cap_table`, annotate `stdlib/http_server.march`, write 3 tests.

### Before implementing IO.WebSocket and IO.Crypto

Confirm the actual runtime builtin names by grepping `runtime/march_runtime.c` and `runtime/march_net.c`:

```bash
grep -E "march_ws_|march_crypto_" runtime/*.c runtime/*.h
```

If the names differ from the placeholders above, update the `builtin_cap_table` entries accordingly.

---

## Updated Capability Hierarchy (full picture)

```
IO
├── IO.Console          — stdout/stderr
├── IO.FileSystem
│   ├── IO.FileRead     — read files, list directories
│   └── IO.FileWrite    — write, delete, rename files/dirs
├── IO.Network
│   ├── IO.NetConnect   — outbound TCP, HTTP
│   │   ├── IO.NetConnect.TLS  — encrypted transport ✅
│   │   ├── IO.Database        — database connections (declaration-only) ✅
│   │   └── IO.WebSocket       — WebSocket sessions (this spec)
│   └── IO.NetListen    — bind + listen on a port (this spec)
├── IO.Process          — env vars, child processes, exit
│   └── IO.IPC          — pipes, unix sockets, signals (this spec)
├── IO.Clock            — read wall clock, monotonic time
├── IO.Random           — entropy (random_bytes, uuid_v4)
├── IO.Crypto           — cryptographic operations (this spec)
├── IO.Spawn            — task spawning ✅
├── IO.Mut              — shared mutable state (Vault) ✅
├── IO.Timer            — scheduled callbacks (this spec)
└── IO.Telemetry        — observability annotation ✅
```
