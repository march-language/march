# Bastion: Structured Logging with Request Correlation IDs

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Every request is assigned a unique correlation ID at the moment it enters the system. That ID propagates automatically through every log line, Depot query, and actor message spawned on behalf of that request — without the application explicitly threading it through function arguments. When something goes wrong, `grep request_id=a1b2c3d4` in your log aggregator gives a complete, ordered trace of everything that happened for that request, across processes and nodes.

This goes beyond what is described in [logging-observability.md](logging-observability.md) (which covers log format and the request logger middleware). This document specifies the *propagation mechanism* — how the correlation ID travels through asynchronous, multi-process, multi-node code without manual plumbing.

---

## Correlation ID Lifecycle

```
Inbound request
    │  X-Request-ID header? → use it
    │  none?                → generate UUID v7
    ▼
Bastion.Middleware.CorrelationID assigns to conn
    │
    ├── stored in conn.assigns.request_id
    ├── echoed back in X-Request-ID response header
    ├── bound into the current process's Logger metadata
    └── stored in the current process's dictionary for actor spawn propagation
    │
    ▼
Every log call in this process includes request_id automatically
    │
    ├── Handler spawns a background actor
    │     → correlation ID is forwarded in the spawn metadata
    │     → actor binds it into its own Logger metadata on start
    │
    ├── Handler makes a Depot query
    │     → correlation ID attached to the query metadata
    │     → Depot logs "slow query" / "query error" with the request_id
    │
    └── Handler renders a template
          → template rendering logged with request_id
```

---

## Setup

```march
fn call(conn) do
  conn
  |> Bastion.Middleware.CorrelationID.assign()   # step 1: assign/generate ID
  |> Bastion.Middleware.Logger.log_request()      # step 2: start request log
  |> parse_body()
  |> load_session()
  |> MyApp.Router.route()
end
```

That is the only change. No further plumbing.

---

## Process Dictionary Propagation

The correlation ID is stored in the process dictionary of the request handler actor under the key `:bastion_request_id`. The logger backend reads it automatically when formatting log lines.

```march
mod Bastion.Middleware.CorrelationID do
  fn assign(conn: Conn) -> Conn do
    request_id = case get_req_header(conn, "x-request-id") do
      Some(id) when String.length(id) <= 200 -> id
      _ -> UUID.v7()
    end
    Process.put(:bastion_request_id, request_id)
    conn
    |> assign(:request_id, request_id)
    |> put_resp_header("x-request-id", request_id)
  end
end
```

---

## Logger Metadata Injection

The March logger backend reads `:bastion_request_id` from the calling process dictionary on every log call and includes it in the emitted log record automatically:

```march
mod Bastion.Logger do
  fn info(message: String, metadata: Map(String, Any)) -> :ok do
    request_id = Process.get(:bastion_request_id)
    base = case request_id do
      Some(id) -> Map.put(metadata, "request_id", id)
      None -> metadata
    end
    Logger.log(:info, message, base)
  end
end
```

The application never passes `request_id` manually:

```march
fn show(conn, id) do
  # request_id is NOT passed here — it comes from the process dictionary
  Bastion.Logger.info("Fetching user", %{"user_id": id})
  user = MyApp.Users.get(conn.assigns.db, id)
  conn |> json(user)
end
```

Log output:

```json
{"level":"info","message":"Fetching user","request_id":"01925a9e-...","user_id":"42","timestamp":"..."}
```

---

## Depot Query Correlation

Depot queries automatically include the correlation ID in their log output:

```march
mod Depot do
  fn query(pool: Pool, sql: String, params: List(Any)) -> List(Map(String, Any)) do
    request_id = Process.get(:bastion_request_id)
    start = System.monotonic_time(:microsecond)
    result = execute_query(pool, sql, params)
    duration = System.monotonic_time(:microsecond) - start

    Bastion.Logger.debug("Depot query", %{
      "sql": String.slice(sql, 0, 200),
      "duration_us": duration,
      "rows": List.length(result),
      "request_id": Option.unwrap_or(request_id, "")
    })

    result
  end
end
```

Slow query logs, query errors, and pool timeout warnings all carry the same `request_id`, making it trivial to correlate a slow DB query with the specific request that caused it.

---

## Actor Spawn Propagation

When a request handler spawns a background actor, the correlation ID is forwarded automatically. March's actor spawn mechanism passes the spawning process's `:bastion_request_id` to the new actor on startup:

