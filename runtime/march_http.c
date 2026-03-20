/* runtime/march_http.c — HTTP and WebSocket C runtime builtins for March.
 *
 * Implements TCP listen/accept/recv/send/close, HTTP request parsing and
 * response serialization, a thread-per-connection HTTP server accept loop,
 * and WebSocket handshake, frame recv/send, and select.
 *
 * All March heap objects use the standard layout:
 *   offset  0: int64_t  rc   (reference count)
 *   offset  8: int32_t  tag
 *   offset 12: int32_t  pad
 *   offset 16+: fields (each 8 bytes, int64_t or pointer)
 *
 * march_string:
 *   offset  0: int64_t  rc
 *   offset  8: int64_t  len
 *   offset 16: char     data[]   (null-terminated)
 */
#include "march_http.h"

#include <sys/socket.h>
#include <sys/select.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <ctype.h>
#include <alloca.h>

/* Forward declarations for sha1 and base64 (defined in sha1.c / base64.c) */
void sha1(const uint8_t *msg, size_t len, uint8_t out[20]);
int  base64_encode(const uint8_t *in, size_t len, char *out, size_t out_sz);

/* ── Helpers ─────────────────────────────────────────────────────────── */

/* Build a Result(Ok) value: tag=1, one pointer field. */
static void *make_ok(void *value) {
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;          /* tag = 1 (Ok) */
    *(void **)((char *)r + 16) = value;
    return r;
}

/* Build a Result(Err) value: tag=0, one pointer field (string). */
static void *make_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    /* tag stays 0 = Err */
    *(void **)((char *)r + 16) = s;
    return r;
}

/* Build a March Unit value (just a header, tag=0, no fields). */
static void *make_unit(void) {
    return march_alloc(16);
}

/* Build a March List Nil node: tag=0, no fields. */
static void *make_nil(void) {
    return march_alloc(16);
}

/* Build a March List Cons node: tag=1, field0=head, field1=tail. */
static void *make_cons(void *head, void *tail) {
    void *c = march_alloc(16 + 16);
    *(int32_t *)((char *)c + 8) = 1;           /* tag = 1 (Cons) */
    *(void **)((char *)c + 16) = head;
    *(void **)((char *)c + 24) = tail;
    return c;
}

/* Build a Header(String, String) value: single constructor (tag=0),
 * two pointer fields (name, value). */
static void *make_header(void *name, void *value) {
    void *h = march_alloc(16 + 16);
    /* tag stays 0 — Header has only one constructor */
    *(void **)((char *)h + 16) = name;
    *(void **)((char *)h + 24) = value;
    return h;
}

/* Build a tuple of 4 pointers.  Tag=0 (tuple has no variants). */
static void *make_tuple4(void *a, void *b, void *c, void *d) {
    void *t = march_alloc(16 + 32);
    *(void **)((char *)t + 16) = a;
    *(void **)((char *)t + 24) = b;
    *(void **)((char *)t + 32) = c;
    *(void **)((char *)t + 40) = d;
    return t;
}

/* Case-insensitive strncmp. */
static int istrncmp(const char *a, const char *b, size_t n) {
    for (size_t i = 0; i < n; i++) {
        int ca = tolower((unsigned char)a[i]);
        int cb = tolower((unsigned char)b[i]);
        if (ca != cb) return ca - cb;
        if (ca == '\0') return 0;
    }
    return 0;
}

/* ── TCP builtins ─────────────────────────────────────────────────────── */

int64_t march_tcp_listen(int64_t port) {
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) return -1;
    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));
    struct sockaddr_in addr;
    memset(&addr, 0, sizeof(addr));
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons((uint16_t)port);
    if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) < 0) {
        close(fd); return -1;
    }
    if (listen(fd, 128) < 0) {
        close(fd); return -1;
    }
    return (int64_t)fd;
}

int64_t march_tcp_accept(int64_t listen_fd) {
    struct sockaddr_in client_addr;
    socklen_t len = sizeof(client_addr);
    int fd = accept((int)listen_fd,
                    (struct sockaddr *)&client_addr, &len);
    return (int64_t)fd;
}

