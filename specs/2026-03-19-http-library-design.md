# HTTP Library Design Spec

**Date:** 2026-03-19
**Status:** Draft

## Overview

March's HTTP library is a three-layer design providing pure protocol types, low-level pooled transport, and a high-level composable client. Each layer is a discrete module — libraries can depend on just the layer they need.

**Design influences:** Elixir Req (step pipeline), Elixir Finch (connection pooling), Gleam gleam_http (polymorphic types, pure protocol layer), Go net/http (simplicity), Rust reqwest-middleware (typed context passing).

## Architecture

```
┌──────────────────────────────────────────────┐
│  Http.Client  (Layer 3 — high-level)         │
│  Steps, redirects, retries, auth, compression│
│  use Http.Client                             │
├──────────────────────────────────────────────┤
│  Http.Transport  (Layer 2 — low-level I/O)   │
│  Connection pooling, TLS, streaming          │
│  use Http.Transport                          │
├──────────────────────────────────────────────┤
│  Http  (Layer 1 — pure types)                │
│  Request(body), Response(body), Method, etc. │
│  use Http                                    │
└──────────────────────────────────────────────┘
```

**Dependency direction:** Layer 3 depends on Layer 2 depends on Layer 1. Libraries that only need HTTP types import Layer 1. Libraries that need raw transport import Layers 1+2. Application code typically uses Layer 3.

## Layer 1: `Http` — Pure Protocol Types

No I/O. Data types, constructors, and transforms only. Any library that speaks HTTP depends on this alone.

### Types

```march
mod Http do
  type Method =
    | Get
    | Post
    | Put
    | Patch
    | Delete
    | Head
    | Options
    | Trace
    | Connect
    | Other(String)

  type Scheme = Http | Https

  type Status = Status(Int)

  type Header = Header(String, String)

  type Request(body) = Request(Method, Scheme, String, Option(Int), String, Option(String), List(Header), body)
  # Fields: method, scheme, host, port, path, query, headers, body

  type Response(body) = Response(Status, List(Header), body)
  # Fields: status, headers, body

  type UrlError =
    | InvalidScheme(String)
    | MissingHost
    | InvalidPort(String)
    | MalformedUrl(String)
end
```

**Note on syntax:** March variant constructors take positional arguments. Record types exist but anonymous records inside variants are not yet supported. If/when record-in-variant syntax is added, these types should be migrated. For now, accessor functions provide named field access.

### Constructors

```march
  # Build requests from URLs (parses scheme, host, port, path, query)
  pub fn get(url: String) -> Result(Request(Unit), UrlError)
  pub fn post(url: String, body: b) -> Result(Request(b), UrlError)
  pub fn put(url: String, body: b) -> Result(Request(b), UrlError)
  pub fn patch(url: String, body: b) -> Result(Request(b), UrlError)
  pub fn delete(url: String) -> Result(Request(Unit), UrlError)
  pub fn head(url: String) -> Result(Request(Unit), UrlError)
  pub fn options(url: String) -> Result(Request(Unit), UrlError)

  # Build from parts (no parsing, no Result)
  pub fn request(method: Method, scheme: Scheme, host: String, path: String) -> Request(Unit)
```

### Accessors

```march
  # Request field access
  pub fn method(req: Request(b)) -> Method
  pub fn host(req: Request(b)) -> String
  pub fn path(req: Request(b)) -> String
  pub fn port(req: Request(b)) -> Option(Int)
  pub fn query(req: Request(b)) -> Option(String)
  pub fn scheme(req: Request(b)) -> Scheme
  pub fn headers(req: Request(b)) -> List(Header)
  pub fn body(req: Request(b)) -> b
```

### Request Transforms (Pipeable)

```march
  pub fn set_header(req: Request(b), name: String, value: String) -> Request(b)
  pub fn set_query(req: Request(b), params: List((String, String))) -> Request(b)
  pub fn set_body(req: Request(a), body: b) -> Request(b)
  pub fn set_path(req: Request(b), path: String) -> Request(b)
  pub fn set_port(req: Request(b), port: Int) -> Request(b)
  pub fn set_scheme(req: Request(b), scheme: Scheme) -> Request(b)
  pub fn set_method(req: Request(b), method: Method) -> Request(b)
```

### Response Inspection

```march
  pub fn status_code(resp: Response(b)) -> Int
  pub fn get_header(resp: Response(b), name: String) -> Option(String)
  pub fn get_headers(resp: Response(b), name: String) -> List(String)
  pub fn response_body(resp: Response(b)) -> b
  pub fn is_success(resp: Response(b)) -> Bool         # 2xx
  pub fn is_redirect(resp: Response(b)) -> Bool        # 3xx
  pub fn is_client_error(resp: Response(b)) -> Bool    # 4xx
  pub fn is_server_error(resp: Response(b)) -> Bool    # 5xx
  pub fn is_informational(resp: Response(b)) -> Bool   # 1xx
```

