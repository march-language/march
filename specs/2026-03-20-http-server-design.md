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
- **Supervised connections** — the accept loop tracks all live connection threads. Enforces max connections, idle timeouts, and graceful shutdown. Like Bandit's `DynamicSupervisor` over connection processes, but using an atomic counter + socket timeouts instead of OTP supervision trees.
- **WebSocket via upgrade** — a plug can upgrade an HTTP connection to WebSocket. After the pipeline, the runtime performs the handshake and enters a March message loop. The handler is a recursive function with pattern matching on frames — no callbacks, no traits, just tail recursion.
- **Capabilities thread through closures** — handlers capture only the caps they need. The type signature is the security audit.

## Non-Goals (v1)

- Linear Conn enforcement — type checker supports it, interpreter doesn't enforce at runtime; deferred
- Typestate (`Conn(Pending)` vs `Conn(Sent)`) — needs phantom types, deferred
- Streaming/chunked responses — deferred to v2
- HTTPS/TLS — deferred
- HTTP/2 — deferred
- March-level scheduler integration — concurrency is via OCaml threads, not the March scheduler
- Session types on protocols — deferred
- `Cap(Net)` gating on port binding — capabilities not wired into `main()` yet

## Architecture

Like Bandit: the accept loop runs in the main thread, each connection gets its own OS thread. Unlike fire-and-forget threading, the accept loop **supervises** all spawned threads — tracking active connections, enforcing limits, and supporting graceful shutdown.

```
HttpServer.listen(server)           -- builtin, implemented in OCaml
  │
  ├── tcp_listen(port)              -- bind + listen
  ├── Install SIGTERM handler       -- sets shutdown flag
  │
  └── Accept Loop (OCaml, main thread)
        │
        ├── State:
        │     active : Atomic.t int     -- live connection count
        │     shutdown : Atomic.t bool  -- graceful shutdown flag
        │     max_conns : int           -- from Server config
        │     idle_timeout : float      -- from Server config
        │
        ├── Unix.select [listen_fd] [] [] 1.0   -- 1s timeout for shutdown checks
        │
        ├── if shutdown → stop accepting, drain active connections, exit
        │
        ├── if active >= max_conns → accept, send 503, close (shed load)
        │
        ├── Unix.accept → client_fd
        │     ├── setsockopt SO_RCVTIMEO idle_timeout
        │     └── setsockopt SO_SNDTIMEO idle_timeout
        │
        ├── Atomic.incr active
        │
        ├── Thread.create → connection thread
        │     │
        │     ├── tcp_recv_http(fd)         -- blocks; releases domain lock
        │     │     └── timeout → close fd (idle client)
        │     ├── http_parse_request(raw)
        │     ├── build Conn
        │     ├── eval March pipeline       -- run_pipeline(conn, plugs)
        │     ├── write_response(fd, conn)
        │     └── tcp_close(fd)
        │     │
        │     ├── On crash: catch Eval_error → send 500 → close fd
        │     ├── On timeout: catch Unix_error(EAGAIN) → close fd
        │     └── finally: Atomic.decr active  -- ALWAYS runs
        │
        └── (loop immediately accepts next connection)
```

The accept loop never waits for handlers to finish. While one handler is blocked reading a request body, other connections are being accepted and processed. This is the same model as Bandit's connection process spawning, with the supervision of ThousandIsland's `ConnectionsSupervisor`.

## The Conn Type

Modeled on `%Plug.Conn{}`. Holds everything about a request-response cycle.

```march
type Method = Get | Post | Put | Patch | Delete | Head | Options

type WsFrame = TextFrame(String) | BinaryFrame(String) | Ping | Pong | Close(Int, String)
type WsSocket = WsSocket(Int)  -- wraps fd, opaque to March code

type Upgrade = NoUpgrade | WebSocketUpgrade(WsSocket -> Unit)

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
  List((String, String)),-- assigns (user-defined key-value store)
  Upgrade                -- websocket upgrade (NoUpgrade by default)
)
```

### Conn Accessors

Read fields from the Conn by destructuring and reconstructing. Since Conn is a plain ADT (not linear in v1), these are simple pattern-match extractions.

```march
pub fn method(conn) : Method do
  match conn with | Conn(_, m, _, _, _, _, _, _, _, _, _, _, _) -> m end
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
pub fn upgrade(conn)     : Upgrade
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
|> HttpServer.max_connections(500)
|> HttpServer.idle_timeout(30)
|> HttpServer.plug(log_plug)
|> HttpServer.plug(auth_plug(auth_cap))
|> HttpServer.plug(router)
|> HttpServer.listen()
```

`HttpServer.new` creates a server config with defaults (1000 max connections, 60s idle timeout). `max_connections` and `idle_timeout` configure supervision. Each `plug` appends to the pipeline. `listen` starts the supervised accept loop. The pipe order IS the execution order — first plug runs first.

### The Server Config Type

```march
type Server = Server(
  Int,                -- port
  List(Conn -> Conn), -- pipeline (list of plugs)
  Int,                -- max_connections (default 1000)
  Int                 -- idle_timeout_secs (default 60)
)

pub fn new(port) do
  Server(port, Nil, 1000, 60)
end

pub fn plug(server, p) do
  match server with
  | Server(port, plugs, mc, it) -> Server(port, append(plugs, Cons(p, Nil)), mc, it)
  end
end

pub fn max_connections(server, n) do
  match server with
  | Server(port, plugs, _, it) -> Server(port, plugs, n, it)
  end
end

pub fn idle_timeout(server, secs) do
  match server with
  | Server(port, plugs, mc, _) -> Server(port, plugs, mc, secs)
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

### Supervision

#### How Bandit/Phoenix Does It (for reference)

Bandit runs on ThousandIsland, which structures connections as a supervision tree:

```
ThousandIsland.Supervisor
  ├── Listener (GenServer — owns listen socket)
  ├── AcceptorPoolSupervisor
  │     └── N Acceptors (default 100, each calls :gen_tcp.accept)
  └── ConnectionsSupervisor (DynamicSupervisor)
        ├── Connection Process 1
        ├── Connection Process 2
        └── ...
```

Each connection is a **supervised process** under `DynamicSupervisor`. If a connection crashes, the supervisor cleans up — no resource leak. The supervisor tracks all live connections, enabling graceful shutdown (drain in-flight, refuse new), max connection enforcement, and idle timeouts.

#### How March Does It

We don't have OTP supervision trees, but we get the same properties with simpler machinery: an `Atomic.t` counter, socket timeouts, and a shutdown flag. The accept loop IS the supervisor.

**Crash recovery** — each thread wraps the full request lifecycle in OCaml-level `try ... with`. The `finally` block always decrements the active counter, even on crash:

```ocaml
let connection_thread client_fd active pipeline env =
  Fun.protect
    ~finally:(fun () ->
      Atomic.decr active;
      (try Unix.close client_fd with _ -> ()))
    (fun () ->
      try
        handle_connection client_fd pipeline env
      with
      | Eval_error msg ->
        send_500_response client_fd;
        Printf.eprintf "[march] Handler crash: %s\n%!" msg
      | Unix.Unix_error (Unix.EAGAIN, _, _)
      | Unix.Unix_error (Unix.EWOULDBLOCK, _, _) ->
        (* Idle timeout — client took too long *)
        Printf.eprintf "[march] Connection timed out\n%!"
      | exn ->
        Printf.eprintf "[march] Unexpected: %s\n%!" (Printexc.to_string exn))
```

From the March programmer's perspective: **there is no try/catch.** If your plug pipeline crashes (division by zero, pattern match failure, etc.), the runtime catches it, sends a 500, and closes the connection. Other connections are unaffected. The accept loop never sees the crash.

**Max connections** — the accept loop checks `Atomic.get active >= max_conns` before spawning a thread. If at capacity, it accepts the connection (to clear the kernel backlog) but immediately sends a 503 Service Unavailable and closes:

```ocaml
let client_fd, _addr = Unix.accept listen_fd in
if Atomic.get active >= max_conns then begin
  send_503_response client_fd;
  Unix.close client_fd