/* Receive a complete HTTP request (headers + body) from fd.
 * Reads byte-by-byte until \r\n\r\n, then reads Content-Length body bytes.
 * Returns a march_string* on success, or NULL on error/close. */
void *march_tcp_recv_http(int64_t fd, int64_t max_bytes) {
    int sock = (int)fd;
    /* Phase 1: read headers until \r\n\r\n */
    char *hdr_buf = NULL;
    size_t hdr_cap = 0, hdr_len = 0;
    int found_end = 0;
    uint8_t byte;
    while (!found_end && (int64_t)hdr_len < max_bytes) {
        ssize_t n = recv(sock, &byte, 1, 0);
        if (n <= 0) goto cleanup_err;
        if (hdr_len >= hdr_cap) {
            hdr_cap = hdr_cap ? hdr_cap * 2 : 1024;
            char *nb = realloc(hdr_buf, hdr_cap);
            if (!nb) goto cleanup_err;
            hdr_buf = nb;
        }
        hdr_buf[hdr_len++] = (char)byte;
        if (hdr_len >= 4 &&
            hdr_buf[hdr_len-4] == '\r' && hdr_buf[hdr_len-3] == '\n' &&
            hdr_buf[hdr_len-2] == '\r' && hdr_buf[hdr_len-1] == '\n') {
            found_end = 1;
        }
    }
    if (!found_end) goto cleanup_err;

    /* Phase 2: find Content-Length in headers */
    int64_t content_length = -1;
    /* Null-terminate temporarily for searching */
    if (hdr_len >= hdr_cap) {
        char *nb = realloc(hdr_buf, hdr_cap + 1);
        if (!nb) goto cleanup_err;
        hdr_buf = nb;
    }
    hdr_buf[hdr_len] = '\0';
    {
        const char *p = hdr_buf;
        while (*p) {
            const char *eol = strstr(p, "\r\n");
            if (!eol) break;
            size_t line_len = (size_t)(eol - p);
            if (istrncmp(p, "content-length:", 15) == 0) {
                const char *val = p + 15;
                while (*val == ' ') val++;
                content_length = (int64_t)strtoll(val, NULL, 10);
                break;
            }
            p = eol + 2;
            if (line_len == 0) break; /* blank line = end of headers */
        }
    }

    /* Phase 3: read body */
    char *body_buf = NULL;
    size_t body_len = 0;
    if (content_length > 0) {
        int64_t to_read = content_length;
        if (hdr_len + to_read > max_bytes)
            to_read = max_bytes - (int64_t)hdr_len;
        if (to_read > 0) {
            body_buf = malloc((size_t)to_read);
            if (!body_buf) goto cleanup_err;
            size_t got = 0;
            while ((int64_t)got < to_read) {
                ssize_t n = recv(sock, body_buf + got,
                                 (size_t)(to_read - (int64_t)got), 0);
                if (n <= 0) break;
                got += (size_t)n;
            }
            body_len = got;
        }
    }

    /* Phase 4: concatenate headers + body into a march_string */
    size_t total = hdr_len + body_len;
    march_string *result = malloc(sizeof(march_string) + total + 1);
    if (!result) { free(body_buf); goto cleanup_err; }
    result->rc  = 1;
    result->len = (int64_t)total;
    memcpy(result->data, hdr_buf, hdr_len);
    if (body_buf) {
        memcpy(result->data + hdr_len, body_buf, body_len);
        free(body_buf);
    }
    result->data[total] = '\0';
    free(hdr_buf);
    return result;

cleanup_err:
    free(hdr_buf);
    return NULL;
}

/* Send all bytes of a march_string to fd.
 * Returns Ok(Unit) on success, Err(String) on failure. */