### Status Helpers

```march
  pub fn status_ok() -> Status            # 200
  pub fn status_created() -> Status       # 201
  pub fn status_no_content() -> Status    # 204
  pub fn status_moved() -> Status         # 301
  pub fn status_found() -> Status         # 302
  pub fn status_bad_request() -> Status   # 400
  pub fn status_unauthorized() -> Status  # 401
  pub fn status_forbidden() -> Status     # 403
  pub fn status_not_found() -> Status     # 404
  pub fn status_server_error() -> Status  # 500
```

### Design Decisions

- **Polymorphic body:** `Request(body)` and `Response(body)` are generic. Body can be `Unit` (no body), `String`, or any user type. This is the Gleam approach adapted for March's type system. The polymorphism is most useful in Layer 1 for library authors working with HTTP types; Layer 3's step pipeline operates on fixed `String` types (see below).
- **Headers as list:** `List(Header)` preserves order and allows duplicate header names (required by HTTP spec for `Set-Cookie` etc.). Case-insensitive lookup is handled by `get_header`.
- **URL parsing returns Result:** `get(url)` can fail on malformed URLs. The `request(method, scheme, host, path)` constructor is infallible for programmatic construction.
- **No I/O:** This module has zero side effects. It can be used in pure code, tested without mocking, and depended on by any library.
- **Positional constructors:** Variant constructors use positional args per March's current AST. Accessor functions provide named field access until record-in-variant syntax is available.

## Layer 2: `Http.Transport` — Low-Level I/O

Connection pooling, TLS, raw request/response. The Finch-equivalent. Takes `Request(String)`, returns `Response(String)`.

**Note on String vs Bytes:** March strings are UTF-8 byte sequences. For HTTP transport, request and response bodies are passed as `String`. A future `Bytes` type (immutable byte buffer for non-UTF-8 binary data) is out of scope for this design but would be a natural evolution of the transport layer.

### Types

```march
mod Http do
  mod Transport do
    type TransportError =
      | ConnectionRefused(String)
      | Timeout(String)
      | TlsError(String)
      | ProtocolError(String)
      | Closed

    type PoolConfig = PoolConfig(Int, Int, Int, Int)
    # Fields: size (default 10), idle_timeout_ms (default 30000),
    #         connect_timeout_ms (default 5000), recv_timeout_ms (default 15000)

    type Pool  # opaque

    type StreamMsg =
      | StatusCode(Int)
      | Headers(List(Http.Header))
      | Data(String)
      | Done

    type StreamControl = Continue | Halt

    type PoolStats = PoolStats(Int, Int, Int)
    # Fields: active, idle, pending
  end
end
```

### Pool Lifecycle

```march
    pub fn start_pool(cap: Cap(Net), config: PoolConfig) -> Task(Result(Pool, TransportError))
    pub fn start_pool_default(cap: Cap(Net)) -> Task(Result(Pool, TransportError))
    pub fn stop_pool(pool: Pool) -> Task(Unit)
    pub fn default_config() -> PoolConfig
```

### Core Operations

```march
    # Send a request, receive full response
    pub fn send(
      pool: Pool,
      request: Http.Request(String)
    ) -> Task(Result(Http.Response(String), TransportError))

    # Streaming — receive response in chunks via callback
    pub fn stream(
      pool: Pool,
      request: Http.Request(String),
      handler: StreamMsg -> StreamControl
    ) -> Task(Result(Http.Response(Unit), TransportError))
```

### Pool Introspection

```march
    pub fn pool_stats(pool: Pool) -> Task(PoolStats)
```

### Design Decisions

- **Pool-per-destination internally:** A single `Pool` handle routes requests to internal sub-pools keyed by `{scheme, host, port}`, matching Finch's architecture. Users don't manage per-host pools.
- **Pool is an actor:** Internally the pool is an actor managing connection checkout/checkin, idle reaping, and reconnection. This fits March's concurrency model. `pool_stats` returns `Task` because it queries the actor.
- **`Request(String)` in, `Response(String)` out:** The transport layer moves string data. March's strings are byte sequences under the hood, so this covers both text and (for now) binary payloads.
- **Capability-gated:** `start_pool` requires `Cap(Net)`. Sandboxed code cannot make HTTP requests unless explicitly granted network capability.
- **4xx/5xx are not errors:** A `404 Not Found` is a successful transport operation. `TransportError` covers only connection-level failures (refused, timeout, TLS, protocol errors, closed).
- **Streaming with early termination:** The `StreamControl` return from the handler callback allows `Halt` to stop receiving data early (e.g., only need headers, or body exceeds size limit). Follows Finch's `stream_while` pattern.
- **`StreamMsg` not `StreamEvent`:** Avoids name collision with `Http.Status` — uses `StatusCode(Int)` variant name.

