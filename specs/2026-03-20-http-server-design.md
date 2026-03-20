# HTTP Server Design

**Date:** 2026-03-20
**Status:** Draft
**Depends on:** HTTP client library (implemented), actors (implemented), monitors/links (implemented)

## Goals

Build an HTTP/1.1 server into March's stdlib. Inspired by Plug/Bandit/Phoenix:

- **Everything is a plug** — a plug is `Conn -> Conn`. The router is a plug. Auth is a plug. Logging is a plug. The whole request lifecycle is a pipeline of `Conn -> Conn` transforms.
- **Conn is the unit of composition** — one value flows through the entire pipeline via `|>`. Holds request data, response state, and user assigns.
- **Conn is a plain value (v1)** — threaded through pipe chains. Linear enforcement is a v2 goal (the type checker supports linear types, but the interpreter doesn't enforce them at runtime yet). For now, Conn is a regular ADT — the pipeline design is identical either way, and linearity can be added later without changing user code.
- **Routing is pattern matching** — `match (conn.method, conn.path_info)`. No DSL, no macros, no framework. Just the language.
- **Concurrent by default** — each accepted connection spawns an OS thread (OCaml 5 `Thread.create`). Blocking I/O releases the domain lock, so threads waiting on `tcp_recv`/`tcp_send` don't block other connections. Like Bandit spawning an Erlang process per connection.
- **Crash isolation without try/catch** — each connection thread has its own execution context. If a handler crashes, the thread catches it at the runtime level (OCaml, not March), sends a 500, closes the fd. Other connections and the accept loop are unaffected.
- **Capabilities thread through closures** — handlers capture only the caps they need. The type signature is the security audit.

## Non-Goals (v1)

- Linear Conn enforcement — type checker supports it, interpreter doesn't enforce at runtime; deferred
- Typestate (`Conn(Pending)` vs `Conn(Sent)`) — needs phantom types, deferred
- Streaming/chunked responses — deferred to v2
- WebSockets — deferred to v2
- HTTPS/TLS — deferred
- HTTP/2 — deferred
- March-level scheduler integration — concurrency is via OCaml threads, not the March scheduler
- Session types on protocols — deferred
- `Cap(Net)` gating on port binding — capabilities not wired into `main()` yet

## Architecture

Like Bandit: the accept loop runs in the main thread, each connection gets its own OS thread.

```
HttpServer.listen(server)           -- builtin, implemented in OCaml
  │
  ├── tcp_listen(port)              -- bind + listen
  │
  └── Accept Loop (OCaml, main thread)
        │
        ├── Unix.accept → client_fd
        │
        ├── Thread.create → connection thread
        │     │
        │     ├── tcp_recv_http(fd)         -- blocks; releases domain lock
        │     ├── http_parse_request(raw)
        │     ├── build Conn
        │     ├── eval March pipeline       -- run_pipeline(conn, plugs)
        │     ├── write_response(fd, conn)
        │     └── tcp_close(fd)
        │     │
        │     └── On crash: catch Eval_error → send 500 → close fd
        │
        └── (loop immediately accepts next connection)
```

The accept loop never waits for handlers to finish. While one handler is blocked reading a request body, other connections are being accepted and processed. This is the same model as Bandit's connection process spawning.

## The Conn Type

Modeled on `%Plug.Conn{}`. Holds everything about a request-response cycle.

```march
type Method = Get | Post | Put | Patch | Delete | Head | Options

type Conn = Conn(
  Int,                   -- fd (TCP socket)
  Method,                -- request method
  String,                -- request path (raw, e.g. "/users/42")
  List(String),          -- path_info (split segments: ["users", "42"])
  String,                -- query_string (raw, e.g. "page=1&limit=10")
  List(Header),          -- request headers
  String,                -- request body
  Int,                   -- response status (0 = not yet set)
  List(Header),          -- response headers
  String,                -- response body
  Bool,                  -- halted? (true after send_resp)
  List((String, String)) -- assigns (user-defined key-value store)
)
```

### Conn Accessors

Read fields from the Conn by destructuring and reconstructing. Since Conn is a plain ADT (not linear in v1), these are simple pattern-match extractions.

```march
pub fn method(conn) : Method do
  match conn with | Conn(_, m, _, _, _, _, _, _, _, _, _, _) -> m end
end

pub fn path(conn)        : String
pub fn path_info(conn)   : List(String)
pub fn query_string(conn): String
pub fn req_headers(conn) : List(Header)
pub fn req_body(conn)    : String
pub fn get_req_header(conn, name) : Option(String)
pub fn halted(conn)      : Bool
pub fn assigns(conn)     : List((String, String))
pub fn get_assign(conn, key) : Option(String)
```

When linear Conn is added in v2, accessors will destructure-and-reconstruct to satisfy linearity (consuming the old Conn, returning both the extracted value and a new Conn), or we'll add a borrow mechanism to the type checker.

### Conn Transforms

Each returns a new Conn (consumes the old one if linear). These are the building blocks for piping.

```march
-- Add a response header
pub fn put_resp_header(conn, name, value) : Conn

-- Set a value in the assigns map
pub fn assign(conn, key, value) : Conn

-- Set response status + body and mark halted
-- This is the primary way to "respond"
pub fn send_resp(conn, status, body) : Conn

-- Mark as halted without setting a response
-- (used by middleware to short-circuit)
pub fn halt(conn) : Conn
```

### Convenience Response Helpers

Sugar over `put_resp_header |> send_resp`:

```march
pub fn text(conn, status, body) : Conn do
  conn
  |> put_resp_header("content-type", "text/plain; charset=utf-8")
  |> send_resp(status, body)
end

pub fn json(conn, status, body) : Conn do
  conn
  |> put_resp_header("content-type", "application/json")
  |> send_resp(status, body)
end

pub fn html(conn, status, body) : Conn do
  conn
  |> put_resp_header("content-type", "text/html; charset=utf-8")
  |> send_resp(status, body)
end

pub fn redirect(conn, url) : Conn do
  conn
  |> put_resp_header("location", url)
  |> send_resp(302, "")
end

pub fn send_file(conn, status, path) : Conn
-- reads file, sets content-type from extension, sends
```

## Plugs and Pipelines

### What is a Plug

A plug is any function `Conn -> Conn`. That's it. No interface, no module protocol, no registration. Just a function.

```march
-- A plug that logs requests
fn log_plug(conn) do
  println(method_to_string(Conn.method(conn)) ++ " " ++ Conn.path(conn))
  conn
end

-- A plug that adds a header
fn server_header_plug(conn) do
  conn |> Conn.put_resp_header("server", "march/0.1")
end
```

### Pipeline Execution

A pipeline is a list of plugs. The runner applies them in order, stopping at the first halted conn (like Plug.Builder):

```march
fn run_pipeline(conn, plugs) do
  match plugs with
  | Nil -> conn
  | Cons(plug, rest) ->
    if Conn.halted(conn) then conn
    else run_pipeline(plug(conn), rest)
  end
end
```

Once `send_resp` is called, the conn is halted and subsequent plugs are skipped.

### Server Setup via Piping

```march
HttpServer.new(4000)
|> HttpServer.plug(log_plug)
|> HttpServer.plug(auth_plug(auth_cap))
|> HttpServer.plug(router)
|> HttpServer.listen()
```

`HttpServer.new` creates a server config. Each `plug` appends to the pipeline. `listen` starts the accept loop. The pipe order IS the execution order — first plug runs first.

### The Server Config Type

```march
type Server = Server(
  Int,            -- port
  List(Conn -> Conn)  -- pipeline (list of plugs)
)

pub fn new(port) do
  Server(port, Nil)
end

pub fn plug(server, p) do
  match server with
  | Server(port, plugs) -> Server(port, append(plugs, Cons(p, Nil)))
  end
end
```

## Routing

Routing is not a special subsystem. It's a plug that pattern-matches.

```march
fn router(conn) do
  match (Conn.method(conn), Conn.path_info(conn)) with
  | (Get, [])                -> conn |> Conn.text(200, "Hello!")
  | (Get, ["users", id])     -> conn |> get_user(id)
  | (Post, ["users"])        -> conn |> create_user()
  | (Delete, ["users", id])  -> conn |> delete_user(id)
  | _                        -> conn |> Conn.text(404, "Not found")
  end
end
```

Every branch must return a Conn (linear enforcement). The catch-all `_` handles 404. Exhaustiveness checking reminds you if you forget it.

### Scoped Pipelines (nested matching)

For route groups that share middleware, just nest functions:

```march
fn router(conn) do
  match Conn.path_info(conn) with
  | Cons("api", rest) ->
    conn
    |> require_auth(auth_cap)
    |> api_router
  | _ ->
    conn |> public_router
  end
end

fn api_router(conn) do
  match (Conn.method(conn), Conn.path_info(conn)) with
  | (Get, ["api", "users"])    -> conn |> list_users()
  | (Post, ["api", "users"])   -> conn |> create_user()
  | _                          -> conn |> Conn.json(404, "{\"error\": \"not found\"}")
  end
end
```

Auth only runs for `/api/*` routes because it's only called in that branch. No framework feature needed — it's just function calls.

## Concurrency: Thread-per-Connection

### How It Works

`HttpServer.listen` is an **OCaml-level builtin** (not a March function). It:

1. Calls `Unix.socket` + `Unix.bind` + `Unix.listen` with `SO_REUSEADDR`
2. Enters a loop: `Unix.accept` → `Thread.create` → loop
3. Each thread runs the March pipeline independently
4. The accept loop returns to accepting immediately — never waits for handlers

This uses OCaml 5's `Thread` module. When a thread calls `Unix.recv` (blocking I/O), the domain lock is released, letting other threads run. Multiple connections can be reading requests, running handlers, and writing responses simultaneously.

### Connection Thread Lifecycle

Each thread runs this sequence (implemented in OCaml inside `eval.ml`):

```
1. tcp_recv_http(fd)           -- read raw HTTP request (blocks, releases lock)
2. http_parse_request(raw)     -- parse method, path, headers, body
3. build Conn value            -- construct the March Conn ADT
4. eval run_pipeline(conn, plugs)  -- run the March plug pipeline
5. extract response from Conn  -- read status, headers, body from returned Conn
6. http_serialize_response()   -- format HTTP response
7. tcp_send_all(fd, response)  -- write response (blocks, releases lock)
8. tcp_close(fd)               -- done
```

Steps 1 and 7 release the domain lock while blocked on I/O. Other threads make progress during these waits. Step 4 (running March code) holds the domain lock, but HTTP handlers are typically fast — the bottleneck is I/O, not computation.

### Crash Recovery

Each thread wraps steps 1-8 in an OCaml-level `try ... with`:

```ocaml
let connection_thread client_fd pipeline env =
  try
    (* steps 1-8 above *)
    handle_connection client_fd pipeline env
  with
  | Eval_error msg ->
    (* Handler crashed — send 500, log, close *)
    send_500_response client_fd;
    Unix.close client_fd;
    Printf.eprintf "Handler crash: %s\n%!" msg
  | exn ->
    Unix.close client_fd;
    Printf.eprintf "Unexpected: %s\n%!" (Printexc.to_string exn)
```

From the March programmer's perspective: **there is no try/catch.** If your plug pipeline crashes (division by zero, pattern match failure, etc.), the runtime catches it, sends a 500, and closes the connection. Other connections are unaffected. The accept loop never sees the crash.

This is the same model as Bandit — if an Erlang process handling a connection crashes, the BEAM catches it and the acceptor keeps running. The difference is implementation (OS threads vs BEAM processes), not semantics.

### Thread Safety

**What's safe:**
- Each connection thread operates on its own Conn value — no sharing
- Plug functions (closures) are immutable values — safe to call from multiple threads
- TCP operations use independent file descriptors per thread

**What needs protection:**
- `actor_registry`, `next_pid`, `next_monitor_id` — shared mutable state in eval.ml
- Protected with a `Mutex.t` around actor operations
- Pure handlers (no actor interaction) run with zero synchronization overhead

**For v1:** handlers that interact with actors will serialize through the mutex. Pure `Conn -> Conn` handlers (the common case for HTTP) run fully in parallel.

### The March-Side API

From the March programmer's perspective, none of this is visible. The API is:

```march
HttpServer.new(4000)
|> HttpServer.plug(logger)
|> HttpServer.plug(router)
|> HttpServer.listen()
```

`listen()` blocks forever (it's the accept loop). Connections are handled concurrently in the background. If a handler crashes, a 500 is sent. The programmer writes pure `Conn -> Conn` functions and the runtime handles the rest.

### Required OCaml Changes

1. **Add `threads` library** to `lib/eval/dune` dependencies
2. **Add `Mutex.t`** around `actor_registry` and global counters in eval.ml
3. **Implement `http_server_listen` builtin** — the accept loop + Thread.create logic
4. **Thread-local state** for `module_stack`, `reduction_ctx`, `debug_ctx` using `Thread.key`

### Future: March-Level Concurrency (v2)

When the March scheduler is wired in, `listen` can spawn lightweight March tasks instead of OS threads — matching Bandit's use of BEAM processes. The March user code doesn't change. The transition is purely internal to the runtime.

## Capability Security

### v1: Capabilities via Closures (works today)

Capability gating on ports (`Cap(Net)`) is deferred. But capability-style security already works through closures — handlers only access what they capture:

```march
fn main() do
  -- Imagine db comes from a capability-gated init in future
  let db_conn = connect_db("postgres://localhost/app")

  HttpServer.new(4000)
  |> HttpServer.plug(fn(conn) do
    match (Conn.method(conn), Conn.path_info(conn)) with
    | (Get, ["users", id]) -> conn |> get_user(db_conn, id) -- captures db_conn
    | (Get, ["health"])    -> conn |> Conn.text(200, "ok")  -- captures nothing
    | _                    -> conn |> Conn.text(404, "Not found")
    end
  end)
  |> HttpServer.listen()
end
```

- `/health` captures nothing — can't touch the database even if it wanted to
- `/users/:id` captures `db_conn` — can access the database

### Future: `Cap(Net)` Gating

When capabilities are wired into `main()`, `HttpServer.new` will require `Cap(Net)`:

```march
fn main(net : Cap(Net), db : Cap(Db)) do
  HttpServer.new(net, 4000)  -- can't bind a port without Cap(Net)
  |> ...
end
```

## New Builtins Required

Added to `base_env` in `lib/eval/eval.ml`:

### Server Builtin (the big one)

```
http_server_listen(port : Int, pipeline : List(Conn -> Conn)) -> Unit
  The entire accept loop + thread spawning, implemented in OCaml.
  1. Unix.socket + Unix.bind(SO_REUSEADDR) + Unix.listen
  2. Loop: Unix.accept → Thread.create(connection_thread) → loop
  3. Each thread: tcp_recv_http → http_parse_request → build Conn →
     eval pipeline → write response → close fd
  4. On crash: catch Eval_error → send 500 → close fd
  Blocks forever (the accept loop). Called from HttpServer.listen().
  Prints "Listening on port {port}" on startup.
```

### HTTP Serialization Builtins

```
http_parse_request(raw : String) -> Result((Method, String, String, List(Header), String), String)
  Parse "GET /path?query HTTP/1.1\r\nHeaders\r\n\r\nBody"
  Returns Ok((method_variant, path, query_string, headers, body)) or Err(msg)
  The builtin converts the method string to a Method variant (Get, Post, etc.)
  Unknown methods return Err.
  Used internally by http_server_listen, but also exposed as a builtin
  for testing and for users who want to build custom servers.

http_serialize_response(status : Int, headers : List(Header), body : String) -> String
  Format "HTTP/1.1 {status} {reason}\r\n{headers}\r\nContent-Length: {len}\r\n\r\n{body}"
  Reason phrase derived from status code (200 → "OK", 404 → "Not Found", etc.)
```

### Existing Builtins Reused

```
tcp_recv_http(fd, max_bytes)   — already implemented for HTTP client; reads until
                                  headers complete, then reads body per Content-Length
                                  or chunked encoding. Works for reading requests too
                                  since HTTP/1.1 framing is symmetric.

tcp_send_all(fd, data)         — already implemented; sends all bytes in a loop.

string_split(s, sep)           — already implemented in eval.ml. Used for
                                  splitting path on "/" to produce path_info.
```

## File Layout

| File | Changes |
|------|---------|
| `lib/eval/dune` | Add `threads` library dependency |
| `lib/eval/eval.ml` | Add `http_server_listen`, `http_parse_request`, `http_serialize_response` builtins; add `Mutex.t` around actor globals; thread-local state via `Thread.key` |
| `stdlib/http_server.march` | New file: `Conn` type, accessors, transforms, pipeline runner, `HttpServer.new`, `HttpServer.plug`, `HttpServer.listen` (calls builtin) |
| `bin/main.ml` | Add `http_server.march` to stdlib load order (after `http.march` for `Header` type) |
| `test/test_march.ml` | Tests for builtins and server module |

## Testing Strategy

### Unit Tests (in test_march.ml)

1. **TCP builtins**: `tcp_listen` returns Ok(fd), `tcp_accept` on non-listening fd returns Err
2. **HTTP parsing**: `http_parse_request` parses well-formed GET/POST, rejects malformed
3. **HTTP serialization**: `http_serialize_response` produces valid HTTP/1.1 response strings
4. **Conn construction**: Build a Conn, read fields back
5. **Conn transforms**: `put_resp_header`, `assign`, `send_resp` modify the right fields
6. **Pipeline execution**: Pipeline stops at halted conn, runs all plugs when not halted

### Integration Tests (March programs)

A test server that:
1. Starts listening on a port
2. Handles concurrent requests (verified by sending multiple curl requests simultaneously)
3. Runs through a pipeline with middleware
4. Sends correct responses per route
5. Sends 500 on a route that deliberately crashes (e.g., division by zero)

Verified by running the server in the background and curling from the test harness.

## Example: Complete Application

```march
mod MyApp do

  -- Middleware: log every request
  fn logger(conn) do
    println(method_to_string(Conn.method(conn)) ++ " " ++ Conn.path(conn))
    conn
  end

  -- Middleware: require auth header, set assign
  fn require_auth(conn) do
    match Conn.get_req_header(conn, "authorization") with
    | Some(token) -> conn |> Conn.assign("token", token)
    | None -> conn |> Conn.text(401, "Unauthorized")
    end
  end

  -- Route handler
  fn router(conn) do
    match (Conn.method(conn), Conn.path_info(conn)) with
    | (Get, [])              -> conn |> Conn.text(200, "Welcome to March!")
    | (Get, ["health"])      -> conn |> Conn.text(200, "ok")
    | (Get, ["users", id])   -> conn |> show_user(id)
    | (Post, ["users"])      -> conn |> create_user()
    | _                      -> conn |> Conn.text(404, "Not Found")
    end
  end

  fn show_user(conn, id) do
    conn |> Conn.json(200, "{\"id\": \"" ++ id ++ "\", \"name\": \"User " ++ id ++ "\"}")
  end

  fn create_user(conn) do
    let body = Conn.req_body(conn)
    conn |> Conn.json(201, body)
  end

  fn main() do
    HttpServer.new(4000)
    |> HttpServer.plug(logger)
    |> HttpServer.plug(require_auth)
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end

end
```

Run: `dune exec march -- examples/http_server.march`
Test: `curl http://localhost:4000/users/42 -H "Authorization: Bearer abc"`