void *march_tcp_send_all(int64_t fd, void *data) {
    if (!data) return make_err("null data");
    march_string *s = (march_string *)data;
    const char *buf = s->data;
    int64_t remaining = s->len;
    while (remaining > 0) {
        ssize_t sent = send((int)fd, buf, (size_t)remaining, 0);
        if (sent < 0) {
            char errbuf[64];
            snprintf(errbuf, sizeof(errbuf), "send: %s", strerror(errno));
            return make_err(errbuf);
        }
        if (sent == 0) return make_err("send: connection closed");
        buf += sent;
        remaining -= sent;
    }
    return make_ok(make_unit());
}

void march_tcp_close(int64_t fd) {
    close((int)fd);
}

/* ── HTTP builtins ─────────────────────────────────────────────────────── */

/* Parse raw HTTP request string.
 * Returns: Ok(tuple(method_str, path_str, headers_list, body_str))
 *       or Err(reason_str)
 *
 * Result tag layout:  Err=0, Ok=1  (Result = Err | Ok in declaration order)
 */
void *march_http_parse_request(void *raw_string) {
    if (!raw_string) return make_err("null input");
    march_string *raw = (march_string *)raw_string;

    /* Find end of headers */
    const char *data = raw->data;
    size_t data_len = (size_t)raw->len;

    /* Find \r\n\r\n */
    size_t hdr_end = 0;
    int found = 0;
    for (size_t i = 0; i + 3 < data_len; i++) {
        if (data[i] == '\r' && data[i+1] == '\n' &&
            data[i+2] == '\r' && data[i+3] == '\n') {
            hdr_end = i;
            found = 1;
            break;
        }
    }
    if (!found) hdr_end = data_len;

    /* Parse request line: "METHOD PATH HTTP/1.x\r\n" */
    const char *p = data;
    const char *eol = NULL;
    /* Find first \r\n */
    for (size_t i = 0; i < hdr_end; i++) {
        if (data[i] == '\r' && data[i+1] == '\n') {
            eol = data + i;
            break;
        }
    }
    if (!eol) return make_err("malformed request line");

    /* Extract method */
    const char *sp1 = memchr(p, ' ', (size_t)(eol - p));
    if (!sp1) return make_err("missing method");
    void *method_str = march_string_lit(p, (int64_t)(sp1 - p));

    /* Extract path (may include query string) */
    const char *path_start = sp1 + 1;
    const char *sp2 = memchr(path_start, ' ', (size_t)(eol - path_start));
    if (!sp2) sp2 = eol;
    void *path_str = march_string_lit(path_start, (int64_t)(sp2 - path_start));

    /* Parse header lines */
    void *headers = make_nil();  /* start with Nil */
    /* We'll build the list in reverse order, then it doesn't matter for this use case */
    const char *line = eol + 2;  /* skip \r\n after request line */
    const char *headers_end = found ? (data + hdr_end) : (data + data_len);
    while (line < headers_end) {
        /* Find end of this header line */
        const char *line_end = line;
        while (line_end < headers_end - 1 &&
               !(line_end[0] == '\r' && line_end[1] == '\n'))
            line_end++;
        if (line_end == line) break;   /* blank line */

        /* Split at first ':' */
        const char *colon = memchr(line, ':', (size_t)(line_end - line));
        if (colon) {
            /* Name: trim whitespace */
            void *hname = march_string_lit(line, (int64_t)(colon - line));
            /* Value: skip ': ' */
            const char *val_start = colon + 1;
            while (val_start < line_end && *val_start == ' ') val_start++;
            /* Trim trailing whitespace from value */
            const char *val_end = line_end;
            while (val_end > val_start &&
                   (val_end[-1] == ' ' || val_end[-1] == '\r'))
                val_end--;
            void *hval = march_string_lit(val_start, (int64_t)(val_end - val_start));
            void *hdr  = make_header(hname, hval);
            headers = make_cons(hdr, headers);  /* prepend — reverse order */
        }
        line = line_end + 2;  /* skip \r\n */
    }

    /* Extract body */
    const char *body_start = found ? (data + hdr_end + 4) : (data + data_len);
    size_t body_len = (size_t)(data + data_len - body_start);
    if (body_start > data + data_len) body_len = 0;
    void *body_str = march_string_lit(body_start, (int64_t)body_len);

    /* Build Ok(tuple(method, path, headers, body)) */
    void *tup = make_tuple4(method_str, path_str, headers, body_str);
    return make_ok(tup);
}

