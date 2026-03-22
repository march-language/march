# March HTTP and Networking Features

## Overview

March provides a comprehensive, layered HTTP and WebSocket implementation spanning three layers:

1. **Layer 1 (Http)**: Pure data types for HTTP requests/responses, URL parsing, and header manipulation
2. **Layer 2 (HttpTransport)**: Low-level TCP connection and raw HTTP/1.1 request-response exchange
3. **Layer 3 (HttpClient)**: High-level composable client with step pipeline, redirects, retries, and streaming

Additionally, March provides an **HTTP server** (via HttpServer module) with request/response handling, Plug-style middleware, and WebSocket upgrade support. The entire stack is implemented with both March stdlib and a C runtime for performance-critical operations.

## Architecture Layers

### Layer 1: Http Module (`stdlib/http.march`)

Pure data types with no I/O. All HTTP libraries depend on this.

**Key Types** (lines 7-21):
- `Method` (line 9): Get | Post | Put | Patch | Delete | Head | Options | Trace | Connect | Other(String)
- `Scheme` (line 11): SchemeHttp | SchemeHttps
- `Status` (line 13): Status(Int)
- `Header` (line 15): Header(String, String)
- `Request(body)` (line 19): Full request with method, scheme, host, port, path, query, headers, and body
- `Response(body)` (line 21): Response with status, headers, and body

**Key Functions**:
- `method_to_string` (line 25): Convert Method variant to HTTP method string
- `status_code`, `status_ok`, `status_created`, etc. (lines 42-55): Status helpers
- `is_success`, `is_redirect`, `is_client_error`, `is_server_error` (lines 57-80): HTTP status classification
- `parse_url` (line 217): Parse HTTP/HTTPS URLs into Request values
- `get_header`, `get_request_header` (lines 189-213): Case-insensitive header lookup
- `set_method`, `set_scheme`, `set_host`, `set_body`, `set_header` (lines 118-159): Request modification helpers

### Layer 2: HttpTransport Module (`stdlib/http_transport.march`)

Low-level TCP and HTTP/1.1 request-response handling. Does **not** close connections; caller manages fd lifetime.

**Key Types** (lines 14-20):
- `TransportError`: ConnectionRefused | ConnTimeout | SendError | RecvError | ConnParseError | Closed

**Key Functions**:
- `connect(req)` (line 26): Open TCP connection to request host:port, returns Ok(fd) or Err
- `request_on(fd, req)` (line 43): Send request on existing fd, receive response (for keep-alive)
- `stream_request_on(fd, req, on_chunk)` (line 74): Stream response body with callback
- `request(req)` (line 129): One-shot: connect, send, receive, close automatically
- `simple_get(url)` (line 170): Convenience wrapper for GET requests

**Connection Lifecycle**:
- Single connection: `request()` opens, sends, receives, closes
- Keep-alive: Caller opens with `connect()`, reuses fd with `request_on()`, closes manually with `tcp_close()`
- Streaming: Use `stream_request_on()` to process body chunks without buffering

### Layer 3: HttpClient Module (`stdlib/http_client.march`)

High-level composable client with Req-style pipeline (request steps → transport → response steps).

**Key Types** (lines 15-34):
- `Client`: Holds request steps, response steps, error steps, redirect/retry config
- `HttpError`: Wraps transport errors, step errors, redirect limits

**Step Pipeline**:
- **Request steps** (lines 136-145): Transform request before sending (auth headers, base URL, etc.)
- **Response steps** (lines 147-156): Transform response after receiving
- **Error steps** (lines 158-167): Recovery strategies for errors
- Executed left-to-right; first error stops pipeline

**Key Functions**:
- `new_client()` (line 43): Create bare client with no steps
- `add_request_step`, `add_response_step`, `add_error_step` (lines 58-77): Register steps
- `with_redirects(client, max)` (line 83): Enable redirect following
- `with_retry(client, max_attempts, backoff_ms)` (line 90): Enable retry with backoff
- `run(client, req)` (line 253): Execute full pipeline (request steps → transport → redirects → response steps)
- `with_connection(client, url, callback)` (line 288): Keep-alive connection reuse
- `stream_get(client, url, on_chunk)` (line 318): Stream body with callback

**Built-in Steps**:
- `step_default_headers` (line 380): Add User-Agent and Accept headers
- `step_bearer_auth(token)` (line 387): Add Bearer token authorization
- `step_basic_auth(user, pass)` (line 395): Add Basic auth header
- `step_base_url(base)` (line 403): Prepend base URL
- `step_content_type(ct)` (line 424): Set Content-Type header
- `step_raise_on_error` (line 432): Reject 4xx/5xx responses