## Layer 3: `Http.Client` — High-Level Composable Client

Req-style step pipeline with built-in convenience steps. What most application code uses.

### Key Design Decision: Fixed Body Types in the Pipeline

The step pipeline operates on **`Request(String)` and `Response(String)`** — not polymorphic body types. This is a deliberate simplification:

- **Why:** Polymorphic step types like `RequestStep(a, b)` create a type-level chain (`a -> b -> c -> ... -> String`) that an opaque `Client` type erases. March's HM type checker cannot verify the pipeline composes correctly through an opaque boundary. Elixir's Req works with dynamic types; March is statically typed.
- **Trade-off:** Users work with `String` bodies in the pipeline. JSON/XML/etc. encoding and decoding happens before entering or after leaving the pipeline (or in steps that convert `String -> String`). This is simpler and type-safe.
- **Layer 1's polymorphism is preserved:** Libraries that work with `Request(MyType)` at the type level use Layer 1 directly. Layer 3 is the "batteries-included runtime" layer where everything is concrete.

### Types

```march
mod Http do
  mod Client do
    type HttpError =
      | TransportError(Http.Transport.TransportError)
      | StepError(String, String)   # (step_name, message)
      | TooManyRedirects(Int)

    type Client  # opaque — holds pool + registered steps + pipeline config

    # Request steps: transform request before sending
    # Returns the (possibly modified) request, or a Result to signal errors
    type RequestStep = Http.Request(String) -> Result(Http.Request(String), HttpError)

    # Response steps: inspect/transform the request+response pair
    # Returns Result to allow steps like raise_on_error_status to signal errors
    type ResponseStep = (Http.Request(String), Http.Response(String)) -> Result((Http.Request(String), Http.Response(String)), HttpError)

    # Error steps: attempt to recover from errors
    type ErrorStep = (Http.Request(String), HttpError) -> ErrorResult

    type ErrorResult =
      | Recover(Http.Response(String))
      | Fail(HttpError)
  end
end
```

### Client Construction

```march
    pub fn new(cap: Cap(Net)) -> Task(Result(Client, HttpError))
    pub fn new_with(cap: Cap(Net), config: Http.Transport.PoolConfig) -> Task(Result(Client, HttpError))
    pub fn from_pool(pool: Http.Transport.Pool) -> Client
```

### Step Registration (Pipeable)

```march
    pub fn add_request_step(client: Client, name: String, step: RequestStep) -> Client
    pub fn add_response_step(client: Client, name: String, step: ResponseStep) -> Client
    pub fn add_error_step(client: Client, name: String, step: ErrorStep) -> Client
    pub fn list_steps(client: Client) -> List(String)
```

### Pipeline Behaviors

Some operations need access to the pipeline itself (they resend requests). These are **pipeline behaviors** configured on the client, not plain steps.

```march
    # Redirect following — needs to resend through the transport
    pub fn with_redirects(client: Client, max: Int) -> Client

    # Retry on transport errors — needs to resend through the transport
    pub fn with_retry(client: Client, max_attempts: Int, backoff_ms: Int) -> Client
```

**Why not steps?** `follow_redirects` and `retry` both need to re-issue HTTP requests. A plain step function only receives `(Request, Response)` and returns a transformed pair — it has no access to the transport pool. Making these pipeline behaviors means the pipeline executor handles them internally with full access to the transport.

### Sending Requests

```march
    # Convenience — build + send through pipeline
    pub fn get(client: Client, url: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn post(client: Client, url: String, body: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn put(client: Client, url: String, body: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn patch(client: Client, url: String, body: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn delete(client: Client, url: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn head(client: Client, url: String) -> Task(Result(Http.Response(String), HttpError))
    pub fn options(client: Client, url: String) -> Task(Result(Http.Response(String), HttpError))

    # Full control — send a pre-built request through the step pipeline
    pub fn send(client: Client, req: Http.Request(String)) -> Task(Result(Http.Response(String), HttpError))
```

### Pipeline Execution

When `send` (or a convenience method) is called, the pipeline executes in order:

1. **Request steps** run left-to-right. Each transforms the request. If a step returns `Err(e)`, remaining request steps are skipped and error steps run.
2. **Transport send** — the request is sent via `Http.Transport.send`.
3. **Redirect handling** (if `with_redirects` is configured) — on 3xx responses, the pipeline re-sends to the redirect target, up to `max` times. Returns `TooManyRedirects` if exceeded.
4. **Response steps** run left-to-right. Each receives and can transform the `(request, response)` pair. If a step returns `Err(e)`, remaining response steps are skipped and error steps run.
5. **On transport error**, retry logic runs first (if `with_retry` is configured). If retries are exhausted or not configured, error steps run left-to-right. Each can `Recover` (produce a response, which then flows through remaining response steps) or `Fail` (pass the error along).

### Built-in Steps

All steps are plain functions in a submodule. None are auto-registered — users opt in.

```march
    mod Steps do
      # Request steps (Request(String) -> Result(Request(String), HttpError))
      pub fn default_headers() -> RequestStep
        # Sets User-Agent: march/0.1, Accept: */*
      pub fn basic_auth(user: String, pass: String) -> RequestStep
      pub fn bearer_auth(token: String) -> RequestStep
      pub fn put_base_url(base: String) -> RequestStep
      pub fn put_content_type(ct: String) -> RequestStep
      pub fn log_requests() -> RequestStep

      # Response steps ((Request, Response) -> Result((Request, Response), HttpError))
      pub fn decompress() -> ResponseStep
        # Decodes gzip/deflate response body based on Content-Encoding header
      pub fn raise_on_error_status() -> ResponseStep
        # Returns Err(StepError("raise_on_error_status", "404 Not Found")) for 4xx/5xx
      pub fn log_responses() -> ResponseStep
    end
```

### Usage Example

```march
use Http
use Http.Client
use Http.Client.Steps

fn main() =
  let client = Client.new(net_cap)
    |> task_await_unwrap
    |> Client.add_request_step("base_url", Steps.put_base_url("https://api.example.com"))
    |> Client.add_request_step("auth", Steps.bearer_auth(my_token))
    |> Client.add_request_step("headers", Steps.default_headers())
    |> Client.add_response_step("decompress", Steps.decompress())
    |> Client.with_redirects(5)
    |> Client.with_retry(3, 1000)

  # Simple GET
  let resp = client
    |> Client.get("/users/1")
    |> task_await_unwrap

  println(Http.response_body(resp))

  # POST with body
  let req = Http.post("https://api.example.com/users", "{\"name\": \"alice\"}")
    |> unwrap
    |> Http.set_header("Content-Type", "application/json")

  let resp = Client.send(client, req) |> task_await_unwrap

  println(Http.response_body(resp))
end
```

### Writing Custom Steps

Steps are plain functions. No interface to implement.

```march
# A request step that adds a request ID header
fn add_request_id(req: Http.Request(String)) -> Result(Http.Request(String), HttpError) =
  let id = generate_uuid()
  Ok(req |> Http.set_header("X-Request-ID", id))

# A response step that logs slow responses
fn log_slow(req: Http.Request(String), resp: Http.Response(String)) -> Result((Http.Request(String), Http.Response(String)), HttpError) =
  # inspect response, log if relevant
  Ok((req, resp))

# Register them
let client = client
  |> Client.add_request_step("request_id", add_request_id)
  |> Client.add_response_step("slow_log", log_slow)
```

### Plugin Pattern

Libraries ship a function that attaches multiple steps at once, following Req's attach pattern.

```march
mod MyApiClient do
  pub fn attach(client: Http.Client.Client, api_key: String) -> Http.Client.Client =
    client
    |> Http.Client.add_request_step("my_api_base", Http.Client.Steps.put_base_url("https://api.myservice.com/v2"))
    |> Http.Client.add_request_step("my_api_auth", Http.Client.Steps.bearer_auth(api_key))
    |> Http.Client.add_response_step("my_api_errors", handle_api_errors)
    |> Http.Client.with_redirects(3)

  fn handle_api_errors(req, resp) =
    # parse API-specific error format, add context
    Ok((req, resp))
end
```

### Design Decisions