/* Serialize an HTTP/1.1 response.
 * headers: March List(Header) — tag=0 Nil, tag=1 Cons(Header, rest)
 *   Header = Header(name_str, value_str), single constructor (tag=0),
 *            fields at offsets 16 (name) and 24 (value).
 */
void *march_http_serialize_response(int64_t status, void *headers, void *body) {
    /* Determine reason phrase */
    const char *reason;
    switch (status) {
        case 200: reason = "OK"; break;
        case 201: reason = "Created"; break;
        case 204: reason = "No Content"; break;
        case 301: reason = "Moved Permanently"; break;
        case 302: reason = "Found"; break;
        case 304: reason = "Not Modified"; break;
        case 400: reason = "Bad Request"; break;
        case 401: reason = "Unauthorized"; break;
        case 403: reason = "Forbidden"; break;
        case 404: reason = "Not Found"; break;
        case 405: reason = "Method Not Allowed"; break;
        case 500: reason = "Internal Server Error"; break;
        case 101: reason = "Switching Protocols"; break;
        default:  reason = ""; break;
    }

    march_string *body_s = (march_string *)body;
    int64_t body_len = body_s ? body_s->len : 0;

    /* Build response into a growable buffer */
    size_t cap = 4096;
    char *buf = malloc(cap);
    if (!buf) return march_string_lit("", 0);
    size_t len = 0;

#define APPEND_STR(s, n) do { \
    size_t _n = (n); \
    while (len + _n + 1 > cap) { cap *= 2; char *nb = realloc(buf, cap); if (!nb) { free(buf); return march_string_lit("", 0); } buf = nb; } \
    memcpy(buf + len, (s), _n); len += _n; \
} while (0)

#define APPEND_CSTR(s) APPEND_STR((s), strlen(s))

    /* Status line */
    char status_line[64];
    int sl_len = snprintf(status_line, sizeof(status_line),
                          "HTTP/1.1 %lld %s\r\n", (long long)status, reason);
    APPEND_STR(status_line, (size_t)sl_len);

    /* Headers from the March list */
    void *cur = headers;
    while (cur) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;  /* Nil */
        /* Cons: field0=head (Header), field1=tail */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        /* Header = Header(name, value), tag=0, fields at 16/24 */
        march_string *hname = *(march_string **)((char *)hdr + 16);
        march_string *hval  = *(march_string **)((char *)hdr + 24);
        APPEND_STR(hname->data, (size_t)hname->len);
        APPEND_CSTR(": ");
        APPEND_STR(hval->data, (size_t)hval->len);
        APPEND_CSTR("\r\n");
        cur = tail;
    }

    /* Content-Length */
    char cl_line[48];
    int cl_len = snprintf(cl_line, sizeof(cl_line),
                          "Content-Length: %lld\r\n", (long long)body_len);
    APPEND_STR(cl_line, (size_t)cl_len);

    /* Blank line */
    APPEND_CSTR("\r\n");

    /* Body */
    if (body_s && body_len > 0)
        APPEND_STR(body_s->data, (size_t)body_len);

#undef APPEND_STR
#undef APPEND_CSTR

    void *result = march_string_lit(buf, (int64_t)len);
    free(buf);
    return result;
}

/* ── HTTP server accept loop ──────────────────────────────────────────── */

/* Server config fields (heap object):
 *   field 0 (offset 16): port       int64_t
 *   field 1 (offset 24): max_conns  int64_t
 *   field 2 (offset 32): timeout_ms int64_t
 */
typedef struct {
    void *pipeline;       /* compiled March function: Conn -> Conn */
    int   client_fd;
} conn_thread_arg_t;

