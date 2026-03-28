# Bastion: Request/Response Lifecycle Hooks and Structured Telemetry

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

Every pipeline stage emits structured telemetry events: router match, middleware execution, controller dispatch, template render, Depot query, and channel message handling. Events flow into a Vault-backed in-memory aggregator that powers the dev dashboard's request waterfall visualization. In production, events can be forwarded to OpenTelemetry, Prometheus, Datadog, or any custom handler.

This is "batteries included" observability — no instrumentation code in application handlers.

---

## Event Model

Every telemetry event is a record with a name, measurements, and metadata:

```march
type TelemetryEvent = %{
  name: List(Atom),           # hierarchical name, e.g. [:bastion, :router, :dispatch]
  measurements: Map(Atom, Int), # numeric values: duration_us, byte_count, etc.
  metadata: Map(Atom, Any)    # contextual data: conn, query, template name, etc.
}
```

Events follow a start/stop convention. The framework emits a `start` event before the operation and a `stop` event after:

```
[:bastion, :endpoint, :start]   — request arrives, before any pipeline processing
[:bastion, :endpoint, :stop]    — response sent, full request lifecycle complete
[:bastion, :router, :start]     — route matching begins
[:bastion, :router, :stop]      — route matched (or 404)
[:bastion, :handler, :start]    — handler function called
[:bastion, :handler, :stop]     — handler function returned
[:bastion, :template, :start]   — ~H rendering begins
[:bastion, :template, :stop]    — ~H rendering complete
[:bastion, :depot, :query, :start]  — database query submitted
[:bastion, :depot, :query, :stop]   — database query returned
[:bastion, :channel, :message, :start]  — channel handle_in called
[:bastion, :channel, :message, :stop]   — channel handle_in returned
```

Exception events fire instead of `:stop` when the stage raises:

```
[:bastion, :endpoint, :exception]
[:bastion, :handler, :exception]
[:bastion, :depot, :query, :exception]
```

---

## Attaching Handlers

```march
mod Bastion.Telemetry do
  # Attach a handler function to one or more event names
  fn attach(
    handler_id: String,
    events: List(List(Atom)),
    handler: fn(TelemetryEvent) -> :ok
  ) -> :ok

  # Detach by handler_id
  fn detach(handler_id: String) -> :ok

  # Emit an event (used internally by the framework; available for app code too)
  fn execute(name: List(Atom), measurements: Map(Atom, Int), metadata: Map(Atom, Any)) -> :ok
end
```

---

## Built-In Aggregator (Vault-Backed)

Bastion ships a zero-config in-memory aggregator that stores the last N requests in a Vault table. It powers the dev dashboard and can be queried programmatically:

```march
mod Bastion.Telemetry.Aggregator do
  # Start the aggregator (called automatically at app startup)
  fn start(opts: AggregatorOpts) -> :ok
  # opts: %{buffer_size: 500, vault_table: :telemetry_events}

  # Query recent requests
  fn recent_requests(limit: Int) -> List(RequestSummary)

  # Get the waterfall breakdown for a specific request
  fn request_waterfall(request_id: String) -> Option(WaterfallData)

  # Live counters (reset on app restart)
  fn counters() -> %{
    total_requests: Int,
    active_requests: Int,
    error_count: Int,
    avg_duration_us: Int
  }
end

type WaterfallData = %{
  request_id: String,
  total_duration_us: Int,
  stages: List(WaterfallStage)
}

type WaterfallStage = %{
  name: String,             # "router", "auth middleware", "handler", "template render", "depot query"
  start_offset_us: Int,     # microseconds from request start
  duration_us: Int,
  metadata: Map(Atom, Any)
}
```

---

## Dev Dashboard: Request Waterfall

The dev dashboard at `/__bastion__/requests` shows a live waterfall view of recent requests:

```
GET /users/42  — 200  — 3.4ms  [2026-03-27 14:23:01]
  ├── router match          0.1ms  ████
  ├── session load          0.2ms  ████████
  ├── auth middleware        0.1ms  ████
  ├── handler dispatch      0.1ms  ████
  ├── depot query [×2]      1.8ms  ████████████████████████████████████
  │     SELECT users WHERE id=$1   0.9ms
  │     SELECT posts WHERE user=$1 0.9ms
  ├── template render       0.8ms  ████████████████
  └── response send         0.3ms  ████████████
```

Each row is clickable — it expands to show full metadata for that stage (SQL query text, template path, middleware name, etc.).

---

## Custom Application Events

Application code can emit telemetry events for custom operations:

```march
fn send_welcome_email(user) do
  Bastion.Telemetry.execute(
    [:my_app, :email, :start],
    %{},
    %{to: user.email, template: "welcome"}
  )

  start_time = System.monotonic_time(:microsecond)
  result = Mailer.deliver(welcome_email(user))
  duration = System.monotonic_time(:microsecond) - start_time

  Bastion.Telemetry.execute(
    [:my_app, :email, :stop],
    %{duration_us: duration},
    %{to: user.email, template: "welcome", result: result}
  )

  result
end
```

Custom events automatically appear in the dev dashboard waterfall if they occur during a request.

---

## Production Handler: OpenTelemetry

```march
mod MyApp.Telemetry do
  fn setup() do
    Bastion.Telemetry.attach(
      "otel-handler",
      [
        [:bastion, :endpoint, :stop],
        [:bastion, :handler, :stop],
        [:bastion, :depot, :query, :stop]
      ],
      fn event ->
        span_name = event.name |> List.join(".")
        OpenTelemetry.record_span(span_name, event.measurements, event.metadata)
      end
    )
  end
end
```

---

## Production Handler: Prometheus Metrics

```march
mod MyApp.Telemetry do
  fn setup() do
    Bastion.Telemetry.attach(
      "prometheus-handler",
      [[:bastion, :endpoint, :stop]],
      fn event ->
        Prometheus.observe("http_request_duration_us",
          event.measurements.duration_us,
          labels: %{
            method: event.metadata.conn.method,
            status: event.metadata.conn.status
          }
        )
      end
    )
  end
end
```

---

## Lifecycle Hook API

In addition to telemetry events, Bastion exposes explicit before/after hooks on the `Conn` struct for fine-grained request interception:

```march
mod Bastion.Conn do
  # Register a callback that fires just before the response is sent
  fn register_before_send(conn: Conn, callback: fn(Conn) -> Conn) -> Conn

  # Register a callback that fires after the response is sent (for cleanup)
  fn register_after_send(conn: Conn, callback: fn(Conn) -> :ok) -> Conn
end

# Example: inject a Server-Timing header into every response
fn call(conn) do
  conn
  |> register_before_send(fn conn ->
    timing = Bastion.Telemetry.Aggregator.request_waterfall(conn.assigns.request_id)
    case timing do
      Some(wf) ->
        header = wf.stages
          |> List.map(fn s -> "#{s.name};dur=#{s.duration_us / 1000.0}" end)
          |> String.join(", ")
        conn |> put_resp_header("server-timing", header)
      None -> conn
    end
  end)
  |> MyApp.Router.route()
end
```

---

## Open Questions

- How does the Vault-backed buffer handle high request throughput? Should writes be batched (e.g., flush every 100ms) to avoid Vault contention under load?
- Should the aggregator ring buffer be capped by count, by age, or both?
- Should there be a way to suppress telemetry for health-check endpoints (`/health`, `/__bastion__/*`) to avoid polluting the dashboard?
