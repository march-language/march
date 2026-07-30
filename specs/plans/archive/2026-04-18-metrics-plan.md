# Metrics — OpenTelemetry-compatible instrumentation

**Status:** Planning
**Date:** 2026-04-18

## Motivation

Logger v2 covers structured logs with trace/span context. The observability
triad (logs, metrics, traces) is incomplete without metrics. Production services
need:

- **Counters**: request count, error count, cache hits
- **Gauges**: active connections, queue depth, memory usage
- **Histograms**: request latency, payload size distributions

The target is Prometheus-compatible scraping (the de-facto standard) with field
naming that matches OpenTelemetry conventions, so pipelines sending to Datadog,
Honeycomb, or Grafana Cloud work without transformation.

This is a *stdlib* metrics module, not a full OTel SDK. The bar is: instrument
a March service in 10 lines, get a `/metrics` Prometheus endpoint, done.

---

## Design

### Types (`stdlib/metrics.march`)

```march
mod Metrics do

  -- ── Instrument types ────────────────────────────────────────────────────

  type Labels = List((String, String))  -- e.g. [("method", "GET"), ("status", "200")]

  -- Opaque handles registered in the global registry.
  type Counter    -- monotonically increasing Float
  type Gauge      -- arbitrary Float (can go up or down)
  type Histogram  -- samples bucketed into configurable boundaries

  -- ── Registry ────────────────────────────────────────────────────────────

  -- Register instruments. Duplicate name = same handle (idempotent).
  fn counter(name : String, help : String) : Counter
  fn counter_with_labels(name : String, help : String, label_names : List(String)) : Counter

  fn gauge(name : String, help : String) : Gauge
  fn gauge_with_labels(name : String, help : String, label_names : List(String)) : Gauge

  fn histogram(name : String, help : String, buckets : List(Float)) : Histogram
  fn histogram_with_labels(name : String, help : String, buckets : List(Float), label_names : List(String)) : Histogram

  -- Predefined bucket sets (Prometheus conventions)
  fn latency_buckets() : List(Float)   -- [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0]
  fn size_buckets() : List(Float)      -- [128, 256, 512, 1024, 4096, 16384, 65536, 262144, 1048576]

  -- ── Recording ────────────────────────────────────────────────────────────

  fn inc(c : Counter) : Unit                               -- increment by 1
  fn inc_by(c : Counter, v : Float) : Unit                 -- increment by v
  fn inc_labels(c : Counter, labels : Labels) : Unit       -- labeled counter
  fn inc_by_labels(c : Counter, v : Float, labels : Labels) : Unit

  fn set(g : Gauge, v : Float) : Unit
  fn set_labels(g : Gauge, v : Float, labels : Labels) : Unit
  fn add(g : Gauge, v : Float) : Unit
  fn sub(g : Gauge, v : Float) : Unit

  fn observe(h : Histogram, v : Float) : Unit
  fn observe_labels(h : Histogram, v : Float, labels : Labels) : Unit

  -- ── Timing helper ────────────────────────────────────────────────────────

  -- Records duration of thunk in histogram (seconds as Float).
  fn timed(h : Histogram, thunk : fn() -> a) : a
  fn timed_labels(h : Histogram, labels : Labels, thunk : fn() -> a) : a

  -- ── Scraping ─────────────────────────────────────────────────────────────

  fn expose_prometheus() : String   -- Prometheus text format 0.0.4
  fn expose_json() : String         -- JSON (for custom collectors)

end
```

### Global registry

The registry is a process-local mutable store (backed by `Vault` or direct FFI
to a C-side hash table). All `counter`/`gauge`/`histogram` calls hit the same
global registry within a process.

Multiple processes (actors) share the registry by design — metrics aggregation
is per-process, which matches how Prometheus scrapes works in practice (one
scrape endpoint per process).

---

## HTTP endpoint

Most services want a `/metrics` route. Provide a ready-made handler:

```march
-- stdlib/metrics.march (continued)

-- Drop-in Prometheus scrape handler. Returns 200 text/plain.
fn prometheus_handler(req : HttpRequest) : HttpResponse
  let body = expose_prometheus()
  Http.response(200, body)
    |> Http.set_header("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
end
```

Bastion integration (in `bastion/router.march` or the app scaffold):
```march
Router.get("/metrics", Metrics.prometheus_handler)
```