### HTTP Server: HttpServer Module (`stdlib/http_server.march`)

Request-response handler with Plug-style middleware pipeline.

**Key Types** (lines 14-35):
- `Upgrade`: NoUpgrade | WebSocketUpgrade(WsSocket -> Unit)
- `Conn` (lines 21-35): 13-field request-response struct
  - Fields 0-6: Request metadata (fd, method, path, path_info, query_string, headers, body)
  - Fields 7-9: Response (status, headers, body)
  - Fields 10-12: Halted flag, assigns, upgrade

**Conn Accessors** (lines 39-89):
- `method`, `path`, `path_info`, `query_string`: Request metadata
- `req_headers`, `req_body`: Raw request
- `status`, `resp_headers`, `resp_body`: Response components
- `halted`, `assigns`, `conn_upgrade`: Control flags
- `fd`: Socket file descriptor

**Conn Transforms** (lines 120-175):
- `put_resp_header(conn, name, value)` (line 120): Add response header
- `assign(conn, key, value)` (line 127): Store user data in assigns
- `send_resp(conn, status, body)` (line 136): Set response + mark halted
- `halt(conn)` (line 144): Mark as halted (stops pipeline)
- `text`, `json`, `html`, `redirect` (lines 153-175): Convenience response helpers

**Pipeline and Server** (lines 179-231):
- `run_pipeline(conn, plugs)` (line 179): Execute list of plugs in order, stops when halted
- `new(port)` (line 196): Create server config
- `plug(server, p)` (line 200): Add middleware plug
- `max_connections(server, n)`, `idle_timeout(server, secs)` (lines 207-217): Configure
- `listen(server)` (line 221): Start blocking server (calls `http_server_listen` builtin)

### WebSocket Module (`stdlib/websocket.march`)

WebSocket frame handling and multiplexed I/O.

**Key Types** (lines 9-13):
- `WsFrame`: TextFrame(String) | BinaryFrame(String) | Ping | Pong | Close(Int, String)
- `WsSocket`: WsSocket(Int) — wraps socket fd
- `SelectResult`: WsData(WsFrame) | ActorMsg | Timeout

**Key Functions** (lines 17-50):
- `upgrade(conn, handler)` (line 17): Mark conn for WebSocket upgrade with handler closure
- `recv(socket)` (line 26): Receive next frame (blocks)
- `send_frame(socket, frame)` (line 33): Send frame
- `close(socket, code, reason)` (line 40): Send close frame
- `select(socket, timeout_ms)` (line 46): Wait on socket OR actor messages OR timeout

## C Runtime Implementation

All heavy lifting is in C for performance. March code calls these builtins which are compiled to LLVM extern declarations.

### TCP Layer (`runtime/march_http.c`)

**Socket Management** (lines 110-255):
- `march_tcp_listen(port)` (line 110): Create listening socket, set SO_REUSEADDR, listen backlog 128. Returns fd or -1.
- `march_tcp_accept(listen_fd)` (line 129): Accept one connection, returns client fd or -1.
- `march_tcp_close(fd)` (line 253): Close socket.

**HTTP Request Reception** (`march_tcp_recv_http`, lines 140-230):
- Reads byte-by-byte until `\r\n\r\n` (header terminator)
- Parses Content-Length from headers
- Reads body bytes if Content-Length specified
- Returns march_string with headers + body, or NULL on error
- Max 1MB receive (enforced by caller)
- Handles partial reads and allocates growable buffers

**Send All** (`march_tcp_send_all`, lines 234-251):
- Loops on short writes using `send()`
- Returns Ok(Unit) or Err(String) with error message

### HTTP Parsing and Serialization

**Request Parsing** (`march_http_parse_request`, lines 265-351):
- Input: Raw HTTP request string
- Finds `\r\n\r\n` to separate headers and body
- Parses request line: "METHOD PATH HTTP/1.x"
- Extracts method, path (with optional query), headers
- Returns Ok(tuple(method_str, path_str, headers_list, body_str)) or Err(reason)
- Headers returned as linked list of Header(name, value) pairs

**Response Serialization** (`march_http_serialize_response`, lines 358-438):
- Input: status code, headers list, body string
- Outputs full HTTP/1.1 response with:
  - Status line: "HTTP/1.1 200 OK\r\n"
  - Headers from list (custom + auto Content-Length)
  - Blank line
  - Body bytes
- Uses growable buffer; returns march_string

