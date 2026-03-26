# Bastion: Architecture and Process Model

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## High-Level Request Flow

```
Client Request
    │
    ▼
┌─────────────────────┐
│   Bastion.Endpoint   │  ← Accepts TCP/TLS connections
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Typed Middleware    │  ← Pipeline: Conn(Raw) → Conn(Parsed) → Conn(Authenticated) → ...
│  Pipeline           │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Pattern-Matched    │  ← fn route(conn, :get, ["users", id]) do ... end
│  Router             │
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Handler Function   │  ← Business logic, DB queries via Depot, template rendering
└─────────┬───────────┘
          │
          ▼
┌─────────────────────┐
│  Response           │  ← HTML (with WASM island markers) or JSON
└─────────────────────┘
```

---

## Server-Side Process Model

Bastion uses **one actor (green thread) per connected user**, matching the proven LiveView model from Phoenix/Erlang.

For standard HTTP request/response cycles, a green thread is spawned to handle the request and terminates when the response is sent. For WebSocket connections (Channels), a persistent actor is maintained for the lifetime of the connection, supervised by Bastion's supervision tree.

```
Bastion.Supervisor
├── Bastion.Endpoint (accepts connections)
├── Bastion.ChannelSupervisor
│   ├── Connection Actor (user A) — holds all component state for user A's page
│   ├── Connection Actor (user B)
│   └── ...
└── Bastion.PubSub (topic-based message broadcast)
```

This is deliberately NOT one actor per component per user on the server. A complex page with 30 interactive components and 10,000 concurrent users creates 10,000 server-side actors (one per connection), not 300,000. The WASM islands handle per-component state on the client.

---

## Client-Side Process Model (WASM Islands)

On the client, each WASM island is an independent actor with its own state and typed mailbox. Islands communicate with each other via message passing and with the server via the WebSocket channel.

```
Browser
├── Island: SearchBar (actor, local state: query, suggestions)
├── Island: ChatWidget (actor, local state: messages, input)
├── Island: NotificationBell (actor, local state: count, dropdown_open)
└── Channel (WebSocket connection to server)
```

Each island actor runs in the WASM runtime, manages its own DOM subtree, and can:

- Hold local state without server round-trips
- Send messages to other islands on the page
- Send messages to the server via the Channel
- Receive pushed updates from the server

---

## Design Principles

1. **Performance is first-class.** Sub-millisecond routing, compiled templates, zero-copy IO lists, efficient WASM bundles. Bastion should compete with Rust frameworks on throughput.
2. **Types everywhere.** Templates are type-checked at compile time. Middleware transformations are tracked in the type system. Shared client/server modules use the same type definitions.
3. **Pattern matching over DSLs.** March has powerful pattern matching — use it. Routes, error handling, and middleware composition should feel like idiomatic March, not a framework-specific language.
4. **The actor model stays under the hood.** Developers interact with `conn` and handler functions. Supervision, process management, and green thread scheduling happen transparently.
5. **Islands, not SPAs.** The default rendering model is server-rendered HTML with targeted WASM islands for interactivity. Ship less code to the client.

---

## Ecosystem Position

```
March          — the language (statically-typed, functional, ML/Elixir hybrid)
Forge          — the build tool (compilation, dependencies, generators)
Depot          — the PostgreSQL driver
Bastion        — the web framework (this document)
Channels       — WebSocket pub/sub (being implemented separately, integrated into Bastion)
```
