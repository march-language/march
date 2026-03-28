# Bastion: Idempotency Keys as Middleware

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

POST and PUT endpoints can accept an `Idempotency-Key` header. The first time a request arrives with a given key, it executes normally and the response is cached in Vault. If an identical request arrives again with the same key — due to a client retry, network hiccup, or double-submit — the cached response is replayed verbatim without re-executing the handler. No duplicate charges. No duplicate emails. No duplicate records.

This is Stripe's idempotency key pattern, implemented as framework middleware with zero application-handler changes.

---

## The Problem

Without idempotency keys, a mobile client that loses its connection after sending a payment request does not know whether the server received it. The safe thing to do is retry — but that risks double-charging. Idempotency keys solve this: the client generates a unique key per logical operation and sends it with every retry. The server ensures the operation happens at most once.

---

## Enabling the Middleware

```march
# In your endpoint pipeline
fn call(conn) do
  conn
  |> parse_body()
  |> load_session()
  |> Bastion.Middleware.Idempotency.protect(
    vault_table: :idempotency_cache,
    ttl: 24 * 60 * 60 * 1000,     # cache for 24 hours (default)
    methods: [:post, :put],        # which methods to apply to (default)
    scope: fn conn ->              # optional: scope key by user to prevent cross-user replay
      conn.assigns[:current_user]
      |> Option.map(fn u -> u.id end)
      |> Option.unwrap_or("anonymous")
    end
  )
  |> MyApp.Router.route()
end
```

That is the only change needed. Application handlers are unmodified.

---

## Request Flow

```
Client → POST /payments  Idempotency-Key: client-uuid-abc-123
              │
              ▼
Bastion.Middleware.Idempotency
  ├── Key present?  NO  → pass through (no idempotency enforcement)
  ├── Key present?  YES
  │     ├── Cache hit?   YES → return cached response, skip handler
  │     └── Cache hit?   NO
  │           ├── Mark key as IN_PROGRESS in Vault
  │           ├── Call handler
  │           ├── Store response in Vault (status, headers, body)
  │           └── Return response to client
  │
  └── Key present?  YES, but IN_PROGRESS (concurrent duplicate)
        └── Wait up to 5s for original to complete, then replay
```

---

## API

```march
mod Bastion.Middleware.Idempotency do
  fn protect(conn: Conn, opts: IdempotencyOpts) -> Conn

  type IdempotencyOpts = %{
    vault_table: Atom,           # Vault table for response cache
    ttl: Int,                    # cache TTL in milliseconds (default: 86_400_000 = 24h)
    methods: List(Atom),         # HTTP methods to protect (default: [:post, :put])
    scope: fn(Conn) -> String,   # optional: key scoping function (default: no scope)
    concurrent_timeout: Int      # ms to wait when a duplicate is in-progress (default: 5000)
  }
end
```

---

## Response Headers

Bastion adds headers to help clients distinguish original responses from replays:

```
# Original (first) response
HTTP/1.1 201 Created
Idempotency-Key: client-uuid-abc-123
X-Idempotent-Replayed: false

# Replayed response
HTTP/1.1 201 Created
Idempotency-Key: client-uuid-abc-123
X-Idempotent-Replayed: true
X-Original-Request-At: 2026-03-27T14:23:01Z
```

Clients can inspect `X-Idempotent-Replayed` to confirm they received a cached response.

---

## Vault Table Setup

```march
mod MyApp do
  fn start() do
    Vault.new(:idempotency_cache, %{
      type: :set,
      read_concurrency: true,
      write_concurrency: false    # writes need ordering guarantees
    })

    # ... rest of supervision tree
  end
end
```

---

## Scope: Per-User Key Isolation

Without scoping, any client that knows a valid `Idempotency-Key` can replay another client's response. Scoping a key to the authenticated user prevents cross-user replay attacks:

```march
fn call(conn) do
  conn
  |> load_session()
  |> MyApp.Auth.load_current_user()
  |> Bastion.Middleware.Idempotency.protect(
    vault_table: :idempotency_cache,
    scope: fn conn ->
      case conn.assigns.current_user do
        Some(user) -> "user:#{user.id}"
        None -> "anonymous"
      end
    end
  )
  |> MyApp.Router.route()
end
```

The Vault key becomes `"user:42:client-uuid-abc-123"` rather than just `"client-uuid-abc-123"`.

---

## Concurrent Duplicates

If two requests with the same idempotency key arrive simultaneously (e.g., two retries from different app servers before the first completes), the middleware handles the race:

1. The first request sets the key to `IN_PROGRESS` atomically via `Vault.put_new`.
2. The second request finds `IN_PROGRESS` and polls (with backoff) for up to `concurrent_timeout` ms.
3. Once the first request completes and stores its response, the second request picks up the cached response and replays it.
4. If `concurrent_timeout` elapses before the original completes, the second request returns `409 Conflict` with a `Retry-After` header.

```march
type IdempotencyState
  = InProgress(%{started_at: DateTime})
  | Completed(%{
    status: Int,
    headers: List({String, String}),
    body: String,
    completed_at: DateTime
  })
```

---

## Per-Route Configuration

Override the middleware defaults for specific routes:

```march
fn route(conn, :post, ["payments"]) do
  conn
  # Payments cache for 7 days (not the default 24h)
  |> Bastion.Middleware.Idempotency.protect(
    vault_table: :payment_idempotency,
    ttl: 7 * 24 * 60 * 60 * 1000
  )
  |> MyApp.PaymentHandler.create(conn)
end

fn route(conn, :post, ["emails", "send"]) do
  conn
  # Email sends: 1-hour idempotency window
  |> Bastion.Middleware.Idempotency.protect(
    vault_table: :idempotency_cache,
    ttl: 60 * 60 * 1000
  )
  |> MyApp.EmailHandler.send(conn)
end
```

---

## Opting Out

Routes that genuinely need to execute on every request (e.g., a non-idempotent counter increment that is intentionally additive) opt out by not including the middleware. The middleware is not applied globally — it is applied explicitly per pipeline or per route.

---

## Error Response Caching

Error responses are also cached. If a handler returns 422 (validation error) on the first request, replays also return 422 with the same body. This prevents a confused client from retrying a request that will never succeed:

```march
# First request: validation error
POST /payments  Idempotency-Key: key-123
→ 422 {"error": "amount must be positive"}

# Retry: same validation error replayed
POST /payments  Idempotency-Key: key-123
→ 422 {"error": "amount must be positive"}
X-Idempotent-Replayed: true
```

5xx responses are intentionally **not** cached — a server error may be transient, and the client should retry.

---

## Telemetry

The idempotency middleware emits telemetry events:

```
[:bastion, :idempotency, :cache_hit]    — replayed a cached response
[:bastion, :idempotency, :cache_miss]   — first request, will execute handler
[:bastion, :idempotency, :in_progress]  — concurrent duplicate, waiting
[:bastion, :idempotency, :conflict]     — concurrent_timeout elapsed, returned 409
```

These feed into the request waterfall in the dev dashboard and any attached telemetry handlers.

---

## Open Questions

- Should idempotency keys be stored in Depot (persistent, survives restarts) rather than Vault (in-memory, lost on restart)? Vault is simpler and faster but a restart within the TTL window could allow a duplicate. A Depot-backed option would add a DB round-trip on every idempotency-protected request.
- Should there be a way to explicitly invalidate an idempotency key (e.g., if the original request is reversed/refunded)?
- How should idempotency interact with streaming responses?