```march
mod Bastion.Actor do
  fn spawn_linked(module: Atom, args: Any) -> Pid do
    request_id = Process.get(:bastion_request_id)
    Actor.spawn_linked(module, args, metadata: %{bastion_request_id: request_id})
  end
end

# In the actor runtime (internal):
fn actor_init(module, args, metadata) do
  case Map.get(metadata, :bastion_request_id) do
    Some(id) -> Process.put(:bastion_request_id, id)
    None -> :ok
  end
  module.init(args)
end
```

Now the background actor's logs carry the same `request_id` as the request that spawned it:

```march
fn create(conn) do
  case MyApp.Orders.create(conn.assigns.db, parse_params(conn)) do
    Ok(order) ->
      # Spawn an async worker — correlation ID propagates automatically
      Bastion.Actor.spawn_linked(MyApp.EmailWorker, %{
        to: order.user.email,
        order_id: order.id
      })
      conn |> json(order)
    Error(cs) ->
      conn |> send_resp(422, Depot.Changeset.errors(cs))
  end
end

mod MyApp.EmailWorker do
  fn init(%{to: to, order_id: order_id}) do
    # This log line carries the same request_id as the HTTP request
    Bastion.Logger.info("Sending order confirmation email", %{
      "to": to,
      "order_id": order_id
    })
    Mailer.deliver(order_confirmation_email(to, order_id))
    :stop
  end
end
```

Log output (showing the propagated `request_id`):

```json
{"level":"info","message":"POST /orders — 200 in 12ms","request_id":"01925a9e-...","status":200}
{"level":"info","message":"Sending order confirmation email","request_id":"01925a9e-...","to":"alice@example.com","order_id":"ord_789"}
```

---

## Cross-Node Propagation

When a PubSub broadcast or actor message crosses a node boundary, Bastion includes the correlation ID in the message envelope:

```march
mod Bastion.PubSub do
  fn broadcast(pubsub: Atom, topic: String, message: Any) -> :ok do
    request_id = Process.get(:bastion_request_id)
    envelope = %{
      payload: message,
      correlation_id: request_id,
      sent_at: DateTime.now()
    }
    broadcast_envelope(pubsub, topic, envelope)
  end
end

# On the receiving node, the correlation ID is bound before handle_msg:
fn deliver_to_subscriber(subscriber: Pid, envelope: Envelope) do
  case envelope.correlation_id do
    Some(id) ->
      Actor.send(subscriber, {:pubsub_with_correlation, id, envelope.payload})
    None ->
      Actor.send(subscriber, {:pubsub_message, envelope.payload})
  end
end
```

Subscribers that use `Bastion.Channel` or `Bastion.Actor` have the correlation ID bound automatically when the message is delivered.

---

## Log Format

The correlation ID appears in both human-readable (dev) and JSON (prod) formats:

**Development:**
```
14:23:01.234 [info] request_id=01925a9e POST /orders — 200 in 12ms
14:23:01.237 [info] request_id=01925a9e Sending order confirmation email to=alice@example.com order_id=ord_789
14:23:01.289 [info] request_id=01925a9e Depot query sql="INSERT INTO orders..." duration_us=45
```

**Production (JSON, one line each):**
```json
{"level":"info","request_id":"01925a9e-...","message":"POST /orders — 200 in 12ms","status":200,"duration_us":12453}
{"level":"info","request_id":"01925a9e-...","message":"Sending order confirmation email","to":"alice@example.com","order_id":"ord_789"}
{"level":"info","request_id":"01925a9e-...","message":"Depot query","sql":"INSERT INTO orders...","duration_us":45,"rows":1}
```

---

## Integration with External Tracing

The correlation ID is designed to compose with OpenTelemetry trace IDs. When `bastion_telemetry` is configured, the correlation ID is used as the OpenTelemetry `trace.id` — so all Bastion log lines and all OTel spans share the same identifier and are linkable in tools like Jaeger, Honeycomb, and Datadog APM.

See [telemetry.md](telemetry.md) for the OpenTelemetry integration details.

---

## Open Questions

- Should the correlation ID be a UUID v7 (time-ordered, 128-bit) or a shorter format (e.g., 16 hex chars)? UUID v7 is great for sorting and external compatibility; a shorter format is friendlier for `grep` and log tailing.
- Should `Process.get(:bastion_request_id)` be replaced with a structured "Logger context" API that supports multiple keys (e.g., `user_id`, `tenant_id`, `request_id`) — similar to `Logger.metadata/1` in Elixir?
- When an actor outlives the request (e.g., a long-running background job), should the correlation ID stay bound indefinitely or be cleared after the initial request context ends?