end else begin
  Atomic.incr active;
  ignore (Thread.create (connection_thread client_fd active pipeline) env)
end
```

This prevents unbounded thread spawning under load. Bandit achieves the same via `num_connections` in ThousandIsland config.

**Idle timeout** — set on each accepted socket via `SO_RCVTIMEO` and `SO_SNDTIMEO`:

```ocaml
let set_timeouts fd timeout =
  Unix.setsockopt_float fd Unix.SO_RCVTIMEO timeout;
  Unix.setsockopt_float fd Unix.SO_SNDTIMEO timeout
```

If a client is idle longer than the timeout, `Unix.recv` raises `Unix_error(EAGAIN, ...)`, caught by the connection thread. This kills slow-loris connections and prevents thread leaks. Bandit does the same via GenServer timeout on connection processes.

**Graceful shutdown** — a `SIGTERM` handler sets a shutdown flag. The accept loop uses `Unix.select` with a 1-second timeout so it can check the flag between accepts:

```ocaml
let server_loop listen_fd pipeline env max_conns idle_timeout =
  let active = Atomic.make 0 in
  let shutdown = Atomic.make false in
  Sys.set_signal Sys.sigterm
    (Sys.Signal_handle (fun _ -> Atomic.set shutdown true));
  Printf.printf "Listening on port %d (max_conns=%d, idle_timeout=%ds)\n%!"
    port max_conns (int_of_float idle_timeout);
  while not (Atomic.get shutdown) do
    match Unix.select [listen_fd] [] [] 1.0 with
    | (fd :: _, _, _) ->
      let client_fd, _addr = Unix.accept fd in
      set_timeouts client_fd idle_timeout;
      if Atomic.get active >= max_conns then begin
        send_503_response client_fd;
        Unix.close client_fd
      end else begin
        Atomic.incr active;
        ignore (Thread.create
          (connection_thread client_fd active pipeline) env)
      end
    | _ -> () (* select timeout — check shutdown flag *)
  done;
  (* Drain: wait for in-flight connections to finish *)
  Printf.eprintf "[march] Shutting down, draining %d connections...\n%!"
    (Atomic.get active);
  while Atomic.get active > 0 do
    Unix.sleepf 0.1
  done;
  Unix.close listen_fd;
  Printf.eprintf "[march] Server stopped.\n%!"
```

On `SIGTERM`: stop accepting, wait for all in-flight handlers to complete, then exit. Bandit achieves this via `DynamicSupervisor.stop` which sends shutdown to all child processes.

#### Comparison: Bandit vs March Supervision

| Property | Bandit (ThousandIsland) | March |
|----------|------------------------|-------|
| Connection tracking | `DynamicSupervisor` child list | `Atomic.t int` counter |
| Max connections | `num_connections` config | `max_connections` config |
| Idle timeout | GenServer timeout | `SO_RCVTIMEO`/`SO_SNDTIMEO` |
| Crash cleanup | Supervisor traps exit, cleans up | `Fun.protect ~finally` always runs |
| Graceful shutdown | `Supervisor.stop` drains children | `shutdown` flag + drain loop |
| Load shedding | Acceptor pauses when at limit | Accept + 503 + close |
| Restart policy | `:temporary` (no restart) | No restart (same — HTTP is stateless) |
| Observability | `:telemetry` events | Print to stderr (v1), telemetry (v2) |

Note: neither Bandit nor March **restarts** crashed connections. HTTP is stateless — if a request crashes, you send 500 and move on. There's nothing to restart. This is why Bandit uses `restart: :temporary` on connection processes. Our approach matches.

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

From the March programmer's perspective, supervision is invisible. The API is:

```march
HttpServer.new(4000)
|> HttpServer.max_connections(1000)   -- optional, default 1000
|> HttpServer.idle_timeout(30)        -- optional, default 60s
|> HttpServer.plug(logger)
|> HttpServer.plug(router)
|> HttpServer.listen()
```

`listen()` blocks forever (it's the accept loop). Connections are handled concurrently in the background. If a handler crashes, a 500 is sent. If the server hits max connections, new clients get a 503. If a client is idle too long, the connection is closed. On `SIGTERM`, the server drains gracefully. The programmer writes pure `Conn -> Conn` functions and the runtime handles the rest.

### Required OCaml Changes

1. **Add `threads` library** to `lib/eval/dune` dependencies
2. **Add `Mutex.t`** around `actor_registry` and global counters in eval.ml
3. **Implement `http_server_listen` builtin** — the supervised accept loop:
   - `Atomic.t` for active connection count and shutdown flag
   - `Unix.select` with 1s timeout for shutdown responsiveness
   - `SO_RCVTIMEO`/`SO_SNDTIMEO` on accepted sockets for idle timeout
   - Max connection enforcement (503 on overload)
   - `Fun.protect ~finally` in connection threads for crash-safe cleanup
   - `SIGTERM` handler + drain loop for graceful shutdown
4. **Thread-local state** for `module_stack`, `reduction_ctx`, `debug_ctx` using `Thread.key`

### Compiled Mode: LLVM IR (how the server works as native code)

The interpreter (`eval.ml`) is the development path. For production, March compiles to native code:

```
March source → parse → desugar → typecheck → monomorphize → defunctionalize
  → lower to TIR → Perceus RC → escape analysis → LLVM IR → clang → native binary
```

The server architecture is **identical** — but the implementation layer shifts from OCaml to C.

#### What changes when compiled

**Builtins become C runtime functions.** Currently builtins live in `eval.ml` as OCaml functions the interpreter calls. In compiled mode, they're C functions in `march_runtime.c` that the LLVM IR calls directly:

```c
// march_runtime.h additions:
void  march_http_server_listen(void *server_config, void *pipeline);
void *march_ws_recv(int64_t fd);
void  march_ws_send(int64_t fd, void *frame);
void  march_ws_handshake(int64_t fd, void *key);
void *march_http_parse_request(void *raw);
void *march_http_serialize_response(int64_t status, void *headers, void *body);
```

The LLVM emitter (`llvm_emit.ml`) already knows how to map March builtins to C names via `mangle_extern`. The HTTP/WS builtins follow the same pattern:

```ocaml
(* In llvm_emit.ml, extend mangle_extern: *)
| "http_server_listen"     -> "march_http_server_listen"
| "http_parse_request"     -> "march_http_parse_request"
| "http_serialize_response"-> "march_http_serialize_response"
| "ws_recv"                -> "march_ws_recv"
| "ws_send"                -> "march_ws_send"
| "ws_handshake"           -> "march_ws_handshake"
```

**Plug pipeline compiles to native function calls.** After defunctionalization (`lib/tir/defun.ml`), closures become tagged structs with a dispatch function pointer. The pipeline runner:

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

Compiles to: `switch` on list tag → load dispatch pointer from closure struct → indirect `call` → tail-recursive loop. With LLVM's optimization passes, this becomes a tight loop of indirect calls — no interpreter dispatch overhead, no value boxing for primitives.

**Pattern matching compiles to native switch/compare.** The router:

```march
match (Conn.method(conn), Conn.path_info(conn)) with
| (Get, ["users", id]) -> ...
```

Becomes: load tag field at offset 8 → `switch i32` on method tag → nested `switch` on list/string comparisons. LLVM optimizes this into jump tables.

**Conn is a heap struct, not interpreted.** The 13-field Conn compiles to a 120-byte heap object (16-byte header + 13 × 8-byte fields). Accessors compile to `getelementptr` + `load`. Transforms compile to alloc + copy + mutate-field. With Perceus FBIP, the common `conn |> put_resp_header(...) |> send_resp(...)` chain reuses the Conn in-place when its RC = 1 (which it always is in a pipeline, since Conn flows linearly through pipes).

**The accept loop is C code in the runtime.** `march_http_server_listen` in `march_runtime.c` is the same thread-per-connection accept loop, but calling compiled March functions instead of the interpreter:

```c
void march_http_server_listen(void *server_config, void *pipeline) {
    // Extract port, max_conns, idle_timeout from server_config struct
    int64_t port = *(int64_t *)((char *)server_config + 16);
    // ... bind, listen, accept loop ...

    while (!shutdown) {
        int client_fd = accept(listen_fd, ...);
        // Spawn thread, call compiled March pipeline
        pthread_create(&tid, NULL, connection_thread, args);
    }
}

