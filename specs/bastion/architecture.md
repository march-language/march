# Bastion — Web Framework Architecture

**Status:** Design phase. The Islands library (`islands/`) is the first shipped piece.

## Overview

Bastion is March's full-stack web framework. It consists of three layers:

```
┌─────────────────────────────────────────────────────────┐
│  Bastion (router, templates, sessions, plug pipeline)    │
├──────────────────────────┬──────────────────────────────┤
│  HttpServer (stdlib)     │  Islands library             │
│  Plug pipeline / Conn    │  WASM island hydration       │
├──────────────────────────┴──────────────────────────────┤
│  March runtime (actors, scheduler, HTTP, TLS)            │
└─────────────────────────────────────────────────────────┘
```

The framework is deliberately separated into independent libraries so each piece can be used standalone:

| Library | Status | Description |
|---------|--------|-------------|
| `HttpServer` (stdlib) | ✅ Shipped | Low-level Conn/plug pipeline |
| `Islands` | ✅ Shipped | WASM island model (this work) |
| `Bastion.Router` | Planned | Macro-free pattern-match router |
| `Bastion.Template` | Planned | Server-side HTML templates |
| `Bastion.Session` | Planned | Cookie-backed session management |
| `Bastion.Auth` | Planned | Pluggable auth strategies |

## Islands Library (`islands/`)

The Islands library is a standalone forge library (`forge new islands --lib`). It does not depend on Bastion; any HTTP framework can use it.

See [`wasm-islands.md`](wasm-islands.md) for the detailed design.

### What it ships today

- `Islands.wrap` / `Islands.wrap_eager` / `Islands.client_only` — server-side HTML wrappers with hydration markers
- `Islands.bootstrap_script` — generate the `<script>` tag for the JS runtime
- `Islands.preload_hint` — `<link rel="modulepreload">` hints for WASM files
- `Islands.Registry` — island descriptor registry for server startup
- `interface Island(s)` — the typeclass for island modules to implement
- `priv/js/march-islands.js` — client-side actor-per-island bootstrap
- Configurable per-island hydration strategies: `Eager | Lazy | OnIdle | OnInteraction`

### WASM compilation status

The WASM target is Tier 1 (code complete; awaiting wasi-sdk + wasmtime for end-to-end test). The browser target (Tier 4, `wasm32-unknown-unknown` + JS glue) is not yet available. The Islands library is architecturally complete; the WASM loading in `march-islands.js` is a well-documented stub that plugs in when Tier 4 lands.

## Request lifecycle (future)

```
Browser request
    │
    ▼
Bastion.Router (match method + path)
    │
    ▼
Plug pipeline (auth, session, CSRF, …)
    │
    ▼
Handler fn (Conn → Conn)
    │  calls Counter.render(state)
    │  calls Islands.wrap("Counter", Eager, state_json, html)
    │
    ▼
HttpServer.send_resp(conn, 200, full_html)
    │
    ▼
Browser receives HTML with hydration markers
    │
    ▼
march-islands.js bootstraps → actor per island → WASM loaded
```

## Actor model

Each island on the client runs as an actor. The JS runtime is a lightweight cooperative actor scheduler built on `queueMicrotask`. When WASM threads (Tier 3) land, the scheduler can be upgraded to use Web Workers while preserving the programming model.

Server-side, each request handler runs inside the March actor scheduler. Islands can be backed by server actors for live updates (via WebSocket); the client actor sends a message to the server actor's `Pid` encoded as a URL-safe token in the hydration state.

## Data flow for a live island (future)

```
Client island actor
    │  user event → send({ tag: "Increment" })
    ▼
WASM update(state, msg) → new state
WASM render(new_state) → HTML
patch DOM
    │
    │  if online: also forward to server via WS
    ▼
Server Counter actor
    on Increment -> { state with count = state.count + 1 }
    │
    ▼
Broadcast to all connected clients watching this counter
```
