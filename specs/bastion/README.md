# Bastion: Web Framework for March

**Status**: Draft | **Version**: 0.1
**Author**: Chase Gilliam | **Date**: March 2026
**Ecosystem**: March (language), Forge (build tool), Depot (Postgres driver)

---

Bastion is a full-stack web framework for the March programming language. It provides server-side rendering, typed WASM islands for client-side interactivity, pattern-matched routing, typed middleware pipelines, and first-class WebSocket support via Channels.

Bastion occupies a similar space to Phoenix in the Elixir ecosystem — opinionated enough to be productive out of the box, but modular enough to stay out of the developer's way. Its key differentiator is **full-stack type safety**: the same March types, modules, and functions compile to both the server (via OCaml 5.3.0) and the browser (via WASM), enabling shared code across the entire stack.

---

## Design Principles

1. **Performance is first-class.** Sub-millisecond routing, compiled templates, zero-copy IO lists, efficient WASM bundles.
2. **Types everywhere.** Templates are type-checked at compile time. Middleware transformations are tracked in the type system.
3. **Pattern matching over DSLs.** Routes, error handling, and middleware composition feel like idiomatic March.
4. **The actor model stays under the hood.** Developers interact with `conn` and handler functions.
5. **Islands, not SPAs.** Server-rendered HTML with targeted WASM islands for interactivity. Ship less code to the client.

---

## Table of Contents

### Core Framework

| Document | Description |
|---|---|
| [architecture.md](architecture.md) | High-level request flow, server-side and client-side process models, design principles, ecosystem position |
| [routing.md](routing.md) | Pattern-matched routing via function heads, route delegation, compile-time route optimization |
| [middleware.md](middleware.md) | Typed middleware pipeline, conn type states, built-in middleware, scoped pipelines |
| [templates.md](templates.md) | `~H` sigil, components as functions, compile-time type checking, XSS prevention |
| [error-handling.md](error-handling.md) | HTTP error handling, custom error pages, WebSocket/island crash recovery, dev error overlay |

### Client-Side and Real-Time

| Document | Description |
|---|---|
| [wasm-islands.md](wasm-islands.md) | Island architecture, declaring islands, SSR + hydration, island-to-island and island-to-server communication, WASM compilation pipeline |
| [channels.md](channels.md) | WebSocket channel handlers, client-side channel usage in WASM islands, channel testing |
| [js-interop.md](js-interop.md) | FFI layer (WASM → JS), built-in Cmd abstractions, JS dependencies and bundling, JS → WASM JSON messages |

### Authentication and Security

| Document | Description |
|---|---|
| [auth.md](auth.md) | Session system, auth generators (session/token/OAuth/magic_link), generated auth middleware |
| [security.md](security.md) | CSRF protection, security headers, CSP, CORS, rate limiting, request size limits, HTTPS redirect |

### Storage and Caching

| Document | Description |
|---|---|
| [vault.md](vault.md) | In-memory key-value store (ETS analogue), table types, concurrency model, TTL, per-node semantics |
| [caching.md](caching.md) | HTTP ETags, response caching, fragment caching, cache invalidation, static asset cache-busting |
| [depot-integration.md](depot-integration.md) | Pool middleware, context modules, migrations, `--no-db` flag, integration testing |

### Styling and Assets

| Document | Description |
|---|---|
| [templates.md](templates.md) | *(see above)* |
| [css-styling.md](css-styling.md) | Global stylesheets, scoped island CSS, CSS variables for theming, no built-in CSS build step |
| [static-files.md](static-files.md) | Built-in static server, asset directory structure, WASM bundle management, content-hash URLs |

### Operations

| Document | Description |
|---|---|
| [logging-observability.md](logging-observability.md) | Structured logging, request ID tracing, request logger middleware, OpenTelemetry integration, metrics |
| [uploads.md](uploads.md) | Streaming multipart parser, typed middleware integration, streaming to external storage, cleanup |
| [deployment.md](deployment.md) | Build artifacts, single binary option, runtime configuration, environment switching, health checks, graceful shutdown |

### Project Setup and Developer Experience

| Document | Description |
|---|---|
| [project-structure.md](project-structure.md) | Directory layout from `forge new`, application entry point, complete example application |
| [configuration.md](configuration.md) | Config files, compile-time vs runtime config, forge.toml |
| [generators.md](generators.md) | All `forge gen.*` commands for handlers, contexts, auth, channels, islands, migrations |
| [dev-experience.md](dev-experience.md) | Live reload, dev error overlay, dev-only middleware, `forge dev` dashboard |
| [testing.md](testing.md) | HTTP request testing, conn builder API, middleware testing, island testing, depot sandbox testing |
| [performance.md](performance.md) | Design decisions for performance, benchmarking targets, scalability model |

### Planning

| Document | Description |
|---|---|
| [open-questions.md](open-questions.md) | Open design questions, explicit v1 exclusions, future work (post-v1 roadmap) |
