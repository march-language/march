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
- **Supervision without try/catch** — each connection spawns a supervised task. If the handler crashes, the monitor sends 500. Process isolation is the error boundary.
- **Capabilities thread through closures** — handlers capture only the caps they need. The type signature is the security audit.

## Non-Goals (v1)

- Linear Conn enforcement — type checker supports it, interpreter doesn't enforce at runtime; deferred
- Typestate (`Conn(Pending)` vs `Conn(Sent)`) — needs phantom types, deferred
- Streaming/chunked responses — deferred to v2
- WebSockets — deferred to v2
- HTTPS/TLS — deferred
- HTTP/2 — deferred
- Async scheduler integration — uses synchronous model for now
- Session types on protocols — deferred
- `Cap(Net)` gating on port binding — capabilities not wired into `main()` yet

## Architecture

```
HttpServer.listen(port, pipeline)
  │
  ├── Accept Loop (recursive function)
  │     │
  │     └── For each TCP connection:
  │           │
  │           ├── Spawn handler task
  │           │     └── read_request(fd)
  │           │         build Conn
  │           │         run_pipeline(conn, plugs)
  │           │         write_response(conn)
  │           │
  │           └── Monitor handler task
  │                 └── On Down: send 500, close fd
  │
  └── (loop continues accepting)
```

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

## Supervision: Connection Lifecycle

### Reality Check: Synchronous Interpreter

The current March runtime is **synchronous and single-threaded**. `task_spawn` eagerly evaluates its function and returns the result. There is no concurrent accept loop — connections are handled one at a time, sequentially.

This is fine for v1. The design below works in the synchronous model and is structured so that swapping in async scheduling later requires no changes to user code.

### The Accept Loop

```march
fn accept_loop(listen_fd, pipeline) do
  match tcp_accept(listen_fd) with
  | Ok(client_fd) ->
    handle_connection(client_fd, pipeline)
    accept_loop(listen_fd, pipeline)
  | Err(_) ->
    accept_loop(listen_fd, pipeline)
  end
end
```

### Connection Handler

Handles a single connection: read request, build Conn, run pipeline, write response.

```march
fn handle_connection(fd, pipeline) do
  match tcp_recv_http(fd, 65536) with
  | Err(_) ->
    tcp_close(fd)
  | Ok(raw) ->
    match http_parse_request(raw) with
    | Err(_) ->
      let resp = http_serialize_response(400, [], "Bad Request")
      tcp_send_all(fd, resp)
      tcp_close(fd)
    | Ok((method, path, query, headers, body)) ->
      let path_info = split_path(path)
      let conn = Conn(fd, method, path, path_info, query, headers, body,
                       0, Nil, "", false, Nil)
      let conn = run_pipeline(conn, pipeline)
      write_response(fd, conn)
      tcp_close(fd)
    end
  end
end
```

### Crash Recovery (Runtime-Level)

In the current interpreter, actor message handlers are already wrapped with OCaml-level exception handling — when an actor handler raises, `crash_actor` is called and monitors are notified. The server uses the same mechanism:

**Implementation in eval.ml:** The `handle_connection` call in the accept loop is wrapped at the OCaml level (inside `eval`) with exception handling. If the March handler crashes (division by zero, pattern match failure, etc.), the OCaml evaluator catches the `Eval_error`, sends a 500 response on the fd, closes it, and the accept loop continues.

From the March programmer's perspective, there is no try/catch. If your handler crashes, the server sends a 500 and moves on. This mirrors how Erlang's runtime catches process crashes — it's the VM's job, not user code.

```
Accept loop iteration:
  1. tcp_accept → get fd
  2. Call handle_connection(fd, pipeline)
     a. Handler succeeds → response written, fd closed
     b. Handler crashes → runtime catches, sends 500, closes fd
  3. Loop back to accept
```

### Future: Actor-Based Concurrency (v2)

When the async scheduler is wired in, the accept loop will spawn a Connection actor per request. The actor monitors a handler task. Crash recovery becomes process isolation — the Connection actor gets a `Down(ref, reason)` message (Erlang convention: reason is `"normal"` for clean exit, error string for crashes) and sends 500 on the fd it owns. The accept loop runs concurrently, never blocked by handler execution.

The March user code (plugs, router, middleware) is identical in both models — only the accept loop internals change.

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

### TCP Server Builtins

```
tcp_listen(port : Int) -> Result(Int, String)
  Unix.socket + Unix.bind + Unix.listen
  SO_REUSEADDR for quick restarts
  Returns Ok(listen_fd) or Err(message)

tcp_accept(listen_fd : Int) -> Result(Int, String)
  Unix.accept on the listening socket
  Returns Ok(client_fd) or Err(message)
```

### HTTP Serialization Builtins

```
http_parse_request(raw : String) -> Result((Method, String, String, List(Header), String), String)
  Parse "GET /path?query HTTP/1.1\r\nHeaders\r\n\r\nBody"
  Returns Ok((method_variant, path, query_string, headers, body)) or Err(msg)
  The builtin converts the method string to a Method variant (Get, Post, etc.)
  Unknown methods return Err.

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

string_split(s, sep)           — already implemented in eval.ml. Used for
                                  splitting path on "/" to produce path_info.
```

## File Layout

| File | Changes |
|------|---------|
| `lib/eval/eval.ml` | Add `tcp_listen`, `tcp_accept`, `http_parse_request`, `http_serialize_response` builtins |
| `stdlib/http_server.march` | New file: `Conn` type, accessors, transforms, pipeline runner, accept loop, convenience helpers |
| `bin/main.ml` | Add `http_server.march` to stdlib load order |
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

A simple test server that:
1. Starts listening on a port
2. Accepts one connection
3. Runs it through a pipeline
4. Sends a response
5. Closes and exits

Verified by running the test and curling the port from the test harness.

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