---

## Common instruments as prebuilt helpers

```march
mod Metrics do
  -- HTTP server auto-instrumentation
  mod Http do
    -- Call once during startup. Registers:
    --   march_http_requests_total (counter, labels: method, path, status)
    --   march_http_request_duration_seconds (histogram, labels: method, path)
    --   march_http_request_size_bytes (histogram)
    --   march_http_response_size_bytes (histogram)
    fn register() : Unit

    -- Middleware — wraps a handler and records the above automatically.
    fn middleware(handler : HttpHandler) : HttpHandler
  end

  -- Runtime metrics
  mod Runtime do
    -- Call once. Registers:
    --   march_process_uptime_seconds (gauge)
    --   march_gc_collections_total (counter, labels: generation)
    --   march_gc_pause_seconds (histogram)
    --   march_memory_allocated_bytes (gauge)
    --   march_actors_active (gauge)
    fn register() : Unit
  end
end
```

Usage in a complete service:
```march
fn main() do
  Metrics.Runtime.register()
  Metrics.Http.register()

  let req_count = Metrics.counter("app_jobs_total", "Total background jobs processed")
  let job_duration = Metrics.histogram("app_job_duration_seconds", "Job duration", Metrics.latency_buckets())

  -- In a handler:
  Metrics.timed(job_duration, fn () -> process_job(job))
  Metrics.inc(req_count)
end
```

---

## OpenTelemetry naming conventions

Field and metric names follow OTel semantic conventions so that OTLP-aware
backends (Honeycomb, Datadog, New Relic) can ingest them without renames:

| Concept | Name |
|---------|------|
| HTTP request count | `http.server.request.duration` |
| HTTP response size | `http.server.response.body.size` |
| DB call duration | `db.client.operation.duration` |
| Process uptime | `process.uptime` |
| GC pause | `process.runtime.gc.pause_duration` |

Users can use any name they want; the conventions are defaults in the
`Metrics.Http` and `Metrics.Runtime` prebuilts.

---

## Implementation

### Storage

Each instrument is a `struct` in C (`runtime/march_metrics.c`):

```c
typedef struct {
  const char *name;
  const char *help;
  const char **label_names;
  int n_labels;
  atomic_double value;          // counter / gauge
} march_counter_t;

typedef struct {
  // ... header fields ...
  atomic_double *buckets;       // boundary counts
  atomic_double sum;
  atomic_long count;
  double *boundaries;
  int n_buckets;
} march_histogram_t;
```

All updates use `_Atomic double` with `__atomic_fetch_add` — lock-free, safe
from multiple concurrent actors.

### March side

The OCaml-side FFI (`lib/tir/llvm_emit.ml` or a dedicated `metrics_ffi.ml`)
exposes:
- `march_counter_new(name, help) : int64` (returns handle as opaque Int)
- `march_counter_inc(handle) : unit`
- `march_counter_inc_by(handle, v) : unit`
- `march_histogram_observe(handle, v) : unit`
- `march_expose_prometheus() : string`

The March module wraps these builtins. `Counter`, `Gauge`, `Histogram` are
`Int` at the ABI level (opaque handles) — the type checker enforces proper
usage.

### Scraping format

`expose_prometheus()` walks the registry and emits Prometheus text format 0.0.4:

```
# HELP march_http_requests_total Total HTTP requests
# TYPE march_http_requests_total counter
march_http_requests_total{method="GET",path="/",status="200"} 1234
march_http_requests_total{method="POST",path="/api",status="201"} 87
...
```

---

## What this is NOT

- A full OpenTelemetry SDK (no OTLP export, no trace-metric linking in this plan)
- A metrics push client (Pushgateway, StatsD — external package)
- A Grafana dashboard generator

These are follow-on concerns. The goal here is zero-config `/metrics` scraping
in 10 lines.

---

## Implementation order

1. **C runtime** — counter, gauge, histogram atoms; Prometheus text emitter
2. **March stdlib** — `Metrics` module with register/inc/set/observe/expose
3. **HTTP handler** — `prometheus_handler` function
4. **Timed helper** — `Metrics.timed` wrapping any thunk
5. **Runtime prebuilt** — `Metrics.Runtime.register()`
6. **HTTP prebuilt** — `Metrics.Http.middleware`

Steps 1–4 land together as the first PR. Steps 5–6 follow.