**Status Code → Reason Mapping** (lines 360-376):
- 200 "OK", 201 "Created", 204 "No Content", 301 "Moved Permanently", 302 "Found", 304 "Not Modified"
- 400 "Bad Request", 401 "Unauthorized", 403 "Forbidden", 404 "Not Found", 405 "Method Not Allowed"
- 500 "Internal Server Error", 101 "Switching Protocols"

### HTTP Server Accept Loop (`march_http_server_listen`, lines 747-798)

**Architecture**:
- Thread-per-connection model using POSIX threads
- Main thread runs `select()` with 1-second timeout on listening socket
- Worker thread spawned for each accepted connection

**Connection Handler** (`connection_thread`, lines 584-745):
1. Read raw HTTP request via `march_tcp_recv_http`
2. Parse request: `march_http_parse_request`
3. Convert method string → Method ADT variant (tags 0-8 for standard methods, tag 9 for Other(String))
4. Split path on "/" into path_info list (filter empty segments)
5. Build Conn heap object (13 fields, 120 bytes total)
6. Call pipeline closure: `Conn -> Conn` using reference-counted borrowing
7. Check upgrade field for WebSocket (tag 1)
8. If WebSocket: perform handshake, call handler, close
9. If HTTP: extract status/headers/body from Conn, serialize response, send, close

**Key Details**:
- Reference counting for closures (pipeline is shared across threads)
- Closures passed as function pointers to `connection_thread`
- Perceus RC protocol: inc_rc before each call to keep borrowed closure alive
- Default response status: 200 if not set by pipeline
- Parse errors return 400, execution errors return 500

### WebSocket Implementation

**Handshake** (`march_ws_handshake`, lines 802-827):
- Combines Sec-WebSocket-Key header with magic string: `258EAFA5-E914-47DA-95CA-C5AB0DC85B11`
- SHA-1 hash the concatenation (160-bit output)
- Base64 encode the 20 bytes
- Send HTTP 101 response with Sec-WebSocket-Accept header

**Frame Reception** (`march_ws_recv`, lines 848-965):
- Reads 2-byte header: FIN (1 bit) | RSV (3) | opcode (4)
- Payload length: 7-bit value, or 126 (read 2-byte ext), or 127 (read 8-byte ext)
- If masked: read 4-byte mask key and unmask payload
- Opcode dispatch:
  - 0x1: Text → TextFrame(String) tag 0
  - 0x2: Binary → BinaryFrame(String) tag 1
  - 0x8: Close → Close(code, reason) tag 4
  - 0x9: Ping → Ping tag 2
  - 0xA: Pong → Pong tag 3
- Error or closed connection returns Close(1001, "going away")
- Max payload 16MB

**Frame Sending** (`march_ws_send`, lines 968-1046):
- Builds frame header: FIN=1 | opcode
- Payload length encoding: <126 (1 byte), 126-65535 (3 bytes), >65535 (10 bytes)
- No masking for server→client frames
- Sends header then payload

**Select** (`march_ws_select`, lines 1054-1130):
- Wait on WebSocket OR actor notification pipe OR timeout
- Prioritizes actor messages if both ready
- Returns WsData(WsFrame) tag 0, ActorMsg tag 1, or Timeout tag 2
- Uses POSIX `select()` with fd_set

### Cryptography Support

**SHA-1** (`runtime/sha1.c`, lines 12-72):
- RFC 3174 implementation
- 160-bit hash for WebSocket handshake
- Message padding, 512-bit block processing, 80-round compression
- No external dependencies

**Base64** (`runtime/base64.c`, lines 13-50):
- Encode only (no decode)
- Groups bytes into 4 base64 chars
- Handles partial groups with padding
- Used for Sec-WebSocket-Accept header

## Heap Object Layout

March uses uniform heap layout for all objects:
```
offset  0: int64_t  rc         // reference count (atomic)
offset  8: int32_t  tag        // variant tag
offset 12: int32_t  pad        // alignment padding
offset 16+: fields (8 bytes each)
```

**march_string** (special):
```
offset  0: int64_t  rc
offset  8: int64_t  len        // byte length
offset 16: char     data[len+1] // null-terminated
```

**Conn** (120 bytes):
- Field 0 (offset 16): int64_t fd
- Field 1-9 (offsets 24-88): pointers to Method/String/List/Int objects
- Field 10-12 (offsets 96-112): pointers to Bool/List/Upgrade objects

**List** (linked list):
- Nil: tag=0, no fields
- Cons: tag=1, field0=head (pointer), field1=tail (pointer)

**Result**:
- Err: tag=0, field0=error (pointer)
- Ok: tag=1, field0=value (pointer)

