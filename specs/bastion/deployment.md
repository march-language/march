# Bastion: Deployment and Releases

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Build Artifact

`forge build --release` produces a single self-contained directory with everything needed to run the application:

```bash
forge build --release
# ✓ Compiling my_app (release mode, optimized)
# ✓ Compiling 5 WASM islands
# ✓ Bundling static assets
# ✓ Release built: _build/release/my_app/
```

The release directory structure:

```
_build/release/my_app/
├── bin/
│   └── my_app                    # Native binary (server)
├── priv/
│   └── static/                   # All static assets, embedded
│       ├── css/
│       ├── js/
│       │   └── bastion.js        # Client runtime
│       ├── islands/              # Compiled WASM bundles
│       │   ├── search_bar-a1b2c3d4.wasm
│       │   ├── chat_widget-e5f6g7h8.wasm
│       │   └── manifest.json
│       └── images/
└── config/
    └── runtime.march             # Runtime configuration (reads env vars)
```

---

## Single Binary Option

For simpler deployments, Forge can embed all static assets directly into the binary:

```bash
forge build --release --embed-assets
# Produces a single binary: _build/release/my_app/bin/my_app
# All static files (CSS, JS, WASM bundles, images) are embedded in the binary
# and served from memory at runtime — no filesystem access needed for assets
```

This is ideal for container deployments:

```dockerfile
FROM ubuntu:22.04
COPY _build/release/my_app/bin/my_app /app/my_app
ENV SECRET_KEY_BASE=...
ENV DB_HOST=...
EXPOSE 4000
CMD ["/app/my_app", "start"]
```

---

## Runtime Configuration

Release builds use runtime configuration that reads environment variables at startup, not compile-time config:

```march
# config/runtime.march — evaluated at application start, NOT at compile time
mod MyApp.Config.Runtime do
  fn load() do
    %{
      port: Env.get("PORT", "4000") |> String.to_int(),
      secret_key_base: Env.fetch!("SECRET_KEY_BASE"),
      db: %{
        hostname: Env.fetch!("DB_HOST"),
        port: Env.get("DB_PORT", "5432") |> String.to_int(),
        database: Env.fetch!("DB_NAME"),
        username: Env.fetch!("DB_USER"),
        password: Env.fetch!("DB_PASS"),
        pool_size: Env.get("DB_POOL_SIZE", "10") |> String.to_int()
      },
      bastion: %{
        env: :prod,
        log_level: Env.get("LOG_LEVEL", "info") |> String.to_atom(),
        log_format: :json
      }
    }
  end
end
```

The distinction between compile-time config (`config/dev.march`, `config/prod.march`) and runtime config (`config/runtime.march`) is enforced by Forge. Compile-time config affects compilation. Runtime config affects behavior at startup.

---

## Environment Switching

Forge uses the `MARCH_ENV` environment variable to select the compile-time configuration:

```bash
# Development (default)
forge dev                          # MARCH_ENV=dev

# Test
forge test                         # MARCH_ENV=test

# Production build
MARCH_ENV=prod forge build --release
```

At runtime, `Bastion.env()` returns the environment the binary was compiled for. This is baked into the binary at compile time — it controls things like whether the dev error overlay is available and what optimizations are applied.

---

## Health Checks

Bastion includes a built-in health check endpoint for load balancers and orchestrators:

```march
# Automatically available at /health (configurable)
# Returns 200: {"status": "ok", "checks": {"depot": "ok", "vault": "ok"}}
# Returns 503 if any check fails: {"status": "degraded", "checks": {"depot": "error", "vault": "ok"}}

mod MyApp.HealthCheck do
  import Bastion.Health

  fn checks() do
    [
      {"depot", fn -> Depot.query(MyApp.Repo.pool(), "SELECT 1") end},
      {"vault", fn -> Vault.info(:response_cache) |> Result.ok() end},
      # Add custom checks:
      {"redis", fn -> MyApp.Redis.ping() end}
    ]
  end
end
```

---

## Graceful Shutdown

When receiving a SIGTERM (e.g., during a Kubernetes rolling deploy), Bastion:

1. Stops accepting new connections
2. Waits for in-flight HTTP requests to complete (configurable timeout, default 30 seconds)
3. Sends a close frame to all WebSocket connections, giving clients time to reconnect to another node
4. Drains the Depot connection pool
5. Exits cleanly

```march
# Configurable shutdown behavior
fn shutdown_config() do
  %{
    drain_timeout: 30_000,          # max ms to wait for in-flight requests
    channel_close_timeout: 5_000,   # ms to wait for WebSocket close handshakes
    on_shutdown: fn ->
      Bastion.Logger.info("Shutting down — draining connections")
    end
  }
end
```

---

## Scalability Model

- **Vertical**: March's green threads on OCaml 5.3.0 multicore efficiently use all CPU cores
- **Horizontal**: Stateless request handling means standard load balancer distribution works; Channel state can be distributed via PubSub backed by Redis or a distributed March cluster
