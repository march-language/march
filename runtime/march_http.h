/* runtime/march_http.h — HTTP and WebSocket C runtime builtins for March.
 *
 * These functions are called from compiled March code.  All March values are
 * passed as `void *` pointers to heap objects with the march_hdr layout
 * (16-byte header, fields at offset 16+).  Strings use march_string layout.
 *
 * NOTE: Do NOT include this header from march_runtime.h — march_http.h already
 * includes march_runtime.h, and a circular include would cause compile errors.
 * Translation units that need HTTP builtins should include march_http.h directly.
 */
#pragma once
#include "march_runtime.h"
#include <stdint.h>

/* ── TCP builtins ──────────────────────────────────────────────────── */

/* Create a listening TCP socket on the given port.
 * Returns the file descriptor (>= 0) on success, or -1 on error. */
int64_t march_tcp_listen(int64_t port);

/* Accept one incoming connection from a listening fd.
 * Blocks until a client connects.  Returns the client fd, or -1 on error. */
int64_t march_tcp_accept(int64_t listen_fd);

/* Read an HTTP request from fd: headers until \r\n\r\n, then Content-Length
 * body bytes (or until close if no Content-Length).  max_bytes caps total.
 * Returns a march_string* with the raw request, or NULL on error. */
void *march_tcp_recv_http(int64_t fd, int64_t max_bytes);

/* Write all bytes of the march_string `data` to fd.  Loops on short writes.
 * Returns Ok(Unit) as a March heap value on success, Err(String) on failure. */
void *march_tcp_send_all(int64_t fd, void *data);

/* Close a file descriptor. */
void march_tcp_close(int64_t fd);

/* Connect to host:port as a TCP client.
 * Returns Ok(fd:i64) or Err(reason:String). Ok=tag0, Err=tag1. */
void *march_tcp_connect(void *host, int64_t port);

/* ── HTTP client builtins ──────────────────────────────────────────── */

/* Serialize an HTTP/1.1 request from its components.
 * Returns a march_string* with the raw request. */
void *march_http_serialize_request(void *method, void *host, void *path,
                                    void *query, void *headers, void *body);

/* Parse a raw HTTP response string.
 * Returns Ok(tuple(status_code:i64, headers:List, body:String)) or Err(String).
 * Ok=tag0, Err=tag1. */
void *march_http_parse_response(void *raw);

/* ── HTTP server builtins ──────────────────────────────────────────── */

/* Parse a raw HTTP request string.
 * Returns: Ok(tuple(method_str, path_str, headers_list, body_str))
 *          Err(reason_str)
 *
 * headers_list is a March List(Header) where Header = Header(String, String).
 * Header tag layout: tag=0 → Nil, tag=1 → Cons(head, tail)
 * Header pair: [rc][tag=0][pad][name_ptr][value_ptr]  (tag=0 since only one ctor)
 */
void *march_http_parse_request(void *raw_string);

/* Serialize an HTTP/1.1 response into a single heap buffer.
 * status:  integer status code (200, 404, etc.)
 * headers: March List(Header) — linked list of Header(String, String) pairs
 * body:    march_string*
 * Returns a march_string* containing the full HTTP response.
 *
 * Prefer march_http_send_response() for the server path — it uses writev()
 * to avoid the intermediate copy. */
void *march_http_serialize_response(int64_t status, void *headers, void *body);

/* Send an HTTP/1.1 response directly to client_fd using scatter-gather I/O.
 *
 * Builds an iovec array that points directly at the march_string name/value
 * data and the body — no coalescing copy.  A single writev() syscall sends
 * the status line, all headers, and the body.
 *
 * status:  HTTP status code (200, 404, etc.)
 * headers: March List(Header) — same layout as march_http_serialize_response
 * body:    march_string* (may be NULL / empty)
 *
 * Returns 0 on success, -1 on error. */
int march_http_send_response(int fd, int64_t status, void *headers, void *body);

