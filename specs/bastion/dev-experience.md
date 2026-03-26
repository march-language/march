# Bastion: Developer Experience

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Live Reload

`forge dev` provides automatic code reloading during development:

```bash
forge dev
# ✓ Compiling my_app (0.34s)
# ✓ Compiling 2 WASM islands (0.89s)
# ✓ Bastion running at http://localhost:4000
# ✓ Live reload enabled — watching src/, priv/static/
```

When files change:

- **Server code changes** (`.march` files in `src/`): Recompile and hot-reload the server module. Active WebSocket connections are preserved — only new HTTP requests use the updated code.
- **Template changes** (files with `~H` sigils): Recompile the affected template function and trigger a browser refresh via a WebSocket reload channel.
- **Island changes** (`.march` files in `src/**/islands/`): Recompile the affected island to WASM, push the new bundle to the browser, and replace the running island. Island state is reset on reload.
- **Static asset changes** (files in `priv/static/`): Trigger a browser refresh. No server restart needed.
- **CSS changes**: If using an external CSS tool via `forge.toml` hooks, the hook re-runs and Bastion refreshes the browser.

---

## Dev Error Overlay

When a request handler crashes in development, Bastion renders a rich error page instead of a generic 500. The error overlay shows:

- The exception type and message
- A full stack trace with source code context (the relevant lines of March code highlighted)
- The conn state at the time of the crash (method, path, headers, params, assigns)
- The middleware pipeline stage where the error occurred
- Timing information (how long each middleware step took before the crash)

```march
# Automatically enabled in dev, disabled in prod
# config/dev.march
fn error_handler() do
  Bastion.Dev.ErrorOverlay  # rich HTML error page
end

# config/prod.march
fn error_handler() do
  MyApp.ErrorHandler         # custom production error handler
end
```

The error overlay is styled inline (no external CSS dependency) and includes a copy-to-clipboard button for the stack trace. It is **never** shown in production — Bastion verifies the environment before rendering it.

---

## Dev-Only Middleware

Bastion includes middleware that's useful in development but disabled in production:

```march
mod Bastion.Dev do
  # Logs detailed timing for every middleware step and DB query
  fn request_timer(conn: Conn) -> Conn
  # Output: parse_body: 0.04ms | load_session: 0.12ms | require_auth: 0.08ms |
  #         depot.query: 0.89ms | template.render: 0.23ms | total: 1.36ms

  # Adds a response header with timing breakdown
  fn server_timing(conn: Conn) -> Conn
  # Adds: Server-Timing: middleware;dur=0.24, db;dur=0.89, render;dur=0.23

  # Logs the full conn state (headers, params, assigns) for debugging
  fn conn_inspector(conn: Conn) -> Conn
end
```

These are included in the generated dev endpoint:

```march
fn call(conn) do
  conn
  |> maybe_dev_middleware()
  |> Bastion.Security.Headers.defaults()
  # ... rest of pipeline

  fn maybe_dev_middleware(conn) do
    case Bastion.env() do
      :dev ->
        conn
        |> Bastion.Dev.request_timer()
        |> Bastion.Dev.server_timing()
      _ ->
        conn
    end
  end
end
```

---

## `forge dev` Dashboard

When running `forge dev`, the terminal displays a live dashboard showing:

```
┌─ Bastion Dev Server ──────────────────────────────────────────────┐
│ http://localhost:4000                                              │
│                                                                    │
│ Requests: 142 total | 0 errors | avg 1.8ms                       │
│ WebSocket: 3 connections                                           │
│ Islands:   2 compiled (search_bar: 42KB, chat_widget: 58KB)      │
│ Vault:     3 tables (response_cache: 24 entries, 18KB)            │
│                                                                    │
│ Last reload: src/my_app/router.march (0.12s ago)                  │
└───────────────────────────────────────────────────────────────────┘
```