- **Steps are functions, not interfaces:** No `Steppable` interface needed. A step is just a function with the right signature. This is simpler and more composable than trait-based middleware.
- **Named steps:** Every step has a string name for introspection via `list_steps`. Aids debugging ("why did my request get modified?") and allows step removal/replacement in plugin composition.
- **Steps return Result:** Both `RequestStep` and `ResponseStep` return `Result`, giving every step an error channel. `raise_on_error_status` uses this to convert 4xx/5xx into errors. Error steps then have the opportunity to recover.
- **Pipeline behaviors vs steps:** `follow_redirects` and `retry` need to resend requests, so they are configured as pipeline behaviors (`with_redirects`, `with_retry`) rather than plain steps. The pipeline executor handles them internally with access to the transport pool. This avoids giving step functions access to the pool, which would break the clean function signature.
- **Fixed `String` body type:** The step pipeline uses `Request(String)` and `Response(String)` uniformly. This avoids unsound type erasure through the opaque `Client`. Layer 1's polymorphic types remain available for libraries that need `Request(MyType)` at the type level.
- **No default steps:** `Client.new()` gives a bare client. Users explicitly add the steps they want. This avoids magic behavior and makes the pipeline transparent.
- **Capability flows through:** `Client.new(cap)` requires `Cap(Net)` because it creates a pool internally. `from_pool` doesn't need it because the pool was already capability-checked at creation.

## Error Philosophy

**4xx/5xx are not errors.** A `404 Not Found` response means the transport succeeded — the server received the request and responded. `TransportError` covers only connection-level failures.

Users who want 4xx/5xx treated as errors add `Steps.raise_on_error_status()` as a response step. This is opt-in, not default.

Error types are layered to match modules:

| Layer | Error Type | Covers |
|-------|-----------|--------|
| Transport | `TransportError` | Connection refused, timeout, TLS, protocol, closed |
| Client | `HttpError` | Wraps `TransportError` + adds `StepError` for step failures + `TooManyRedirects` |

## Capability Model

HTTP requires network access. March's capability system gates this:

```march
# Pool creation requires Cap(Net)
let pool = Http.Transport.start_pool(net_cap, config) |> task_await_unwrap

# Client creation requires Cap(Net) (creates pool internally)
let client = Http.Client.new(net_cap) |> task_await_unwrap

# Or share a pool across clients
let client1 = Http.Client.from_pool(pool)
let client2 = Http.Client.from_pool(pool)
```

Sandboxed code without `Cap(Net)` cannot construct pools or clients. Libraries declare their capability requirements; callers provide them.

## JSON Interop

JSON is a separate stdlib module (`Json`), not coupled to HTTP. The pattern for JSON APIs:

```march
use Http.Client
use Json

# Encode body as JSON, send as POST
let json_body = Json.encode(user)
let resp = client
  |> Client.post("/api/users", json_body)
  |> task_await_unwrap

# Decode response body from JSON
let parsed = Http.response_body(resp) |> Json.decode
match parsed with
| Ok(u) -> println(u.name)
| Err(e) -> println("JSON error: " ++ e)
end
```

A `json_encode` request step and `json_decode` response step could be written as a plugin, but they live outside `Http.Client`.

## Prerequisites

These language features must exist before this library can be built:

- **Nested module definitions:** `mod Http do mod Transport do ... end end` syntax. The parser currently supports single-level `mod Name do ... end`. Nested modules need parser extension or flattened module names.
- **`Cap(Net)` capability type:** The capability system is designed but the specific `Net` capability for network access needs to be defined and integrated.
- **Socket/TCP primitives:** The transport layer needs low-level socket operations (connect, send, receive, close) as runtime builtins or FFI bindings. These do not exist yet.
- **TLS bindings:** HTTPS support requires TLS. This could be via FFI to OpenSSL/LibreSSL or a pure implementation.

## Future Considerations

These are explicitly out of scope for the initial design but noted for future work:

- **`Bytes` type:** An immutable byte buffer for non-UTF-8 binary data. Would replace `String` at the transport boundary for binary protocols. Currently March strings handle both text and byte payloads.
- **HTTP/2 support:** The transport layer abstracts protocol details. HTTP/2 multiplexing would use a single connection with a state machine (like Finch) instead of a connection pool. The `Pool` type hides this from callers.
- **WebSocket upgrade:** Would be a transport-level operation returning a `WebSocket` handle instead of a `Response`. Likely a separate `Http.Transport.upgrade_websocket` function.
- **Request body streaming:** Currently request bodies are fully materialized as `String`. Large uploads would need a `Stream(String)` body type and transport support.
- **Cookie jar:** A step that maintains cookies across requests. Natural fit as a stateful response step.
- **Connection-level configuration:** Per-destination pool sizes, custom TLS certificates, proxy support. Would extend `PoolConfig`.
- **Metrics/telemetry:** Steps can implement timing and counting, but a first-class telemetry hook point could be added to the transport layer.
- **Short-circuit in request steps:** A request step could return a response directly (e.g., cache hit) instead of only transforming the request. This would need an extended return type like `Continue(Request) | ShortCircuit(Response) | Err(HttpError)`. Deferred to avoid complexity in v1.