/* Send a static file to client_fd with zero-copy kernel I/O.
 *
 * 1. Opens path and fstat()s it for size.
 * 2. Sends HTTP/1.1 200 response headers (Content-Type inferred from
 *    file extension, Content-Length from fstat) via writev().
 * 3. Sends the file body using sendfile() on Linux and macOS; falls back
 *    to a read/write loop on other platforms.
 *
 * Returns 0 on success, -1 on error (errno set, no response sent on open/
 * fstat failure — caller should send a 404 or 500 instead). */
int march_http_send_file(int client_fd, const char *path);

/* ── HTTP server ───────────────────────────────────────────────────── */

/* Default number of worker threads in the connection thread pool.
 * Used as a fallback when sysconf(_SC_NPROCESSORS_ONLN) is unavailable. */
#define MARCH_HTTP_POOL_DEFAULT_SIZE 16

/* Start the HTTP connection thread pool.
 * pool_size: number of worker threads (0 → MARCH_HTTP_POOL_DEFAULT_SIZE).
 * pipeline:  compiled March function pointer (Conn -> Conn), shared by all workers.
 * Must be called before the accept loop starts enqueuing connections.
 * Safe to call once per process lifetime. */
void march_http_pool_start(int64_t pool_size, void *pipeline);

/* Signal all worker threads to drain remaining work and exit, then join them.
 * Blocks until every worker has returned.  Destroys pool synchronisation
 * primitives — do not call march_http_pool_start again after this. */
void march_http_pool_stop(void);

/* Start a blocking HTTP server accept loop backed by a fixed thread pool.
 * port:         TCP port to listen on
 * max_conns:    maximum concurrent connections (unused — pool_size caps this)
 * idle_timeout: idle timeout in seconds (unused — set SO_RCVTIMEO if needed)
 * pipeline:     a compiled March function pointer (Conn -> Conn)
 * Starts a MARCH_HTTP_POOL_DEFAULT_SIZE-worker pool internally and runs the
 * accept loop until SIGTERM/SIGINT.  Calls march_http_pool_stop before returning. */
void march_http_server_listen(int64_t port, int64_t max_conns,
                               int64_t idle_timeout, void *pipeline);

/* ── WebSocket builtins ────────────────────────────────────────────── */

/* Perform the WebSocket handshake upgrade on an already-accepted fd.
 * key_string: the value of the Sec-WebSocket-Key header (march_string*).
 * Writes the HTTP 101 upgrade response to fd. */
void march_ws_handshake(int64_t fd, void *key_string);

/* Read one WebSocket frame from fd.
 * Returns a March WsFrame value:
 *   type WsFrame = TextFrame(String)    -- tag 0, field 0 = String ptr
 *                | BinaryFrame(String)  -- tag 1, field 0 = String ptr
 *                | Ping                 -- tag 2, no fields
 *                | Pong                 -- tag 3, no fields
 *                | Close(Int, String)   -- tag 4, field 0 = Int, field 1 = String ptr
 * On error (connection closed) returns a Close(1001, "") frame. */
void *march_ws_recv(int64_t fd);

/* Send a WebSocket frame to fd.
 * frame: a March WsFrame value (same tag layout as march_ws_recv). */
void march_ws_send(int64_t fd, void *frame);

/* Wait for either a WebSocket frame or a message on an actor pipe.
 * fd:        WebSocket socket file descriptor
 * pipe_rd:   read end of a notification pipe (march_string* wrapping an Int fd),
 *            or NULL to skip actor-message waiting
 * timeout_ms: milliseconds to wait; 0 = no timeout
 *
 * Returns a March SelectResult value:
 *   type SelectResult(a) = WsData(WsFrame) | ActorMsg(a) | Timeout
 *   tag 0 = WsData,  field 0 = WsFrame ptr
 *   tag 1 = ActorMsg, field 0 = message ptr (opaque)
 *   tag 2 = Timeout, no fields
 */
void *march_ws_select(int64_t socket_fd, void *pipe_rd, int64_t timeout_ms);