/* Each connection thread: parse request, run pipeline, send response, close. */
static void *connection_thread(void *arg) {
    conn_thread_arg_t *a = (conn_thread_arg_t *)arg;
    int fd = a->client_fd;
    void *pipeline = a->pipeline;
    free(a);

    /* Read raw HTTP request */
    void *raw = march_tcp_recv_http((int64_t)fd, 1024 * 1024 /* 1MB max */);
    if (!raw) {
        close(fd);
        return NULL;
    }

    /* Parse the request */
    void *parse_result = march_http_parse_request(raw);
    /* parse_result: Result — tag=0 Err, tag=1 Ok */
    int32_t parse_tag = *(int32_t *)((char *)parse_result + 8);
    if (parse_tag == 0) {
        /* Parse error — send 400 */
        void *resp = march_http_serialize_response(
            400, make_nil(),
            march_string_lit("Bad Request", 11));
        march_tcp_send_all((int64_t)fd, resp);
        close(fd);
        return NULL;
    }

    /* Ok(tuple(method, path, headers, body)) */
    void *tup = *(void **)((char *)parse_result + 16);

    /* Build a minimal Conn value and call the pipeline.
     *
     * TODO: Full Conn construction requires knowing the exact March Conn
     * type layout, which depends on how the codegen/compiler emits it.
     * For v1, we call the pipeline with the raw parse tuple; the pipeline
     * is expected to accept (method, path, headers, body) and return a
     * response string directly.  When the full Conn ADT is wired up in
     * the codegen, this should be updated to construct the Conn properly.
     */
    typedef void *(*pipeline_fn_t)(void *);
    pipeline_fn_t fn = (pipeline_fn_t)pipeline;
    void *response_str = fn(tup);

    if (response_str) {
        /* If the pipeline returned a march_string, send it directly. */
        int32_t resp_tag = *(int32_t *)((char *)response_str + 8);
        (void)resp_tag;
        march_tcp_send_all((int64_t)fd, response_str);
    }

    close(fd);
    return NULL;
}

void march_http_server_listen(void *server_config, void *pipeline) {
    if (!server_config || !pipeline) return;

    int64_t port      = *(int64_t *)((char *)server_config + 16);
    int64_t max_conns = *(int64_t *)((char *)server_config + 24);
    /* int64_t timeout_ms = *(int64_t *)((char *)server_config + 32); */
    (void)max_conns;  /* TODO: enforce max_conns with an atomic counter */

    /* Ignore broken-pipe signals — we handle send errors explicitly */
    signal(SIGPIPE, SIG_IGN);

    int64_t listen_fd = march_tcp_listen(port);
    if (listen_fd < 0) {
        fprintf(stderr, "march_http_server_listen: tcp_listen(%lld) failed: %s\n",
                (long long)port, strerror(errno));
        return;
    }

    fprintf(stderr, "march: HTTP server listening on port %lld\n", (long long)port);

    for (;;) {
        /* Use select with 1-second timeout to allow future shutdown signalling */
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET((int)listen_fd, &rfds);
        struct timeval tv = {.tv_sec = 1, .tv_usec = 0};
        int r = select((int)listen_fd + 1, &rfds, NULL, NULL, &tv);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (r == 0) continue;  /* timeout — loop back */

        int64_t client_fd = march_tcp_accept(listen_fd);
        if (client_fd < 0) continue;

        conn_thread_arg_t *arg = malloc(sizeof(conn_thread_arg_t));
        if (!arg) { close((int)client_fd); continue; }
        arg->client_fd = (int)client_fd;
        arg->pipeline  = pipeline;

        pthread_t tid;
        pthread_attr_t attr;
        pthread_attr_init(&attr);
        pthread_attr_setdetachstate(&attr, PTHREAD_CREATE_DETACHED);
        if (pthread_create(&tid, &attr, connection_thread, arg) != 0) {
            free(arg);
            close((int)client_fd);
        }
        pthread_attr_destroy(&attr);
    }

    close((int)listen_fd);
}

/* ── WebSocket builtins ───────────────────────────────────────────────── */