## LLVM Compilation

HTTP/WebSocket builtins are declared as external functions in generated LLVM IR.

**Function Mapping** (`lib/tir/llvm_emit.ml`, lines 268-279, 1432-1443):

| March Function | C Runtime | LLVM Type Signature |
|---|---|---|
| `tcp_listen` | `march_tcp_listen` | `i64 (i64)` |
| `tcp_accept` | `march_tcp_accept` | `i64 (i64)` |
| `tcp_recv_http` | `march_tcp_recv_http` | `ptr (i64, i64)` |
| `tcp_send_all` | `march_tcp_send_all` | `void (i64, ptr)` |
| `tcp_close` | `march_tcp_close` | `void (i64)` |
| `http_parse_request` | `march_http_parse_request` | `ptr (ptr)` |
| `http_serialize_response` | `march_http_serialize_response` | `ptr (i64, ptr, ptr)` |
| `http_server_listen` | `march_http_server_listen` | `void (i64, i64, i64, ptr)` |
| `ws_handshake` | `march_ws_handshake` | `void (i64, ptr)` |
| `ws_recv` | `march_ws_recv` | `ptr (i64)` |
| `ws_send` | `march_ws_send` | `void (i64, ptr)` |
| `ws_select` | `march_ws_select` | `ptr (i64, ptr, i64)` |

## Interpreter Support (`lib/eval/eval.ml`)

The interpreter provides pure OCaml implementations for development/testing:

**TCP Functions** (lines 1868-1932):
- `tcp_connect`: Uses OCaml Unix module with getaddrinfo
- `tcp_send_all`: Loop over Unix.send
- `tcp_recv_all`: Receive into buffer up to timeout
- `tcp_close`: Close file descriptor

**HTTP Functions** (lines 1933-2247):
- `tcp_recv_http`: Full HTTP request reception (headers + body)
- `tcp_recv_http_headers`: Headers only with Content-Length and Transfer-Encoding detection
- `tcp_recv_chunk`: Fixed-size receive
- `tcp_recv_chunked_frame`: Chunked transfer encoding frame parser
- `http_serialize_request`: Build raw HTTP request string
- `http_parse_response`: Parse status + headers + body from response string

## Test Coverage

### Unit Tests

**HTTP Native Tests** (`test/test_http_native.sh`):
- Compiles `examples/http_hello.march` to native executable
- Tests:
  - GET / → "Hello from compiled March!" (200)
  - GET /nonexistent → 404 status

### Benchmarks

Performance benchmarks under `bench/`:
- `http_get.march`: Fetch single URL
- `http_get_close.march`: Repeated single-request pattern (new connection per request)
- `http_get_keepalive.march`: Keep-alive connection reuse

### Examples

**http_hello.march**: Simple "Hello World" HTTP server
- Single route: GET / → 200 OK with text
- Catch-all: everything else → 404

**http_requests.march**: Demonstration of all three layers
- Layer 2: Direct `HttpTransport.simple_get()`
- Layer 3: `HttpClient` with request steps
- Shows GET and POST via public APIs

**http_streaming.march**: Streaming patterns
- Print chunks as received
- Count bytes without buffering
- Chunked transfer encoding handling

**counter_server.march**: Actor + HTTP server integration
- Spawned actor manages counter state
- GET /count, POST /increment, POST /decrement
- Shows conn → actor communication pattern

## Connection Handling

### Keep-Alive vs. Close

**One-Shot Requests** (Layer 2: `HttpTransport.request`):
- Adds `Connection: close` header
- Opens connection → sends request → receives response → closes
- Each request is independent

**Keep-Alive Requests** (Layer 2: `HttpTransport.request_on`, Layer 3: `HttpClient.with_connection`):
- Caller manages fd lifecycle
- Multiple requests on same connection
- Caller responsible for closing with `tcp_close(fd)`

### Server Connection Management

**Per-Connection Thread**:
- Listen thread accepts connections
- Worker thread created for each connection
- Worker reads 1 request, runs pipeline, sends response, closes
- Detached thread (not joined by main thread)

**Pipeline Halting**:
- Pipeline stops at first plug that halts the connection
- `send_resp()` automatically halts
- Allows early exit without processing remaining plugs

## Known Limitations