static void *connection_thread(void *arg) {
    // ... recv, parse, build Conn ...

    // Call the compiled defunctionalized dispatch:
    void *result_conn = march_dispatch_pipeline(pipeline, conn);

    // ... serialize response, send, close ...
}
```

**Build command:**
```bash
march --emit-llvm app.march              # produces app.ll
clang -O2 runtime/march_runtime.c app.ll -lpthread -o server
./server                                  # native binary, no interpreter
```

#### Performance impact of compilation

| Component | Interpreted (eval.ml) | Compiled (LLVM) |
|-----------|----------------------|-----------------|
| Plug dispatch | Hashtbl lookup + pattern match on AST | Indirect function call (1 branch) |
| Conn field access | Recursive match on 13-field constructor | `getelementptr` + `load` (1 instruction) |
| Pipeline loop | Interpreter reduces ~50 AST nodes per plug | Tight loop, ~5 native instructions per plug |
| String concat | Allocate March value + OCaml string ops | Direct `memcpy` via `march_string_concat` |
| Pattern match routing | Interpreter walks pattern tree | Jump table via `switch i32` |
| Conn transforms | Alloc new VVariant, copy fields | FBIP in-place rewrite (zero allocation) |
| Per-request overhead | ~100μs interpreter dispatch | ~1-5μs native |

The I/O cost (TCP recv/send) dominates either way. But for compute-heavy handlers (JSON parsing, template rendering, auth token validation), compiled mode is 20-100× faster.

### Scaling to 2 Million Concurrent Connections

Thread-per-connection (v1) tops out at ~10K-50K. Each OS thread costs ~8MB stack. For 2M connections, we need lightweight processes. March already has the infrastructure — it just needs to be wired in.

#### Tier 1: v1 — Thread-per-connection (current spec)

- `Thread.create` (interpreter) or `pthread_create` (compiled)
- ~8MB stack per thread
- Ceiling: ~10K-50K concurrent connections
- Good enough for most applications

#### Tier 2: Compiled + io_uring event loop

Replace thread-per-connection with an event-driven reactor. The compiled runtime uses `io_uring` (Linux) or `kqueue` (macOS) to multiplex all connections onto a small thread pool:

```
N worker threads (= N CPU cores)
  └── Each runs an io_uring event loop
        ├── Accepts new connections (IORING_OP_ACCEPT)
        ├── Reads requests  (IORING_OP_RECV)
        ├── Writes responses (IORING_OP_SEND)
        └── Dispatches to compiled March handlers
              └── Handler runs to completion (non-blocking)
              └── All I/O submitted as io_uring SQEs
```

Memory per connection: ~4KB (recv buffer + Conn struct + response buffer). 2M × 4KB = 8GB — feasible on a single machine.

**The key constraint**: handlers must not block. In compiled mode, `tcp_recv`/`tcp_send` submit io_uring operations and suspend the handler. This requires **stackful coroutines** (see Tier 3).

```c
// march_runtime.c — io_uring reactor
typedef struct {
    int fd;
    void *pipeline;        // compiled March pipeline (defunctionalized)
    void *recv_buf;
    int state;             // ACCEPTING, READING, PROCESSING, WRITING
} march_connection;

void march_io_loop(struct io_uring *ring, void *pipeline, int max_conns) {
    march_connection *conns = calloc(max_conns, sizeof(march_connection));
    // Submit initial accept
    // On completion: submit recv for new fd
    // On recv complete: run compiled pipeline, submit send
    // On send complete: close fd, recycle slot
}
```

#### Tier 3: March lightweight processes (the BEAM model)

The full solution. Each connection is a **March process** — a stackful coroutine with:

- ~2-4KB initial heap (per-process arena, per `specs/gc_design.md`)
- Cooperative scheduling via reduction counting (already in `lib/scheduler/scheduler.ml`)
- Lock-free mailbox for actor messages (already in `lib/scheduler/mailbox.ml`)
- Work-stealing across CPU cores (already in `lib/scheduler/work_pool.ml`)

```
N Domains (= N CPU cores, via compiled Domain.spawn or pthread)
  └── Each domain owns:
        ├── io_uring instance (for async I/O)
        ├── Run queue of March processes
        ├── Work-stealing deque (Chase-Lev, already implemented)
        └── Scheduler loop:
              1. Poll io_uring completions → wake blocked processes
              2. Pick process from run queue (or steal from another domain)
              3. Run process for 4,000 reductions (already implemented)
              4. If process blocks on I/O → submit io_uring SQE, park process
              5. If process yields → re-queue
              6. Loop
```

**Memory budget for 2M connections — naive:**

| Component | Per connection | × 2M |
|-----------|---------------|-------|
| Process heap (arena) | 2KB initial | 4 GB |
| Conn struct | 120 bytes | 240 MB |
| Recv buffer | 4KB | 8 GB |
| Send buffer | 4KB (on demand) | 8 GB peak |
| Process control block | 64 bytes | 128 MB |
| **Total** | **~10KB** | **~20 GB** |

That's wasteful. Let's squeeze it.

**Where the bytes actually go:**

The current object header is 16 bytes: `{rc: i64, tag: i32, pad: i32}`. That means our 13-field Conn is `16 + 13×8 = 120 bytes`. But most of those 16 header bytes are waste — we don't need 64-bit refcounts, and the 4-byte pad is pure alignment slack.

The recv/send buffers at 4KB each are the real killer — 16GB for buffers alone. Most idle WebSocket connections have nothing buffered.

**Optimization 1: Compact object header — 16 bytes → 8 bytes**

```c
// Current: 16 bytes
typedef struct { int64_t rc; int32_t tag; int32_t pad; } march_hdr;

// Optimized: 8 bytes
typedef struct {
    uint32_t rc;     // 4 billion max refs — plenty
    uint16_t tag;    // 65K constructors per type — plenty
    uint16_t flags;  // GC flags, arena color, etc.
} march_hdr_compact;
```

Saves 8 bytes per heap object. For Conn: `8 + 13×8 = 112 bytes`. For every WsFrame, every List cons cell, every Header pair. At 2M connections with ~20 objects average per connection, that's 320MB saved.

But the real win is what this enables for field packing (see below).

**Optimization 2: Conn field packing — 120 bytes → 64 bytes**

The current Conn has 13 fields, all 8 bytes (uniform `i64/ptr` layout). But many fields are small:

```
Current Conn layout (120 bytes):
  [header 16B] [fd:i64] [method:i64] [path:ptr] [path_info:ptr]
  [query:ptr] [headers:ptr] [body:ptr] [status:i64] [resp_hdrs:ptr]
  [resp_body:ptr] [halted:i64] [assigns:ptr] [upgrade:ptr]
```

With the compact header and field-type-aware layout:

```
Packed Conn layout (64 bytes):
  [hdr 8B]
  [fd:i32] [status:i16] [method:u8] [halted:u8]  -- 8 bytes (4 fields!)
  [path:ptr] [path_info:ptr]                       -- 16 bytes
  [query:ptr] [req_headers:ptr]                    -- 16 bytes
  [req_body:ptr] [resp_headers:ptr]                -- 16 bytes  (upgrade tag packed into flags)