void march_ws_handshake(int64_t fd, void *key_string) {
    if (!key_string) return;
    march_string *key = (march_string *)key_string;
    const char *magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    size_t magic_len = 36;
    size_t total = (size_t)key->len + magic_len;
    char *concat = (char *)alloca(total);
    memcpy(concat, key->data, (size_t)key->len);
    memcpy(concat + key->len, magic, magic_len);

    uint8_t hash[20];
    sha1((const uint8_t *)concat, total, hash);

    char b64[32];
    base64_encode(hash, 20, b64, sizeof(b64));

    char resp[256];
    int n = snprintf(resp, sizeof(resp),
        "HTTP/1.1 101 Switching Protocols\r\n"
        "Upgrade: websocket\r\n"
        "Connection: Upgrade\r\n"
        "Sec-WebSocket-Accept: %s\r\n\r\n",
        b64);
    if (n > 0)
        send((int)fd, resp, (size_t)n, 0);
}

/* recv_all_bytes: read exactly `n` bytes from fd into buf. Returns 0 on success, -1 on error. */
static int recv_exact(int fd, uint8_t *buf, size_t n) {
    size_t got = 0;
    while (got < n) {
        ssize_t r = recv(fd, buf + got, n - got, 0);
        if (r <= 0) return -1;
        got += (size_t)r;
    }
    return 0;
}

/* WsFrame tag layout (matches March declaration order):
 *   TextFrame(String)   → tag 0, field[0] = String ptr
 *   BinaryFrame(String) → tag 1, field[0] = String ptr
 *   Ping                → tag 2, no fields
 *   Pong                → tag 3, no fields
 *   Close(Int, String)  → tag 4, field[0] = Int, field[1] = String ptr
 */

void *march_ws_recv(int64_t fd) {
    int sock = (int)fd;
    uint8_t hdr2[2];

    /* Read 2-byte frame header */
    if (recv_exact(sock, hdr2, 2) < 0)
        goto closed;

    int fin    = (hdr2[0] >> 7) & 1;
    int opcode = hdr2[0] & 0x0F;
    int masked = (hdr2[1] >> 7) & 1;
    uint64_t payload_len = hdr2[1] & 0x7F;
    (void)fin;

    /* Extended payload length */
    if (payload_len == 126) {
        uint8_t ext[2];
        if (recv_exact(sock, ext, 2) < 0) goto closed;
        payload_len = ((uint64_t)ext[0] << 8) | ext[1];
    } else if (payload_len == 127) {
        uint8_t ext[8];
        if (recv_exact(sock, ext, 8) < 0) goto closed;
        payload_len = 0;
        for (int i = 0; i < 8; i++)
            payload_len = (payload_len << 8) | ext[i];
    }

    /* Masking key (clients always mask, servers never do) */
    uint8_t mask[4] = {0, 0, 0, 0};
    if (masked) {
        if (recv_exact(sock, mask, 4) < 0) goto closed;
    }

    /* Read payload */
    uint8_t *payload = NULL;
    if (payload_len > 0) {
        if (payload_len > 16 * 1024 * 1024) goto closed;  /* 16MB limit */
        payload = malloc(payload_len + 1);
        if (!payload) goto closed;
        if (recv_exact(sock, payload, payload_len) < 0) {
            free(payload); goto closed;
        }
        /* Unmask */
        if (masked) {
            for (uint64_t i = 0; i < payload_len; i++)
                payload[i] ^= mask[i % 4];
        }
        payload[payload_len] = '\0';
    }

    void *result = NULL;
    switch (opcode) {
        case 0x1: {  /* Text */
            void *s = march_string_lit(payload ? (char *)payload : "",
                                       (int64_t)payload_len);
            result = march_alloc(16 + 8);
            /* tag = 0 (TextFrame) */
            *(void **)((char *)result + 16) = s;
            break;
        }
        case 0x2: {  /* Binary */
            void *s = march_string_lit(payload ? (char *)payload : "",
                                       (int64_t)payload_len);
            result = march_alloc(16 + 8);
            *(int32_t *)((char *)result + 8) = 1;  /* tag = 1 (BinaryFrame) */
            *(void **)((char *)result + 16) = s;
            break;
        }
        case 0x8: {  /* Close */
            int64_t code = 1000;
            const char *reason_cstr = "";
            size_t reason_len = 0;
            if (payload_len >= 2) {
                code = ((int64_t)payload[0] << 8) | payload[1];
                reason_cstr = (payload_len > 2) ? (char *)payload + 2 : "";
                reason_len  = (payload_len > 2) ? payload_len - 2 : 0;
            }
            void *reason_str = march_string_lit(reason_cstr, (int64_t)reason_len);
            result = march_alloc(16 + 16);
            *(int32_t *)((char *)result + 8) = 4;  /* tag = 4 (Close) */
            *(int64_t *)((char *)result + 16) = code;
            *(void **)((char *)result + 24) = reason_str;
            break;
        }
        case 0x9: {  /* Ping */
            result = march_alloc(16);
            *(int32_t *)((char *)result + 8) = 2;  /* tag = 2 (Ping) */
            break;
        }
        case 0xA: {  /* Pong */
            result = march_alloc(16);
            *(int32_t *)((char *)result + 8) = 3;  /* tag = 3 (Pong) */
            break;
        }
        default: {
            /* Unknown opcode — treat as close */
            result = march_alloc(16 + 16);
            *(int32_t *)((char *)result + 8) = 4;
            *(int64_t *)((char *)result + 16) = 1002;  /* protocol error */
            *(void **)((char *)result + 24) = march_string_lit("unknown opcode", 14);
            break;
        }
    }

    free(payload);
    return result;

closed:
    free(payload);
    /* Return Close(1001, "gone away") */
    {
        void *r = march_alloc(16 + 16);
        *(int32_t *)((char *)r + 8) = 4;
        *(int64_t *)((char *)r + 16) = 1001;
        *(void **)((char *)r + 24) = march_string_lit("going away", 10);
        return r;
    }
}