1. **HTTP/1.0 Only**: No HTTP/1.1 Expect/Continue, no persistent connection support in some layers
2. **No HTTPS/TLS**: Only HTTP/plain WebSocket (no wss://)
3. **Single-Request Per Connection (Server)**: HTTP server only handles one request per connection thread, then closes
4. **No HTTP/2**: No multiplexing
5. **WebSocket Frame Size**: Limited to 16MB per frame
6. **No Trailers**: HTTP/1.1 trailers not supported
7. **No 100-Continue**: Expect header not handled
8. **No Proxy Support**: No CONNECT method or proxy-related handling

## Future Enhancements

- HTTP/1.1 persistent connections in server
- HTTPS/TLS support
- HTTP/2 multiplexing
- HTTP compression (gzip, brotli)
- WebSocket compression
- Request timeouts
- Request body streaming in server

## Source File Reference

| File | Purpose | Lines |
|------|---------|-------|
| `stdlib/http.march` | Layer 1: Types and URL parsing | 1-339 |
| `stdlib/http_transport.march` | Layer 2: TCP and HTTP exchange | 1-181 |
| `stdlib/http_client.march` | Layer 3: Composable client pipeline | 1-441 |
| `stdlib/http_server.march` | Server with Plug middleware | 1-234 |
| `stdlib/websocket.march` | WebSocket frame types and API | 1-53 |
| `runtime/march_http.c` | C builtins for HTTP/WebSocket | 1-1131 |
| `runtime/march_http.h` | C API declarations | 1-101 |
| `runtime/sha1.c` | SHA-1 for WebSocket handshake | 1-72 |
| `runtime/base64.c` | Base64 for WebSocket | 1-50 |
| `lib/tir/llvm_emit.ml` | LLVM code generation | 268-279, 1432-1443 |
| `lib/eval/eval.ml` | Interpreter HTTP builtins | 1868-2247 |
| `test/test_http_native.sh` | E2E HTTP server test | 1-45 |
| `examples/http_hello.march` | Simple server example | 1-18 |
| `examples/http_requests.march` | Client usage example | 1-86 |
| `examples/http_streaming.march` | Streaming patterns | 1-68 |
| `examples/counter_server.march` | Actor + HTTP integration | 1-84 |
| `bench/http_get.march` | HTTP performance benchmark | - |
| `bench/http_get_close.march` | Single-request pattern bench | - |
| `bench/http_get_keepalive.march` | Keep-alive bench | - |

## Data Flow Diagrams

### Client Request (Layer 3)

```
HttpClient.run()
  ├─ run_request_steps()      [transform request]
  ├─ HttpTransport.request()
  │  ├─ tcp_connect()          [march_tcp_connect via C]
  │  ├─ http_serialize_request()
  │  ├─ tcp_send_all()         [march_tcp_send_all via C]
  │  ├─ tcp_recv_all()         [march_tcp_recv_all via C]
  │  ├─ http_parse_response()
  │  └─ tcp_close()
  ├─ handle_redirects()        [follow Location headers]
  ├─ run_response_steps()      [transform response]
  └─ run_error_steps()         [recovery]
```

### Server Request (HTTP)

```
march_http_server_listen()
  └─ [select loop]
     └─ march_tcp_accept()
        └─ [spawn worker thread]
           ├─ march_tcp_recv_http()
           ├─ march_http_parse_request()
           ├─ [build Conn]
           ├─ [call pipeline closure]
           ├─ [extract Conn fields]
           ├─ march_http_serialize_response()
           ├─ march_tcp_send_all()
           └─ close(fd)
```

### WebSocket Upgrade

```
HTTP server connection_thread()
  ├─ [receive HTTP request]
  ├─ [check upgrade field: tag=1]
  ├─ march_ws_handshake()
  │  ├─ sha1() [key + magic]
  │  ├─ base64_encode()
  │  └─ send() [HTTP 101]
  ├─ [call WsSocket handler]
  │  ├─ march_ws_recv()     [read frames]
  │  ├─ march_ws_send()     [write frames]
  │  └─ march_ws_select()   [multiplex fd + actor pipe]
  └─ close(fd)
```

## Integration Points

### With Perceus Reference Counting

Pipeline closures in HTTP server use Perceus protocol:
- `march_incrc()` increments RC before each call
- Closures captured variables are incrc'd too
- Decrement happens on return from closure
- Critical for sharing pipeline across threads

### With Actor System

WebSocket can multiplex on actor notification pipes:
- `ws_select()` accepts optional pipe fd
- Unblocks on either WebSocket data or pipe notification
- Allows WebSocket handler to interact with spawned actors

### With Threads

HTTP server spawns detached threads per connection:
- No thread pooling (unbounded connections)
- Each thread independent (no shared state except pipeline closure)
- Potential for resource exhaustion (TODO: max_conns enforcement)