```

Wait — we can do better. For WebSocket connections, the Conn is only used during the upgrade handshake. After upgrade, only the `WsSocket(fd)` survives. The Conn gets freed (RC→0, Perceus). So Conn size doesn't matter for idle WS connections at all.

What matters for idle WebSocket connections:

```
Per idle WS connection:
  Process control block     48 bytes  (see below)
  Coroutine stack          512 bytes  (see below)
  WsSocket value             8 bytes  (compact header) + 4 bytes (fd) = 12 bytes
  Handler state args        varies    (but minimal for echo/chat)
  Recv buffer                0 bytes  (allocated on demand by io_uring)
  Send buffer                0 bytes  (allocated on demand)
  ─────────────────────────────────
  Total                   ~580 bytes
```

**Optimization 3: Minimal coroutine stacks — 2KB → 512 bytes**

A WebSocket handler in steady state has a tiny call depth:

```
echo_handler → WebSocket.recv → [suspended on io_uring]
```

That's 2-3 stack frames. Each frame: return address (8B) + saved registers (~48B) + locals. A 512-byte stack handles this easily. Guard page at the bottom catches overflow → `mmap` a bigger stack and copy (like Go's segmented/copyable stacks).

```c
// Growable stack: start tiny, grow on demand
#define INITIAL_STACK_SIZE 512
#define STACK_GUARD_SIZE   4096  // one page