/* Send a WebSocket frame to fd (server→client, unmasked). */
void march_ws_send(int64_t fd, void *frame) {
    if (!frame) return;
    int sock = (int)fd;

    int32_t tag = *(int32_t *)((char *)frame + 8);

    uint8_t opcode;
    const uint8_t *payload = NULL;
    size_t payload_len = 0;
    uint8_t close_hdr[2] = {0, 0};

    march_string *payload_str = NULL;

    switch (tag) {
        case 0:  /* TextFrame(String) */
            opcode = 0x01;
            payload_str = *(march_string **)((char *)frame + 16);
            break;
        case 1:  /* BinaryFrame(String) */
            opcode = 0x02;
            payload_str = *(march_string **)((char *)frame + 16);
            break;
        case 2:  /* Ping */
            opcode = 0x09;
            break;
        case 3:  /* Pong */
            opcode = 0x0A;
            break;
        case 4: {  /* Close(Int, String) */
            opcode = 0x08;
            int64_t code = *(int64_t *)((char *)frame + 16);
            payload_str   = *(march_string **)((char *)frame + 24);
            /* Build 2-byte close status + reason */
            size_t reason_len = payload_str ? (size_t)payload_str->len : 0;
            uint8_t *close_buf = alloca(2 + reason_len);
            close_buf[0] = (uint8_t)((code >> 8) & 0xFF);
            close_buf[1] = (uint8_t)(code & 0xFF);
            if (reason_len > 0 && payload_str)
                memcpy(close_buf + 2, payload_str->data, reason_len);
            payload     = close_buf;
            payload_len = 2 + reason_len;
            payload_str = NULL;  /* already set payload directly */
            break;
        }
        default:
            return;
    }

    if (payload_str) {
        payload     = (const uint8_t *)payload_str->data;
        payload_len = (size_t)payload_str->len;
    }

    /* Build frame header: FIN=1, RSV=0, opcode; MASK=0, payload_len */
    uint8_t frame_hdr[10];
    int hdr_len;
    frame_hdr[0] = 0x80 | opcode;  /* FIN=1 */

    if (payload_len < 126) {
        frame_hdr[1] = (uint8_t)payload_len;
        hdr_len = 2;
    } else if (payload_len < 65536) {
        frame_hdr[1] = 126;
        frame_hdr[2] = (uint8_t)(payload_len >> 8);
        frame_hdr[3] = (uint8_t)(payload_len & 0xFF);
        hdr_len = 4;
    } else {
        frame_hdr[1] = 127;
        for (int i = 0; i < 8; i++)
            frame_hdr[2 + i] = (uint8_t)((payload_len >> (56 - 8*i)) & 0xFF);
        hdr_len = 10;
    }

    send(sock, frame_hdr, (size_t)hdr_len, 0);
    if (payload_len > 0)
        send(sock, payload, payload_len, 0);

    (void)close_hdr;
}

