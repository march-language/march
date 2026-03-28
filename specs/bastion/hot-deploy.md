# Bastion: Connection Draining on Hot Deploy

**Status**: Draft | **Version**: 0.1 | **Part of**: [Bastion Design Spec](README.md)

---

## Overview

During a hot deploy (rolling upgrade, blue/green switch, or in-place restart), in-flight requests on the old version finish before the process exits. New requests are routed to the new version immediately. The handoff is mediated by the actor supervision tree — the HTTP acceptor supervisor stops accepting new connections while child request handlers continue running to completion.

No request is dropped. No user sees a 502. The drain window is configurable with a hard timeout as a safety net.

---

## How It Works

The lifecycle on SIGTERM (or a hot-deploy signal):

```
1. Bastion.Supervisor receives SIGTERM
2. Bastion.Endpoint.Supervisor stops the acceptor actor
   → OS closes the listen socket (new connections go to new node/process)
3. Bastion.Endpoint.Supervisor switches health check to 503
   → Load balancer stops routing new requests to this node
4. Bastion.Endpoint.Supervisor waits for all in-flight RequestHandler actors to exit
   → Each RequestHandler runs to completion normally
5. After all handlers exit (or drain_timeout elapses), remaining connections get 503
6. Bastion.Supervisor shuts down remaining infrastructure in reverse startup order:
   - Channel supervisor (sends WebSocket close frames, waits channel_close_timeout)
   - Depot pool (drains open DB connections)
   - Vault (no-op — in-memory, discarded)
7. Process exits cleanly with code 0
```

---

## Actor Tree During Drain

```march
Bastion.Supervisor
  ├── Bastion.Endpoint.Supervisor   ← stops accepting; monitors RequestHandlers
  │     ├── Acceptor                ← STOPPED during drain
  │     ├── RequestHandler(req_1)   ← running to completion
  │     ├── RequestHandler(req_2)   ← running to completion
  │     └── RequestHandler(req_3)   ← running to completion
  ├── Bastion.Channel.Supervisor    ← sends close frames on drain
  └── Depot.PoolSupervisor          ← drains after all RequestHandlers exit
```

The endpoint supervisor monitors each `RequestHandler` actor. When the last one exits, the supervisor proceeds with shutdown.

---

## Configuration

```march
# config/config.march
fn endpoint() do
  %{
    port: 4000,
    drain: %{
      # Maximum time to wait for in-flight requests to finish
      timeout: 30_000,              # 30 seconds (default)

      # Time to wait for WebSocket channel close handshakes after
      # all HTTP requests have completed
      channel_close_timeout: 5_000,  # 5 seconds (default)

      # HTTP status returned to new requests during the drain window
      # (after acceptor is stopped but before process exits)
      drain_status: 503,            # default

      # Whether to set Connection: close on responses during drain
      # Tells keep-alive clients to reconnect elsewhere
      close_connections: true       # default
    }
  }
end
```

---

## Health Check Integration

Bastion's built-in health check transitions to `503 Draining` as soon as drain begins, giving load balancers a signal to stop routing before the drain timeout fires:

```march
# Automatically managed by Bastion.Endpoint — no application code needed
# GET /health  →  200 {"status":"ok"}      (normal operation)
# GET /health  →  503 {"status":"draining"} (drain in progress)
# GET /health  →  503 {"status":"starting"} (startup not yet complete)
```

Applications can register custom health check logic that also participates in the drain state:

```march
mod MyApp.HealthCheck do
  import Bastion.Health

  fn checks() do
    [
      {"depot", fn -> Depot.ping(MyApp.Repo) end},
      {"queue", fn -> MyApp.JobQueue.healthy?() end}
    ]
  end
end
```

During drain, custom checks are bypassed and the endpoint returns 503 immediately — there is no point running DB pings when the node is shutting down.

---

## Drain Signal Options

By default, Bastion drains on SIGTERM. Other triggers can be configured:

```march
fn endpoint() do
  %{
    drain_signals: [:sigterm, :sigusr2],   # SIGUSR2 for zero-downtime restarts
    drain_on_supervisor_exit: true          # also drain if top-level supervisor crashes
  }
end
```

`SIGUSR2` is useful for in-place hot restarts (Phased + systemd `ExecReload`), where the new binary starts up, signals the old process with SIGUSR2, and the old process drains while the new one begins serving.

---

## Drain Timeout Behaviour

When `drain_timeout` elapses and requests are still in flight:

1. Remaining `RequestHandler` actors receive a `:drain_timeout` message.
2. Each handler closes the connection with a `503 Service Unavailable` response and a `Retry-After: 5` header pointing clients to retry.
3. The endpoint supervisor proceeds with shutdown regardless.

```march
# Handlers can optionally handle the drain_timeout message to do cleanup
mod MyApp.LongRunningHandler do
  fn handle_msg(:drain_timeout, conn) do
    # Opportunity to checkpoint long-running work before the 503
    conn |> send_resp(503, "Server restarting — please retry in a moment")
  end
end
```

---

## Dev Mode

In development, drain is effectively instant — there is no 30-second wait. `forge dev` uses `--drain-timeout 0` so hot reloads are immediate.

---

## Kubernetes Rolling Deploy Example

```yaml
# deployment.yaml
spec:
  template:
    spec:
      terminationGracePeriodSeconds: 40   # > drain_timeout + buffer
      containers:
        - name: my_app
          lifecycle:
            preStop:
              exec:
                command: ["/bin/sh", "-c", "sleep 5"]   # let LB drain before SIGTERM
```

The `preStop` sleep gives the load balancer time to stop routing before the drain begins. After `preStop`, Kubernetes sends SIGTERM — Bastion's drain window runs, then the process exits. `terminationGracePeriodSeconds` is the hard outer limit Kubernetes enforces.

---

## Open Questions

- Should there be a way for individual request handlers to opt out of the drain timeout (for truly idempotent, safe-to-kill handlers)?
- Should Bastion support partial drain — drain HTTP but keep WebSocket channels alive longer?
- Interaction with sticky sessions: if a load balancer uses sticky routing and the node is draining, should Bastion advertise alternate nodes in the 503 response?
