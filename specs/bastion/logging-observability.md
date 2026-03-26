# Bastion: Logging and Observability

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Structured Logging

Bastion uses structured logging throughout. In development, logs are human-readable. In production, they're JSON — parseable by log aggregation tools (Datadog, Grafana Loki, CloudWatch, etc.).

```march
mod Bastion.Logger do
  # Standard log levels
  fn debug(message: String, metadata: Map(String, Any)) -> :ok
  fn info(message: String, metadata: Map(String, Any)) -> :ok
  fn warn(message: String, metadata: Map(String, Any)) -> :ok
  fn error(message: String, metadata: Map(String, Any)) -> :ok
end

# Usage in a handler
fn show(conn, id) do
  Bastion.Logger.info("Fetching user", %{"user_id": id, "source": "api"})
  user = MyApp.Users.get(conn.assigns.db, id)
  conn |> json(user)
end
```

Development output (human-readable):

```
12:34:56.789 [info] GET /users/42 — 200 in 1.2ms
  request_id=a1b2c3d4 user_id=42 source=api
```

Production output (JSON, one line per entry):

```json
{"timestamp":"2026-03-26T12:34:56.789Z","level":"info","message":"GET /users/42 — 200 in 1.2ms","request_id":"a1b2c3d4","user_id":"42","source":"api","duration_us":1234,"status":200,"method":"GET","path":"/users/42"}
```

The output format is configured per environment:

```march
# config/prod.march
fn logger() do
  %{format: :json, level: :info, output: :stdout}
end

# config/dev.march
fn logger() do
  %{format: :human, level: :debug, output: :stdout}
end
```

---

## Request ID Tracing

Every request gets a unique request ID that propagates through the entire pipeline — middleware, handlers, Depot queries, Channel messages, and log entries.

```march
mod Bastion.Middleware.RequestID do
  fn assign_request_id(conn: Conn) -> Conn do
    request_id = case get_req_header(conn, "x-request-id") do
      Some(id) -> id
      None -> generate_uuid()
    end
    conn
    |> assign(:request_id, request_id)
    |> put_resp_header("x-request-id", request_id)
  end
end
```

The request ID is automatically included in all log entries emitted during that request's lifetime:

```json
{"request_id":"a1b2c3d4","message":"parse_body completed","duration_us":45}
{"request_id":"a1b2c3d4","message":"session loaded","user_id":"99"}
{"request_id":"a1b2c3d4","message":"Depot query","sql":"SELECT * FROM users WHERE id = $1","duration_us":892}
{"request_id":"a1b2c3d4","message":"template rendered","template":"user/show","duration_us":234}
{"request_id":"a1b2c3d4","message":"GET /users/42 — 200 in 1.4ms"}
```

---

## Request Logger Middleware

Bastion ships a logger middleware that automatically logs every request with method, path, status, and duration:

```march
mod Bastion.Middleware.Logger do
  fn log_request(conn: Conn) -> Conn do
    start_time = System.monotonic_time(:microsecond)

    # Register a callback that fires after the response is sent
    conn |> register_before_send(fn conn ->
      duration = System.monotonic_time(:microsecond) - start_time
      Bastion.Logger.info("#{conn.method} #{conn.request_path} — #{conn.status}", %{
        "method": conn.method,
        "path": conn.request_path,
        "status": conn.status,
        "duration_us": duration,
        "request_id": conn.assigns.request_id,
        "remote_ip": conn.remote_ip
      })
      conn
    end)
  end
end
```

---

## OpenTelemetry Integration

Bastion integrates with OpenTelemetry for distributed tracing and metrics. This is opt-in — enabled by adding the `bastion_telemetry` package to your dependencies.

```march
mod Bastion.Telemetry do
  # Spans emitted automatically:
  # bastion.endpoint.call         — full request lifecycle
  #   bastion.middleware.pipeline  — middleware execution
  #   bastion.router.dispatch      — route matching
  #   bastion.handler.call         — handler execution
  #     depot.query                — database queries
  #     bastion.template.render    — template rendering
  # bastion.channel.handle_in     — channel message handling
end
```

Configuration:

```march
# config/config.march
fn telemetry() do
  %{
    enabled: true,
    exporter: :otlp,                    # OpenTelemetry Protocol
    endpoint: "http://localhost:4318",   # OTLP collector
    service_name: "my_app",
    sample_rate: 1.0                    # 1.0 = trace everything, 0.1 = 10% sampling
  }
end
```

Custom spans in handlers:

```march
fn show(conn, id) do
  Bastion.Telemetry.span("users.fetch", %{"user_id": id}, fn ->
    MyApp.Users.get(conn.assigns.db, id)
  end)
  |> case do
    Ok(user) -> conn |> json(user)
    Error(:not_found) -> conn |> send_resp(404, "Not found")
  end
end
```

---

## Metrics

Bastion emits metrics at key points, consumable by Prometheus, StatsD, or OpenTelemetry Metrics:

```
# Automatically emitted metrics:
# bastion.http.request.duration    — histogram of request durations
# bastion.http.request.count       — counter of requests by method/path/status
# bastion.http.active_connections  — gauge of active connections
# bastion.channel.connected        — gauge of WebSocket connections
# bastion.channel.message.count    — counter of channel messages
# bastion.vault.operation.count    — counter of Vault reads/writes by table
# bastion.vault.memory             — gauge of Vault memory usage by table
# depot.query.duration             — histogram of database query durations
# depot.pool.available             — gauge of available connections in pool
```

---

## OpenTelemetry Performance Overhead

OpenTelemetry tracing has some overhead in production. See [open-questions.md](open-questions.md) for discussion of the right default sample rate and whether spans should be sampled by default.