/* Select on WebSocket fd and optional actor notification pipe.
 * SelectResult(a) tag layout:
 *   WsData(WsFrame)  → tag 0, field[0] = WsFrame ptr
 *   ActorMsg(a)      → tag 1, field[0] = message ptr
 *   Timeout          → tag 2, no fields
 */
void *march_ws_select(int64_t socket_fd, void *pipe_rd, int64_t timeout_ms) {
    int ws_fd = (int)socket_fd;

    /* pipe_rd is an int64 field inside a March heap object, or NULL */
    int pipe_fd = -1;
    if (pipe_rd) {
        /* pipe_rd is a march_string wrapping an Int, or directly an Int heap obj.
         * For now we treat it as a pointer to a heap object whose first int64 field
         * (at offset 16) holds the pipe file descriptor. */
        pipe_fd = (int)(*(int64_t *)((char *)pipe_rd + 16));
    }

    int max_fd = ws_fd;
    if (pipe_fd > max_fd) max_fd = pipe_fd;

    fd_set rfds;
    FD_ZERO(&rfds);
    FD_SET(ws_fd, &rfds);
    if (pipe_fd >= 0) FD_SET(pipe_fd, &rfds);

    struct timeval tv;
    struct timeval *tvp = NULL;
    if (timeout_ms > 0) {
        tv.tv_sec  = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        tvp = &tv;
    }

    int r = select(max_fd + 1, &rfds, NULL, NULL, tvp);
    if (r < 0) {
        if (errno == EINTR) {
            /* Return Timeout on signal */
            void *t = march_alloc(16);
            *(int32_t *)((char *)t + 8) = 2;
            return t;
        }
        /* Error → return Timeout */
        void *t = march_alloc(16);
        *(int32_t *)((char *)t + 8) = 2;
        return t;
    }

    if (r == 0) {
        /* Timeout */
        void *t = march_alloc(16);
        *(int32_t *)((char *)t + 8) = 2;
        return t;
    }

    /* Check actor pipe first (prioritise actor messages) */
    if (pipe_fd >= 0 && FD_ISSET(pipe_fd, &rfds)) {
        /* Drain one byte from the notification pipe */
        uint8_t dummy;
        recv(pipe_fd, &dummy, 1, 0);
        /* Return ActorMsg — the caller is responsible for reading the mailbox.
         * We return a placeholder Unit value as the message. */
        void *msg = march_alloc(16);  /* Unit */
        void *res = march_alloc(16 + 8);
        *(int32_t *)((char *)res + 8) = 1;  /* tag = 1 (ActorMsg) */
        *(void **)((char *)res + 16) = msg;
        return res;
    }

    /* WebSocket data available */
    if (FD_ISSET(ws_fd, &rfds)) {
        void *ws_frame = march_ws_recv(socket_fd);
        void *res = march_alloc(16 + 8);
        /* tag = 0 (WsData) */
        *(void **)((char *)res + 16) = ws_frame;
        return res;
    }

    /* Shouldn't reach here, but return Timeout as a safe fallback */
    void *t = march_alloc(16);
    *(int32_t *)((char *)t + 8) = 2;
    return t;
}