void *march_alloc_stack() {
    // [guard page][512 bytes usable]
    void *mem = mmap(NULL, STACK_GUARD_SIZE + INITIAL_STACK_SIZE,
                     PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    mprotect(mem, STACK_GUARD_SIZE, PROT_NONE);  // guard page
    return mem;
}
```

But wait — 4KB guard page per connection defeats the purpose. Better: use **stackless coroutines**. The March handler compiles to a state machine (LLVM coroutine transform), so there's no stack at all — just a small frame on the process heap.

```c
// Stackless: handler state is a heap struct, not a stack
typedef struct {
    int state;        // resume point (switch label)
    int64_t fd;       // captured from WsSocket
    void *user_state; // handler's recursive args
} march_ws_frame;    // ~24 bytes
```

With LLVM's coroutine lowering (`@llvm.coro.begin`, `@llvm.coro.suspend`), the tail-recursive `echo_handler` compiles to a state machine where `WebSocket.recv` is a suspend point. The "coroutine frame" is just the live variables across the suspend — typically 16-32 bytes.

**Optimization 4: Process control block — 64 bytes → 48 bytes**

```c
typedef struct march_proc {
    uint32_t pid;              // 4B (4 billion PIDs enough)
    uint16_t status;           // 2B
    uint16_t reductions;       // 2B (countdown from 4000, fits u16)
    void *coro_frame;          // 8B (stackless coroutine state)
    void *heap;                // 8B (arena pointer, NULL if no allocs)
    uint32_t heap_used;        // 4B (arena offset)
    uint32_t heap_size;        // 4B (arena capacity)
    march_mailbox *mailbox;    // 8B (NULL if no actor interaction)
    struct march_proc *next;   // 8B (run queue linkage)
} march_proc;                  // = 48 bytes
```

Mailbox is NULL for pure WS handlers (most connections). Arena is NULL until the handler allocates — a simple echo handler allocates nothing (FBIP reuses the frame in-place).

**Optimization 5: Zero-copy recv with io_uring — 0 bytes per idle connection**

With `io_uring` provided buffers (`IORING_OP_PROVIDE_BUFFERS`), the kernel manages a shared buffer pool. Recv doesn't need a per-connection buffer — the kernel picks one from the pool when data arrives, and the connection releases it after processing.

```c
// Shared buffer pool: 1024 buffers × 4KB = 4MB total
// Shared across ALL connections. Only active readers use a buffer.
#define POOL_SIZE 1024
#define BUF_SIZE  4096

void setup_buffer_pool(struct io_uring *ring) {
    void *pool = mmap(NULL, POOL_SIZE * BUF_SIZE, ...);
    io_uring_register_buffers(ring, pool, POOL_SIZE);
    // Submit PROVIDE_BUFFERS for the pool
    struct io_uring_sqe *sqe = io_uring_get_sqe(ring);
    io_uring_prep_provide_buffers(sqe, pool, BUF_SIZE, POOL_SIZE, 0, 0);
}

// recv uses pool buffer — no per-connection allocation
io_uring_prep_recv(sqe, fd, NULL, 0, 0);
sqe->flags |= IOSQE_BUFFER_SELECT;
sqe->buf_group = 0;  // use the shared pool
```

With 1024 buffers shared across 2M connections: 4MB total instead of 8GB. Only connections actively receiving data consume a buffer, and it's returned to the pool immediately after processing.

**Optimization 6: Lazy arena allocation — 0 bytes for simple handlers**

The per-process arena (`heap` pointer) starts NULL. Allocation triggers arena creation. A pure WebSocket echo handler with FBIP reuse allocates nothing — the `TextFrame("Echo: " ++ msg)` reuses the incoming frame's memory. No arena needed.

```c
void *march_proc_alloc(march_proc *proc, int64_t sz) {
    if (!proc->heap) {
        // First allocation: create 1KB arena
        proc->heap = mmap(NULL, 1024, ...);
        proc->heap_size = 1024;
        proc->heap_used = 0;
    }
    // Bump pointer
    void *p = (char *)proc->heap + proc->heap_used;
    proc->heap_used += sz;
    return p;
}
```

**Optimized memory budget:**

| Component | Per idle WS conn | × 2M |
|-----------|-----------------|-------|
| Process control block | 48 bytes | 96 MB |
| Coroutine frame (stackless) | 32 bytes | 64 MB |
| WsSocket value | 12 bytes | 24 MB |
| Arena heap | 0 bytes (lazy, none for echo) | 0 |
| Recv buffer | 0 bytes (shared pool) | 4 MB pool |
| Send buffer | 0 bytes (shared pool) | 4 MB pool |
| Kernel fd | 0 bytes (kernel-side) | ~256 MB kernel |
| **Userspace total** | **~92 bytes** | **~184 MB** |
| **With kernel** | | **~440 MB** |

**That's 2 million WebSocket connections in under 512MB.** On a 16GB machine. The kernel fd table (~128 bytes per fd) and socket buffers (~128 bytes per socket with `SO_RCVBUF` minimized) are the floor — everything else is squeezed to near-zero.

**Comparison:**

| Runtime | Per idle WS conn | 2M connections |
|---------|-----------------|----------------|
| Phoenix/BEAM | ~2-3 KB | ~4-6 GB |
| Go (goroutine) | ~4-8 KB | ~8-16 GB |
| March (naive) | ~10 KB | ~20 GB |
| March (optimized) | **~92 bytes** | **~184 MB** |
| Theoretical min (just fds) | ~128 bytes | ~256 MB |

March beats BEAM by 20-30× per connection because:
1. **Stackless coroutines** — no per-process stack (BEAM allocates ~2KB per process)
2. **FBIP in-place reuse** — simple handlers allocate zero heap
3. **io_uring buffer pools** — no per-connection recv buffer
4. **Compact headers** — 8-byte object headers vs BEAM's tagged word per value
5. **Compiled native code** — no bytecode interpreter state per process

#### What we give up for 92 bytes (tradeoffs)

**1. Server-push is broken — the big one**

The broadcasting example in the WebSocket section doesn't actually work:

```march
fn chat_loop(room_pid, socket) do
  match WebSocket.recv(socket) with    -- blocked here forever
  | TextFrame(msg) ->
    Actor.send(room_pid, Broadcast(msg))  -- sends TO the room
    chat_loop(room_pid, socket)
  | ...
```

The handler suspends on `WebSocket.recv(socket)`. While suspended, the room actor calls `WebSocket.send(s, frame)` to push a message to this connection. But who executes that send? The handler process is parked. There's no way to wake it — it's waiting for a *client* frame, not an actor message.

BEAM doesn't have this problem. Each Erlang process has a single mailbox that receives both network I/O and internal messages. `receive` can pattern-match on either. March's `recv` blocks on one fd.

**Solutions, with memory impact:**

**(a) `select` builtin — wait on fd OR mailbox**

Add `WebSocket.select(socket, timeout)` that suspends until either a WebSocket frame arrives OR an actor message arrives:

```march
type SelectResult = WsData(WsFrame) | ActorMsg(Msg) | Timeout

fn chat_loop(room_pid, socket) do
  match WebSocket.select(socket, 30000) with
  | WsData(TextFrame(msg)) ->
    Actor.send(room_pid, Broadcast(msg))
    chat_loop(room_pid, socket)
  | ActorMsg(Push(frame)) ->
    WebSocket.send(socket, frame)
    chat_loop(room_pid, socket)
  | WsData(Close(_, _)) ->
    Actor.send(room_pid, Leave(socket))
  | Timeout ->
    WebSocket.send(socket, Ping)
    chat_loop(room_pid, socket)
  | _ -> chat_loop(room_pid, socket)
  end
end
```

Runtime implementation: the io_uring loop watches both the socket fd and the process mailbox (via an `eventfd` that the mailbox signals on enqueue). Wakes the process on whichever fires first.

Memory cost: +8 bytes per process for the eventfd. Total: **~100 bytes/conn**. The mailbox pointer (already in the PCB) is no longer NULL — but the mailbox itself is a lock-free linked list head, so it's 8 bytes until the first message.

This is the right answer. It's how Go's `select` works, how Erlang's `receive` works, and how every serious concurrent system handles multiplexed waiting. The cost is small and the capability is essential.

**(b) Two processes per connection (reader + writer)**

Split each WebSocket connection into a reader process (blocks on recv) and a writer process (blocks on mailbox). The room actor sends to the writer. The reader forwards client messages to the room.

Memory cost: 2 × 92 = **~184 bytes/conn**. Doubles connection count toward max. More complex, no real advantage over (a).

**(c) Non-blocking poll loop**

`WebSocket.try_recv(socket) : Option(WsFrame)` returns immediately. Handler polls in a loop with a sleep. Wasteful — burns CPU proportional to connection count. Defeats the purpose of io_uring. Rejected.

**Recommendation: option (a).** `select` is the primitive. It costs 8 bytes and enables the full pub/sub pattern. Without it, March WebSockets are read-only — fundamentally less capable than Phoenix Channels.

**2. FBIP doesn't save as much as claimed**

The spec says "a pure echo handler allocates nothing." Let's check:

```march
WebSocket.send(socket, TextFrame("Echo: " ++ msg))
```

- `"Echo: " ++ msg` — string concat. Output is longer than either input. Neither input string can be reused in-place. This **allocates a new string**.
- `TextFrame(...)` — wraps the string. Perceus can reuse the incoming `TextFrame`'s memory (same size, RC=1). This is **zero-cost via FBIP**.

So even the simplest echo handler allocates one string per message. The arena isn't zero — it's ~100 bytes per message processed. For an *idle* connection (no messages flowing), it's still zero. But under load, the lazy arena kicks in and grows.

Real handlers allocate more: JSON serialization, string building, list manipulation. The arena will grow to 1-4KB for realistic workloads. Still much less than BEAM (which allocates per-word), but not zero.

**Honest per-connection budget under moderate load:**

| Component | Idle | Active (10 msg/s) |
|-----------|------|-------------------|
| Process control block | 48B | 48B |
| Coroutine frame | 32B | 32B |
| WsSocket | 12B | 12B |
| eventfd (for select) | 8B | 8B |
| Arena heap | 0B | 1-4 KB |
| Mailbox | 8B (empty head) | 8B + messages |
| **Total** | **~108B** | **~1-4 KB** |

Active connections converge toward BEAM-like memory per connection. The win is that *idle* connections (the vast majority in a 2M-connection deployment) stay near 108 bytes.

**3. Stackless coroutines limit handler complexity**

LLVM's `@llvm.coro.*` transforms compile the handler into a state machine. Every `recv`/`send`/`select` call is a suspend point. The coroutine frame holds only the variables live across suspension.

This works perfectly for:
```march
fn handler(socket) do
  match WebSocket.recv(socket) with   -- suspend point
  | ... -> WebSocket.send(socket, ...) -- suspend point
  end
  handler(socket)                      -- tail call, no stack growth
end
```

This breaks for:
- **Deep recursion inside a handler** — if you call a recursive function between suspend points, that recursion uses the coroutine's stack. But there is no stack — it's a state machine. LLVM would need to heap-allocate the recursive frames, which is expensive.
- **Calling arbitrary library code** — a function 10 calls deep that does blocking I/O needs all 10 frames preserved across the suspend. The coroutine frame explodes.
- **Multiple suspend points in complex control flow** — conditionals, loops, and nested matches with suspend points in different branches create large state machines with many live-variable sets. The coroutine frame grows.

**Fallback**: handlers that exceed the stackless model fall back to stackful coroutines (512B-2KB initial stack, growable). The runtime detects this at compile time — if the coroutine frame would exceed a threshold (e.g., 256 bytes), use a stack instead. Memory per connection: ~600B-2KB instead of 92B. Still better than a full OS thread.

**4. io_uring is Linux-only**

`io_uring` requires Linux 5.1+. The shared buffer pool (`IORING_OP_PROVIDE_BUFFERS`) requires Linux 5.7+. There is no equivalent on macOS or Windows.

Fallback:
- **macOS**: `kqueue` + per-connection 4KB buffer (back to ~4KB/conn)
- **Windows**: IOCP + per-connection buffer (same)
- The optimization stack degrades gracefully: stackless coroutines and compact headers still work, only the zero-copy buffer pool is platform-specific

**5. Shared buffer pool contention under burst**

The pool has 1024 buffers. If 2000 connections receive data simultaneously, 976 of them must wait for a buffer to be released. Under sustained burst, this creates head-of-line blocking.

Mitigation: size the pool for expected peak concurrency, not total connections. Most real workloads have <10% of connections active at any instant. For 2M connections with 5% active = 100K active, a 100K-buffer pool = 400MB. Still far below the naive 8GB.

**6. Compact header is a pervasive change**

Switching from 16-byte to 8-byte headers touches:
- `march_runtime.c` — all allocation, RC, and field access
- `llvm_emit.ml` — all `getelementptr` offsets, header stores, tag loads
- `perceus.ml` — RC operation sizes
- Every TIR pass that emits memory operations

This is ~2 weeks of work and affects every benchmark. It should be done, but it's a separate project from the HTTP server.

**7. Debugging stackless coroutines is hard**

A crashed stackless handler has no stack trace — just a state number in the coroutine frame. "Crashed in state 7 of echo_handler" is not a useful error message. Need to emit a state→source-location map at compile time for diagnostics. BEAM doesn't have this problem because every process has a real call stack.

#### Summary: what 92 bytes actually costs

| Trade-off | Impact | Mitigation |
|-----------|--------|------------|
| No server-push | **Severe** — broadcasting broken | Add `select` builtin (+8B/conn) |
| FBIP not zero under load | Moderate — 1-4KB active | Lazy arena, still < BEAM |
| Stackless limits handler complexity | Moderate — simple handlers only | Fallback to stackful (512B-2KB) |
| Linux-only buffer pools | Moderate — macOS/Win degrade | Graceful fallback to per-conn buffers |
| Buffer pool contention | Low — size pool for peak active % | Tunable pool size |
| Compact header is pervasive | Low — engineering cost, not design | Separate project |
| No stack traces | Low — debugging only | State→location map |

**The honest number**: ~108 bytes idle (with `select`), 1-4KB active. Still 2-3× better than BEAM idle, comparable active. The real advantage is that most connections in a 2M deployment are idle — and idle is where March dominates.

A 64GB machine comfortably handles **2M active connections with room for application state**, or **10M+ idle connections** at the theoretical limit.

**How March processes suspend on I/O:**

In compiled mode, `ws_recv(fd)` doesn't actually block. It:

1. Submits an `IORING_OP_RECV` to the io_uring ring
2. Sets the process state to `PWaiting`
3. Yields to the scheduler (returns from the reduction loop)
4. When the CQE arrives, the scheduler wakes the process
5. The process resumes with the received data

From the March programmer's perspective, `WebSocket.recv(socket)` still looks blocking. The compiled runtime makes it async under the hood — exactly how BEAM makes `receive` look blocking while multiplexing millions of processes.

**Implementation in compiled C runtime:**

```c
// Process structure (compiled mode)
typedef struct march_proc {
    int64_t pid;
    int status;                    // PReady, PRunning, PWaiting, PDone
    void *stack;                   // coroutine stack (2KB initial, growable)
    void *heap;                    // per-process arena
    int64_t heap_size;
    int64_t reductions;            // countdown, yields at 0
    march_mailbox *mailbox;        // lock-free MPSC queue
    struct march_proc *next;       // intrusive linked list for run queue
} march_proc;

// Suspend on I/O — called from compiled march_ws_recv
void *march_ws_recv(int64_t fd) {
    march_proc *self = march_current_proc();
    // Submit io_uring recv
    struct io_uring_sqe *sqe = io_uring_get_sqe(self->ring);
    io_uring_prep_recv(sqe, fd, self->recv_buf, BUF_SIZE, 0);
    io_uring_sqe_set_data(sqe, self);  // wake this process on completion
    io_uring_submit(self->ring);
    // Suspend
    self->status = PWaiting;
    march_yield();                     // longjmp back to scheduler
    // Resumed here after CQE arrives
    return march_build_ws_frame(self->recv_buf, self->recv_len);
}
```

#### The March user code never changes

This is the critical design property. All three tiers run the same March source:

```march
fn echo_handler(socket) do
  match WebSocket.recv(socket) with
  | TextFrame(msg) ->
    WebSocket.send(socket, TextFrame("Echo: " ++ msg))
    echo_handler(socket)
  | Close(_, _) -> ()
  | _ -> echo_handler(socket)
  end
end
```

| | v1 (interpreter) | v1 (compiled) | v2 (compiled + processes) |
|---|---|---|---|
| `WebSocket.recv` | OCaml `Unix.recv` blocks thread | C `recv()` blocks pthread | `io_uring_prep_recv` + yield |
| Connection unit | OS thread (8MB) | OS thread (8MB) | March process (2KB) |
| Max connections | ~50K | ~50K | ~2M+ |
| Handler execution | Interpreter dispatch | Native instructions | Native instructions |
| Scheduling | OS scheduler | OS scheduler | March scheduler (reduction-counted) |

#### What already exists vs. what's needed

**Already implemented:**
- Reduction counter + cooperative scheduling (`lib/scheduler/scheduler.ml`)
- Lock-free mailbox (`lib/scheduler/mailbox.ml`)
- Chase-Lev work-stealing deques (`lib/scheduler/work_pool.ml`)
- Per-actor arena design (`specs/gc_design.md`, Layer 3)
- LLVM IR emission with builtin mangling (`lib/tir/llvm_emit.ml`)
- C runtime with allocation, RC, actors (`runtime/march_runtime.c`)
- Perceus RC with FBIP reuse (`lib/tir/perceus.ml`)

**Needed for Tier 2 (event loop):**
- `io_uring`/`kqueue` wrapper in `march_runtime.c`
- Non-blocking I/O variants of TCP builtins
- Connection state machine in C

**Needed for Tier 3 (2M connections):**
- LLVM coroutine lowering for stackless suspend/resume (`@llvm.coro.*`)
- Wire scheduler into compiled runtime (C port of `scheduler.ml`)
- Per-process lazy arena allocator in C (replaces `calloc` in `march_alloc`)
- `io_uring` provided buffers (shared buffer pool, zero per-connection buffers)
- Process-aware io_uring integration
- Compact 8-byte object header (`{rc:u32, tag:u16, flags:u16}`)
- Fallback: stackful coroutines for handlers with deep call stacks

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

## WebSocket Support

### How Phoenix/Bandit Does It (for reference)

In Phoenix, WebSocket flows through three layers:

1. **Plug level** — `Plug.Conn` has an `upgrade` field. A plug sets it to `{:websocket, handler, opts}`
2. **Bandit level** — after the plug pipeline returns, Bandit checks `conn.upgrade`. If websocket, it sends 101, then switches the connection process from HTTP mode to WebSocket frame mode. The process stays alive.
3. **Phoenix level** — `Phoenix.Socket` and `Phoenix.Channel` provide a GenServer-based handler with `handle_in/3`, `handle_info/2` callbacks

March doesn't need the Phoenix layer. We operate at the Plug/Bandit layer — upgrade detection, handshake, and a message loop.

### The March Model: Upgrade + Recursive Handler

WebSocket breaks `Conn -> Conn`. HTTP is one request, one response. WebSocket is a long-lived bidirectional stream. The solution: a plug marks the conn for upgrade, and the runtime enters a **March-level message loop** instead of closing the fd.

The handler isn't a callback object. It's a function `WsSocket -> Unit` that uses tail recursion and pattern matching — the most natural March idiom for a long-lived loop.

### Upgrade Flow

```
1. HTTP request arrives with Upgrade: websocket headers
2. Normal plug pipeline runs (auth, logging, etc.)
3. Router plug calls WebSocket.upgrade(conn, handler)
   → stores handler in Conn's upgrade field, marks halted
4. Pipeline returns to runtime
5. Runtime checks conn.upgrade:
   - NoUpgrade → normal HTTP response (existing path)
   - WebSocketUpgrade(handler) → WebSocket handshake:
     a. Validate Sec-WebSocket-Key header
     b. Compute Sec-WebSocket-Accept (SHA-1 + base64)
     c. Send "HTTP/1.1 101 Switching Protocols" response
     d. Call handler(WsSocket(fd))
     e. Handler runs until close/crash
     f. Thread stays alive for WS lifetime
     g. On return or crash: close fd, decr active count
```

The plug pipeline still runs for WebSocket connections. Auth, logging, rate limiting — all apply before the upgrade. This is the same design as Bandit: the upgrade is detected after the pipeline, not before.

### Types

```march
type WsFrame = TextFrame(String)
             | BinaryFrame(String)
             | Ping
             | Pong
             | Close(Int, String)  -- status code + reason

type WsSocket = WsSocket(Int)  -- opaque handle wrapping fd
```

### WebSocket API (March-side)

```march
-- Upgrade a conn to websocket. Handler is called after handshake.
-- Validates upgrade headers, marks conn as halted.
pub fn upgrade(conn, handler : WsSocket -> Unit) : Conn do
  match Conn.get_req_header(conn, "upgrade") with
  | Some("websocket") ->
    match conn with
    | Conn(fd, m, p, pi, qs, rh, rb, _, _, _, _, assigns, _) ->
      Conn(fd, m, p, pi, qs, rh, rb, 101, [], "", true, assigns,
           WebSocketUpgrade(handler))
    end
  | _ ->
    conn |> Conn.text(400, "Not a WebSocket request")
  end
end

-- Receive a frame (blocks until one arrives)
-- Builtin: ws_recv(fd) -> WsFrame
pub fn recv(socket) : WsFrame do
  match socket with
  | WsSocket(fd) -> ws_recv(fd)
  end
end

-- Send a frame
-- Builtin: ws_send(fd, frame) -> Unit
pub fn send(socket, frame) : Unit do
  match socket with
  | WsSocket(fd) -> ws_send(fd, frame)
  end
end

-- Send a close frame and close the connection
pub fn close(socket, code, reason) : Unit do
  send(socket, Close(code, reason))
end

-- Multiplex: wait on socket OR actor mailbox OR timeout
-- This is the key primitive for server-push and broadcasting.
-- Without it, handlers can only react to client messages.
type SelectResult = WsData(WsFrame) | ActorMsg(Any) | Timeout

pub fn select(socket, timeout_ms) : SelectResult do
  match socket with
  | WsSocket(fd) -> ws_select(fd, timeout_ms)
  end
end
```

### Handler Pattern: Tail-Recursive Message Loop

The idiomatic March WebSocket handler uses tail recursion with pattern matching. No callbacks, no GenServer — just a function that loops.

```march
fn echo_handler(socket) do
  echo_loop(socket)
end

fn echo_loop(socket) do
  match WebSocket.recv(socket) with
  | TextFrame(msg) ->
    WebSocket.send(socket, TextFrame("Echo: " ++ msg))
    echo_loop(socket)
  | BinaryFrame(data) ->
    WebSocket.send(socket, BinaryFrame(data))
    echo_loop(socket)
  | Ping ->
    WebSocket.send(socket, Pong)
    echo_loop(socket)
  | Close(_, _) ->
    println("Client disconnected")
  | Pong -> echo_loop(socket)
  end
end
```

### Stateful Handler: Thread State Through Recursion

For handlers that maintain state (chat rooms, game sessions), thread it through the recursive call:

```march
fn chat_handler(socket) do
  WebSocket.send(socket, TextFrame("Welcome to chat!"))
  chat_loop(socket, [])
end

fn chat_loop(socket, history) do
  match WebSocket.recv(socket) with
  | TextFrame(msg) ->
    let entry = (msg, history)
    WebSocket.send(socket, TextFrame("You said: " ++ msg))
    chat_loop(socket, Cons(msg, history))
  | Close(_, _) ->
    println("Client left. Messages: " ++ int_to_string(length(history)))
  | Ping ->
    WebSocket.send(socket, Pong)
    chat_loop(socket, history)
  | _ -> chat_loop(socket, history)
  end
end
```

### Broadcasting: WebSockets + Actors (using `select`)

For multi-client scenarios (chat rooms, live updates), the handler must wait on *both* the WebSocket fd and actor messages simultaneously. This requires `WebSocket.select` — without it, server-push is impossible (see Tradeoffs section).

```march
type ChatMsg = Push(WsFrame) | ServerClose

fn chat_handler(room_pid, socket) do
  Actor.send(room_pid, Join(self()))
  chat_loop(room_pid, socket)
end

fn chat_loop(room_pid, socket) do
  match WebSocket.select(socket, 30000) with
  | WsData(TextFrame(msg)) ->
    -- Client sent a message — tell room to broadcast
    Actor.send(room_pid, Broadcast(msg))
    chat_loop(room_pid, socket)
  | WsData(Close(_, _)) ->
    Actor.send(room_pid, Leave(self()))
  | WsData(Ping) ->
    WebSocket.send(socket, Pong)
    chat_loop(room_pid, socket)
  | ActorMsg(Push(frame)) ->
    -- Room pushed a message — forward to this client
    WebSocket.send(socket, frame)
    chat_loop(room_pid, socket)
  | ActorMsg(ServerClose) ->
    WebSocket.close(socket, 1000, "Server shutting down")
  | Timeout ->
    -- Keepalive
    WebSocket.send(socket, Ping)
    chat_loop(room_pid, socket)
  | _ -> chat_loop(room_pid, socket)
  end
end

-- Room actor: maintains list of connected pids, broadcasts to all
fn room_actor(members) do
  receive do
  | Join(pid) -> room_actor(Cons(pid, members))
  | Leave(pid) -> room_actor(remove(members, pid))
  | Broadcast(msg) ->
    let frame = TextFrame(msg)
    each(members, fn(pid) do Actor.send(pid, Push(frame)) end)
    room_actor(members)
  end
end
```

`WebSocket.select(socket, timeout)` suspends the process until either:
- A WebSocket frame arrives on the socket → returns `WsData(frame)`
- An actor message arrives in the process mailbox → returns `ActorMsg(msg)`
- The timeout expires → returns `Timeout`

Under the hood: the io_uring loop watches the socket fd *and* the process's eventfd (signaled when the mailbox is non-empty). Whichever fires first wakes the process.

This is the March equivalent of Phoenix Channels + PubSub. The room actor is the channel, `Actor.send` is the PubSub, and `select` multiplexes network + actor I/O like BEAM's `receive`. No framework — just actors, functions, and `select`.

### Routing WebSocket Connections

WebSocket routes are just plug branches that call `WebSocket.upgrade`:

```march
fn router(conn) do
  match (Conn.method(conn), Conn.path_info(conn)) with
  | (Get, ["ws", "echo"])  -> conn |> WebSocket.upgrade(echo_handler)
  | (Get, ["ws", "chat"])  -> conn |> WebSocket.upgrade(chat_handler(room_pid))
  | (Get, [])              -> conn |> Conn.text(200, "Hello!")
  | _                      -> conn |> Conn.text(404, "Not found")
  end
end
```

Auth middleware runs before the router, so WebSocket connections go through the same auth pipeline as HTTP requests. If auth fails and halts the conn, the WebSocket upgrade never happens.

### Runtime Implementation (OCaml side)

After the plug pipeline returns, the runtime checks the upgrade field:

```ocaml
let handle_connection client_fd pipeline env =
  let raw = tcp_recv_http client_fd in
  let conn = build_conn client_fd raw in
  let result_conn = eval_pipeline conn pipeline env in
  match get_upgrade result_conn with
  | NoUpgrade ->
    (* Normal HTTP: write response, close *)
    let response = serialize_response result_conn in
    tcp_send_all client_fd response;
    Unix.close client_fd
  | WebSocketUpgrade handler ->
    (* WebSocket: handshake, then enter handler *)
    let key = get_header result_conn "sec-websocket-key" in
    ws_send_handshake client_fd key;
    (* Remove socket timeout — WS connections are long-lived *)
    Unix.setsockopt_float client_fd Unix.SO_RCVTIMEO 0.0;
    Unix.setsockopt_float client_fd Unix.SO_SNDTIMEO 0.0;
    (* Call the March handler — blocks until it returns *)
    eval_apply handler [VVariant ("WsSocket", [VInt (Obj.magic client_fd)])] env
    (* Thread cleanup happens in Fun.protect ~finally *)
```

The WebSocket handshake (RFC 6455 §4.2.2):
```ocaml
let ws_send_handshake fd key =
  let magic = "258EAFA5-E914-47DA-95CA-5AB5DC76E45B" in
  let accept = Base64.encode (Sha1.string (key ^ magic)) in
  let response = Printf.sprintf
    "HTTP/1.1 101 Switching Protocols\r\n\
     Upgrade: websocket\r\n\
     Connection: Upgrade\r\n\
     Sec-WebSocket-Accept: %s\r\n\r\n" accept in
  tcp_send_all fd response
```

### WebSocket Frame Protocol (OCaml builtins)

RFC 6455 frames — implemented as OCaml builtins, exposed to March:

```
ws_recv(fd : Int) -> WsFrame
  Read one WebSocket frame from fd.
  - Reads 2-byte header (FIN, opcode, MASK, payload length)
  - Reads extended length if needed (16-bit or 64-bit)
  - Reads 4-byte mask key (client→server frames are always masked)
  - Reads and unmasks payload
  - Maps opcode to WsFrame variant:
    0x1 → TextFrame(payload)
    0x2 → BinaryFrame(payload)
    0x8 → Close(status_code, reason)
    0x9 → Ping
    0xA → Pong
  - Handles continuation frames (opcode 0x0) by buffering

ws_send(fd : Int, frame : WsFrame) -> Unit
  Encode and send one WebSocket frame.
  - Server→client frames are NOT masked (per RFC 6455)
  - Maps WsFrame variant to opcode
  - Writes header + payload length + payload
  - Handles frames > 125 bytes (extended length encoding)
```

### Supervision for WebSocket Connections

WebSocket connections are long-lived — they stay in the connection count and are subject to the same supervision as HTTP:

- **Active count**: the thread stays alive (and counted) for the WS lifetime
- **Max connections**: WS connections consume slots. A server with `max_connections(1000)` can hold at most 1000 concurrent HTTP + WS connections combined
- **Idle timeout**: disabled after upgrade (WS connections are expected to be long-lived). Ping/pong provides liveness checking instead — the runtime auto-responds to pings at the OCaml level
- **Crash recovery**: if the March handler crashes, `Fun.protect ~finally` still runs — fd closed, counter decremented
- **Graceful shutdown**: WS handlers receive a `Close` frame when the server drains (the drain loop sends close frames to all upgraded connections before waiting)

### Comparison: Phoenix Channels vs March WebSocket

| Feature | Phoenix | March |
|---------|---------|-------|
| Handler model | GenServer callbacks (`handle_in`, `handle_info`) | Recursive function with pattern match on `recv` |
| State | GenServer state (socket.assigns) | Function arguments (threaded through recursion) |
| Broadcasting | PubSub (`broadcast/3`) | Actor that holds socket list + `each` |
| Room/topic multiplexing | Built-in topic routing | Just function arguments + actors |
| Presence tracking | `Phoenix.Presence` (CRDT) | Actor with join/leave messages (v1) |
| Auth | Socket-level `connect/3` | Same plug pipeline as HTTP |
| Transport | Configurable (WS, long-poll) | WebSocket only (v1) |

### Non-Goals for WebSocket (v1)

- **Per-message compression** (`permessage-deflate`) — deferred
- **Subprotocol negotiation** (`Sec-WebSocket-Protocol`) — deferred
- **Binary frame streaming** (fragmented frames > memory) — deferred
- **Long-poll fallback** — WebSocket only
- **Session types** — compile-time protocol verification is a v2 goal

## New Builtins Required

Added to `base_env` in `lib/eval/eval.ml`:

### Server Builtin (the big one)

```
http_server_listen(port : Int, pipeline : List(Conn -> Conn),
                   max_conns : Int, idle_timeout : Int) -> Unit
  The entire accept loop + thread spawning + supervision, implemented in OCaml.
  1. Unix.socket + Unix.bind(SO_REUSEADDR) + Unix.listen
  2. Install SIGTERM handler (sets shutdown flag)
  3. Loop: Unix.select(1s timeout) → check shutdown → check max_conns →
     Unix.accept → set SO_RCVTIMEO/SO_SNDTIMEO → Atomic.incr active →
     Thread.create(connection_thread) → loop
  4. Each thread: tcp_recv_http → http_parse_request → build Conn →
     eval pipeline → write response → close fd → Atomic.decr active
  5. On crash: catch Eval_error → send 500 → close fd → decr active
  6. On timeout: catch EAGAIN → close fd → decr active
  7. On max_conns: accept → send 503 → close fd (no thread spawned)
  8. On shutdown: stop accepting, drain (wait for active=0), close listen_fd
  Blocks forever (the accept loop). Called from HttpServer.listen().
  Prints "Listening on port {port} (max_conns=N, idle_timeout=Ns)" on startup.
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

### WebSocket Builtins

```
ws_recv(fd : Int) -> WsFrame
  Read and decode one WebSocket frame (RFC 6455).
  Blocks until a frame arrives. Unmasks client payload.
  Maps opcode → WsFrame variant. Handles continuation frames.

ws_send(fd : Int, frame : WsFrame) -> Unit
  Encode and send one WebSocket frame. No masking (server→client).
  Maps WsFrame variant → opcode. Handles extended length encoding.

ws_handshake(fd : Int, key : String) -> Unit
  Send 101 Switching Protocols with computed Sec-WebSocket-Accept.
  Called internally by the runtime after pipeline upgrade detection.
  Also exposed as a builtin for custom server implementations.

ws_select(fd : Int, timeout_ms : Int) -> SelectResult
  Suspend until a WebSocket frame arrives on fd, an actor message
  arrives in the current process's mailbox, or timeout expires.
  Implementation: io_uring watches fd + process eventfd.
  Returns WsData(frame), ActorMsg(msg), or Timeout.
  This is the key primitive enabling server-push and pub/sub.
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
| `lib/eval/eval.ml` | Add `http_server_listen`, `http_parse_request`, `http_serialize_response`, `ws_recv`, `ws_send`, `ws_handshake` builtins; add `Mutex.t` around actor globals; thread-local state via `Thread.key`; WebSocket upgrade detection after pipeline |
| `stdlib/http_server.march` | New file: `Conn` type (with Upgrade field), accessors, transforms, pipeline runner, `HttpServer.new`, `HttpServer.plug`, `HttpServer.listen` (calls builtin) |
| `stdlib/websocket.march` | New file: `WsFrame`, `WsSocket`, `WebSocket.upgrade`, `WebSocket.recv`, `WebSocket.send`, `WebSocket.close` |
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
7. **WebSocket handshake**: `ws_handshake` produces valid `Sec-WebSocket-Accept`
8. **WebSocket framing**: `ws_recv` decodes masked text/binary/close/ping frames; `ws_send` encodes them
9. **WebSocket upgrade detection**: Conn with `WebSocketUpgrade` triggers handshake path

### Integration Tests (March programs)

A test server that:
1. Starts listening on a port
2. Handles concurrent requests (verified by sending multiple curl requests simultaneously)
3. Runs through a pipeline with middleware
4. Sends correct responses per route
5. Sends 500 on a route that deliberately crashes (e.g., division by zero)
6. Returns 503 when at max connections (set low, e.g., 2, then send 3+ concurrent)
7. Closes idle connections after timeout (set low, e.g., 2s, connect and wait)
8. Shuts down gracefully on SIGTERM (send requests, SIGTERM, verify in-flight complete)
9. WebSocket echo: connect with wscat, send text, verify echo response
10. WebSocket + auth: verify upgrade fails without auth header
11. WebSocket broadcast: two clients connect to chat room, one sends, both receive

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
    | (Get, ["ws", "echo"])  -> conn |> WebSocket.upgrade(echo_handler)
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

  -- WebSocket echo handler
  fn echo_handler(socket) do
    match WebSocket.recv(socket) with
    | TextFrame(msg) ->
      WebSocket.send(socket, TextFrame("Echo: " ++ msg))
      echo_handler(socket)
    | Close(_, _) -> ()
    | Ping ->
      WebSocket.send(socket, Pong)
      echo_handler(socket)
    | _ -> echo_handler(socket)
    end
  end

  fn main() do
    HttpServer.new(4000)
    |> HttpServer.max_connections(500)
    |> HttpServer.idle_timeout(30)
    |> HttpServer.plug(logger)
    |> HttpServer.plug(require_auth)
    |> HttpServer.plug(router)
    |> HttpServer.listen()
  end

end
```

Run: `dune exec march -- examples/http_server.march`
Test: `curl http://localhost:4000/users/42 -H "Authorization: Bearer abc"`
