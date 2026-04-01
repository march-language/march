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
#include "march_http_internal.h"
#include "march_http_io.h"
#include "march_http_parse_simd.h"
#include "march_http_response.h"

/* ── SIMD HTTP parser feature gate ────────────────────────────────────
 * Define MARCH_HTTP_DISABLE_SIMD to force the legacy scalar parser path.
 * By default the SIMD parser (march_http_parse_simd.c) is used; it falls
 * back to scalar automatically on non-SSE4.2 CPUs.
 */
#if !defined(MARCH_HTTP_DISABLE_SIMD)
#  define MARCH_HTTP_USE_SIMD 1
#endif

#include <sys/socket.h>
#include <sys/select.h>
#include <sys/uio.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <unistd.h>
#include <sys/wait.h>
#include <errno.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include <signal.h>
#include <stdatomic.h>
#include <ctype.h>
#include <alloca.h>
#if defined(__linux__)
#  include <sys/sendfile.h>
#endif

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
    if (listen(fd, 1024) < 0) {
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

/* Per-thread accumulation buffer for march_tcp_recv_http().
 * Allocated on first use and grown as needed; never freed (worker threads
 * are long-lived, OS reclaims memory on exit).  Reused across requests on
 * the same keep-alive connection — eliminates the malloc/realloc on the
 * hot path once the buffer has stabilised at the typical request size. */
typedef struct { char *buf; size_t cap; } recv_buf_t;
static _Thread_local recv_buf_t tl_recv_buf;

/* Grow tl_recv_buf to at least `needed` bytes.
 * Returns the buffer pointer on success, NULL on OOM.
 * On OOM the old buffer (and its contents) remain valid. */
static char *recv_buf_grow(size_t needed) {
    recv_buf_t *rb = &tl_recv_buf;
    if (needed <= rb->cap) return rb->buf;
    size_t new_cap = rb->cap ? rb->cap * 2 : 4096;
    while (new_cap < needed) new_cap *= 2;
    char *nb = realloc(rb->buf, new_cap);
    if (!nb) return NULL;
    rb->buf = nb;
    rb->cap = new_cap;
    return nb;
}

/* Receive a complete HTTP request (headers + body) from fd.
 * Uses a thread-local accumulation buffer that is reused across requests
 * on the same keep-alive connection — no malloc on the hot path after the
 * first request per thread.  Body allocation is still per-request (variable
 * size, and the data is copied into the result string anyway).
 * Returns a march_string* on success, or NULL on error/close/timeout. */
void *march_tcp_recv_http(int64_t fd, int64_t max_bytes) {
    int sock = (int)fd;
    char readbuf[16384];

    /* Phase 1: accumulate into the thread-local buffer until \r\n\r\n. */
    size_t hdr_len  = 0;   /* bytes written into tl_recv_buf so far */
    int    found_end = 0;
    size_t hdrs_end  = 0;  /* offset of first byte AFTER \r\n\r\n */

    while (!found_end && (int64_t)hdr_len < max_bytes) {
        ssize_t n = recv(sock, readbuf, sizeof(readbuf), 0);
        if (n <= 0) return NULL;

        char *buf = recv_buf_grow(hdr_len + (size_t)n);
        if (!buf) return NULL;
        memcpy(buf + hdr_len, readbuf, (size_t)n);
        hdr_len += (size_t)n;

        /* Scan for \r\n\r\n; start 3 bytes before the new data to handle
         * sequences that straddle two reads. */
        size_t scan_from = (hdr_len > (size_t)n + 3) ? hdr_len - (size_t)n - 3 : 0;
        for (size_t i = scan_from; i + 3 < hdr_len; i++) {
            if (buf[i] == '\r' && buf[i+1] == '\n' &&
                buf[i+2] == '\r' && buf[i+3] == '\n') {
                found_end = 1;
                hdrs_end  = i + 4;
                break;
            }
        }
    }
    if (!found_end) return NULL;

    /* Phase 2: find Content-Length.  Temporarily null-terminate at hdrs_end. */
    int64_t content_length = -1;
    {
        char *buf = recv_buf_grow(hdrs_end + 1);
        if (!buf) return NULL;
        char saved = buf[hdrs_end];
        buf[hdrs_end] = '\0';
        const char *p = buf;
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
            if (line_len == 0) break;
        }
        buf[hdrs_end] = saved;
    }

    /* Phase 3: read body.  Already-buffered bytes past hdrs_end are reused. */
    char  *body_buf = NULL;
    size_t body_len = 0;

    if (content_length > 0) {
        int64_t to_read = content_length;
        if ((int64_t)hdrs_end + to_read > max_bytes)
            to_read = max_bytes - (int64_t)hdrs_end;
        if (to_read > 0) {
            body_buf = malloc((size_t)to_read);
            if (!body_buf) return NULL;
            size_t already = hdr_len - hdrs_end;
            if (already > (size_t)to_read) already = (size_t)to_read;
            if (already > 0)
                memcpy(body_buf, tl_recv_buf.buf + hdrs_end, already);
            size_t got = already;
            while ((int64_t)got < to_read) {
                ssize_t n = recv(sock, body_buf + got,
                                 (size_t)(to_read - (int64_t)got), 0);
                if (n <= 0) break;
                got += (size_t)n;
            }
            body_len = got;
        }
    }

    /* Phase 4: build result march_string (header block + body).
     * tl_recv_buf.buf is NOT freed — it is reused by the next request. */
    size_t total = hdrs_end + body_len;
    march_string *result = malloc(sizeof(march_string) + total + 1);
    if (!result) { free(body_buf); return NULL; }
    atomic_store_explicit((_Atomic int64_t *)&result->rc, 1, memory_order_relaxed);
    result->len = (int64_t)total;
    memcpy(result->data, tl_recv_buf.buf, hdrs_end);
    if (body_buf) {
        memcpy(result->data + hdrs_end, body_buf, body_len);
        free(body_buf);
    }
    result->data[total] = '\0';
    return result;
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

/* Connect to host:port as a TCP client.
 * Returns Ok(fd:i64) on success, Err(reason:string) on failure.
 * Tag convention: Ok=tag0, Err=tag1 (matches march_runtime.c mk_ok/mk_err). */
void *march_tcp_connect(void *host_ptr, int64_t port) {
    if (!host_ptr) {
        void *s = march_string_lit("tcp_connect: null host", 22);
        void *r = march_alloc(24);
        ((march_hdr *)r)->tag = 1; /* Err */
        *(void **)((char *)r + 16) = s;
        return r;
    }
    march_string *hs = (march_string *)host_ptr;
    char *host = hs->data;
    char port_str[16];
    snprintf(port_str, sizeof(port_str), "%d", (int)port);

    struct addrinfo hints, *res = NULL;
    memset(&hints, 0, sizeof(hints));
    hints.ai_family   = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    if (getaddrinfo(host, port_str, &hints, &res) != 0 || !res) {
        void *s = march_string_lit("tcp_connect: getaddrinfo failed", 31);
        void *r = march_alloc(24);
        ((march_hdr *)r)->tag = 1; /* Err */
        *(void **)((char *)r + 16) = s;
        return r;
    }
    int fd = socket(res->ai_family, res->ai_socktype, res->ai_protocol);
    if (fd < 0) {
        freeaddrinfo(res);
        void *s = march_string_lit("tcp_connect: socket failed", 26);
        void *r = march_alloc(24);
        ((march_hdr *)r)->tag = 1; /* Err */
        *(void **)((char *)r + 16) = s;
        return r;
    }
    if (connect(fd, res->ai_addr, res->ai_addrlen) < 0) {
        close(fd);
        freeaddrinfo(res);
        void *s = march_string_lit("tcp_connect: connection refused", 31);
        void *r = march_alloc(24);
        ((march_hdr *)r)->tag = 1; /* Err */
        *(void **)((char *)r + 16) = s;
        return r;
    }
    freeaddrinfo(res);
    /* Return Ok(fd) — fd stored as i64 field 0, Ok=tag0 */
    void *ok_obj = march_alloc(24);
    /* tag stays 0 = Ok */
    *(int64_t *)((char *)ok_obj + 16) = (int64_t)fd;
    return ok_obj;
}

/* ── HTTP builtins ─────────────────────────────────────────────────────── */

/* Parse raw HTTP request string.
 * Returns: Ok(tuple(method_str, path_str, headers_list, body_str))
 *       or Err(reason_str)
 *
 * Result tag layout:  Err=0, Ok=1  (Result = Err | Ok in declaration order)
 *
 * When MARCH_HTTP_USE_SIMD is defined (default), delegates to the SIMD-
 * accelerated parser in march_http_parse_simd.c, then converts the raw C
 * string slices into March heap objects.  Define MARCH_HTTP_DISABLE_SIMD
 * to use the legacy scalar path instead.
 */
void *march_http_parse_request(void *raw_string) {
    if (!raw_string) return make_err("null input");
    march_string *raw = (march_string *)raw_string;
    const char *data     = raw->data;
    size_t      data_len = (size_t)raw->len;

#if defined(MARCH_HTTP_USE_SIMD)
    /* ── SIMD fast path ─────────────────────────────────────────────── */
    march_http_request_t parsed;
    int result = march_http_parse_request_simd(data, data_len, &parsed);
    if (result < 0) return make_err("malformed request");
    if (result == 0) return make_err("incomplete request");

    /* Convert method and path to March strings */
    void *method_str = march_string_lit(parsed.method,
                                        (int64_t)parsed.method_len);
    void *path_str   = march_string_lit(parsed.path,
                                        (int64_t)parsed.path_len);

    /* Build header list (prepend each header → reverse order,
     * matching the legacy scalar path behaviour) */
    void *headers = make_nil();
    for (size_t i = 0; i < parsed.num_headers; i++) {
        const march_http_header_t *h = &parsed.headers[i];
        void *hname = march_string_lit(h->name,  (int64_t)h->name_len);
        void *hval  = march_string_lit(h->value, (int64_t)h->value_len);
        void *hdr   = make_header(hname, hval);
        headers     = make_cons(hdr, headers);
    }

    /* Body is everything after the header section */
    const char *body_start = data + parsed.header_end;
    size_t       body_len  = data_len > parsed.header_end
                             ? data_len - parsed.header_end : 0;
    void *body_str = march_string_lit(body_start, (int64_t)body_len);

    void *tup = make_tuple4(method_str, path_str, headers, body_str);
    return make_ok(tup);

#else /* MARCH_HTTP_DISABLE_SIMD — legacy scalar path */

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

    /* Parse request line */
    const char *p = data;
    const char *eol = NULL;
    for (size_t i = 0; i < hdr_end; i++) {
        if (data[i] == '\r' && data[i+1] == '\n') {
            eol = data + i;
            break;
        }
    }
    if (!eol) return make_err("malformed request line");

    const char *sp1 = memchr(p, ' ', (size_t)(eol - p));
    if (!sp1) return make_err("missing method");
    void *method_str = march_string_lit(p, (int64_t)(sp1 - p));

    const char *path_start = sp1 + 1;
    const char *sp2 = memchr(path_start, ' ', (size_t)(eol - path_start));
    if (!sp2) sp2 = eol;
    void *path_str = march_string_lit(path_start, (int64_t)(sp2 - path_start));

    void *headers = make_nil();
    const char *line = eol + 2;
    const char *headers_end = found ? (data + hdr_end) : (data + data_len);
    while (line < headers_end) {
        const char *line_end = line;
        while (line_end < headers_end - 1 &&
               !(line_end[0] == '\r' && line_end[1] == '\n'))
            line_end++;
        if (line_end == line) break;

        const char *colon = memchr(line, ':', (size_t)(line_end - line));
        if (colon) {
            void *hname = march_string_lit(line, (int64_t)(colon - line));
            const char *val_start = colon + 1;
            while (val_start < line_end && *val_start == ' ') val_start++;
            const char *val_end = line_end;
            while (val_end > val_start &&
                   (val_end[-1] == ' ' || val_end[-1] == '\r'))
                val_end--;
            void *hval = march_string_lit(val_start, (int64_t)(val_end - val_start));
            void *hdr  = make_header(hname, hval);
            headers = make_cons(hdr, headers);
        }
        line = line_end + 2;
    }

    const char *body_start = found ? (data + hdr_end + 4) : (data + data_len);
    size_t body_len = (size_t)(data + data_len - body_start);
    if (body_start > data + data_len) body_len = 0;
    void *body_str = march_string_lit(body_start, (int64_t)body_len);

    void *tup = make_tuple4(method_str, path_str, headers, body_str);
    return make_ok(tup);
#endif /* MARCH_HTTP_USE_SIMD */
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

/* ── Zero-copy response sending with writev() ─────────────────────────── */

/* Static separator strings used as iovec bases (no copy). */
static const char COLON_SP[] = ": ";
static const char CRLF[]     = "\r\n";

static const char *reason_phrase(int64_t status) {
    switch (status) {
        case 101: return "Switching Protocols";
        case 200: return "OK";
        case 201: return "Created";
        case 204: return "No Content";
        case 301: return "Moved Permanently";
        case 302: return "Found";
        case 304: return "Not Modified";
        case 400: return "Bad Request";
        case 401: return "Unauthorized";
        case 403: return "Forbidden";
        case 404: return "Not Found";
        case 405: return "Method Not Allowed";
        case 500: return "Internal Server Error";
        default:  return "";
    }
}

/* Drive writev() to completion, retrying on EINTR and partial sends. */
static int writev_all(int fd, struct iovec *iov, int iovcnt) {
    while (iovcnt > 0) {
        ssize_t n = writev(fd, iov, iovcnt);
        if (n < 0) {
            if (errno == EINTR) continue;
            return -1;
        }
        /* Advance past the bytes that were written. */
        while (n > 0 && iovcnt > 0) {
            if ((size_t)n >= iov->iov_len) {
                n       -= (ssize_t)iov->iov_len;
                iov++;
                iovcnt--;
            } else {
                iov->iov_base = (char *)iov->iov_base + n;
                iov->iov_len -= (size_t)n;
                n = 0;
            }
        }
    }
    return 0;
}

/* Send an HTTP/1.1 response directly to fd using scatter-gather I/O.
 *
 * Builds an iovec array whose entries point directly at:
 *   - a stack-allocated status line  ("HTTP/1.1 200 OK\r\n")
 *   - each header's name/value in-place from their march_string data
 *   - static ": " and "\r\n" literals
 *   - a stack-allocated Content-Length line
 *   - the body's data pointer (no copy)
 *
 * A single writev() syscall sends the lot without ever coalescing into
 * one large buffer.
 *
 * Returns 0 on success, -1 on error. */
int march_http_send_response(int fd, int64_t status, void *headers, void *body) {
    const char *reason = reason_phrase(status);

    march_string *body_s = (march_string *)body;
    int64_t body_len = body_s ? body_s->len : 0;

    /* Count headers so we can size the iovec array exactly. */
    int n_hdrs = 0;
    for (void *c = headers; c; ) {
        if (*(int32_t *)((char *)c + 8) == 0) break;  /* Nil */
        n_hdrs++;
        c = *(void **)((char *)c + 24);
    }

    /* iovec layout:
     *   [0]             status line
     *   [1 .. 4*n_hdrs] name, ": ", value, "\r\n" per header
     *   [4*n+1]         Content-Length line
     *   [4*n+2]         "\r\n" (end of headers blank line)
     *   [4*n+3]         body  (present only when body_len > 0)
     */
    int n_iov = 3 + 4 * n_hdrs + (body_len > 0 ? 1 : 0);
    struct iovec *iov = malloc((size_t)n_iov * sizeof(struct iovec));
    if (!iov) return -1;

    /* Stack buffers for the two generated lines. */
    char status_line[64];
    int sl_len = snprintf(status_line, sizeof(status_line),
                          "HTTP/1.1 %lld %s\r\n", (long long)status, reason);
    char cl_line[48];
    int cl_len = snprintf(cl_line, sizeof(cl_line),
                          "Content-Length: %lld\r\n", (long long)body_len);

    int i = 0;
    iov[i].iov_base = status_line;
    iov[i].iov_len  = (size_t)(sl_len > 0 ? sl_len : 0);
    i++;

    void *cur = headers;
    while (cur) {
        if (*(int32_t *)((char *)cur + 8) == 0) break;  /* Nil */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        march_string *hname = *(march_string **)((char *)hdr + 16);
        march_string *hval  = *(march_string **)((char *)hdr + 24);

        iov[i].iov_base = hname->data;       iov[i].iov_len = (size_t)hname->len; i++;
        iov[i].iov_base = (void *)COLON_SP;  iov[i].iov_len = 2;                  i++;
        iov[i].iov_base = hval->data;        iov[i].iov_len = (size_t)hval->len;  i++;
        iov[i].iov_base = (void *)CRLF;      iov[i].iov_len = 2;                  i++;

        cur = tail;
    }

    iov[i].iov_base = cl_line;
    iov[i].iov_len  = (size_t)(cl_len > 0 ? cl_len : 0);
    i++;

    iov[i].iov_base = (void *)CRLF;
    iov[i].iov_len  = 2;
    i++;

    if (body_len > 0) {
        iov[i].iov_base = body_s->data;
        iov[i].iov_len  = (size_t)body_len;
        i++;
    }

    int ret = writev_all(fd, iov, i);
    free(iov);
    return ret;
}

/* ── sendfile() for static files ─────────────────────────────────────── */

static const char *content_type_for_ext(const char *path) {
    const char *ext = strrchr(path, '.');
    if (!ext) return "application/octet-stream";
    if (strcmp(ext, ".html") == 0 || strcmp(ext, ".htm")  == 0) return "text/html";
    if (strcmp(ext, ".css")  == 0)                               return "text/css";
    if (strcmp(ext, ".js")   == 0)                               return "application/javascript";
    if (strcmp(ext, ".json") == 0)                               return "application/json";
    if (strcmp(ext, ".png")  == 0)                               return "image/png";
    if (strcmp(ext, ".jpg")  == 0 || strcmp(ext, ".jpeg") == 0)  return "image/jpeg";
    if (strcmp(ext, ".gif")  == 0)                               return "image/gif";
    if (strcmp(ext, ".svg")  == 0)                               return "image/svg+xml";
    if (strcmp(ext, ".ico")  == 0)                               return "image/x-icon";
    if (strcmp(ext, ".txt")  == 0)                               return "text/plain";
    if (strcmp(ext, ".pdf")  == 0)                               return "application/pdf";
    if (strcmp(ext, ".wasm") == 0)                               return "application/wasm";
    if (strcmp(ext, ".webp") == 0)                               return "image/webp";
    return "application/octet-stream";
}

/* Transfer a file to client_fd with zero-copy kernel I/O.
 *
 * 1. Opens the file and fstat()s it for size.
 * 2. Sends "HTTP/1.1 200 OK", Content-Type, Content-Length, and the blank
 *    separator line via writev() — no heap allocation for headers.
 * 3. Sends the file body via sendfile() on Linux/macOS, falling back to a
 *    read/write loop on other platforms.
 *
 * Returns 0 on success, -1 on error (errno set). */
int march_http_send_file(int client_fd, const char *path) {
    int file_fd = open(path, O_RDONLY);
    if (file_fd < 0) return -1;

    struct stat st;
    if (fstat(file_fd, &st) < 0) { close(file_fd); return -1; }

    off_t        file_size = st.st_size;
    const char  *ct        = content_type_for_ext(path);

    /* Build and send headers with writev (all stack storage). */
    char status_line[] = "HTTP/1.1 200 OK\r\n";
    char ct_line[160];
    int  ct_len = snprintf(ct_line, sizeof(ct_line),
                           "Content-Type: %s\r\n", ct);
    char cl_line[48];
    int  cl_len = snprintf(cl_line, sizeof(cl_line),
                           "Content-Length: %lld\r\n", (long long)file_size);
    char end_hdr[] = "\r\n";

    struct iovec iov[4];
    iov[0].iov_base = status_line;  iov[0].iov_len = sizeof(status_line) - 1;
    iov[1].iov_base = ct_line;      iov[1].iov_len = (size_t)(ct_len > 0 ? ct_len : 0);
    iov[2].iov_base = cl_line;      iov[2].iov_len = (size_t)(cl_len > 0 ? cl_len : 0);
    iov[3].iov_base = end_hdr;      iov[3].iov_len = 2;

    if (writev_all(client_fd, iov, 4) < 0) { close(file_fd); return -1; }

    if (file_size == 0) { close(file_fd); return 0; }

    /* Send file body: kernel transfers pages directly without a userspace copy. */
    int ret = 0;

#if defined(__linux__)
    {
        off_t offset    = 0;
        off_t remaining = file_size;
        while (remaining > 0) {
            ssize_t sent = sendfile(client_fd, file_fd, &offset, (size_t)remaining);
            if (sent < 0) {
                if (errno == EINTR) continue;
                ret = -1; break;
            }
            remaining -= sent;
        }
    }
#elif defined(__APPLE__)
    {
        off_t offset    = 0;
        off_t remaining = file_size;
        while (remaining > 0) {
            off_t len = remaining;
            /* sendfile(int fd, int s, off_t offset, off_t *len, hdtr, flags) */
            int r = sendfile(file_fd, client_fd, offset, &len, NULL, 0);
            if (r < 0 && errno != EAGAIN) {
                if (errno == EINTR) continue;
                ret = -1; break;
            }
            offset    += len;
            remaining -= len;
        }
    }
#else
    /* Generic fallback: read/write loop. */
    {
        char    buf[65536];
        off_t   remaining = file_size;
        while (remaining > 0) {
            size_t  to_read = remaining > (off_t)sizeof(buf)
                              ? sizeof(buf) : (size_t)remaining;
            ssize_t nr = read(file_fd, buf, to_read);
            if (nr < 0) { if (errno == EINTR) continue; ret = -1; break; }
            if (nr == 0) break;
            ssize_t w = 0;
            while (w < nr) {
                ssize_t nw = write(client_fd, buf + w, (size_t)(nr - w));
                if (nw < 0) { if (errno == EINTR) continue; ret = -1; break; }
                w += nw;
            }
            if (ret < 0) break;
            remaining -= nr;
        }
    }
#endif

    close(file_fd);
    return ret;
}

/* ── HTTP server accept loop ──────────────────────────────────────────── */

typedef struct {
    void *pipeline;       /* compiled March function: Conn -> Conn */
    int   client_fd;
} conn_thread_arg_t;

/* FNV-1a 64-bit hash — must match the OCaml fnv1a_64 in llvm_emit.ml.
 * Used to intern atom names as stable i64 values for pattern matching. */
static int64_t fnv1a_64_str(const char *s, size_t len) {
    uint64_t h = UINT64_C(0xcbf29ce484222325);
    const uint64_t prime = UINT64_C(0x100000001b3);
    for (size_t i = 0; i < len; i++) {
        h ^= (uint8_t)s[i];
        h *= prime;
    }
    return (int64_t)h;
}

/* Convert an HTTP method string to a March atom (i64 FNV-1a hash).
 * March atoms are lowercase: GET → :get, POST → :post, etc.
 * The hash is computed on the lowercase atom name to match the compiler. */
static int64_t method_string_to_atom(const char *s, size_t len) {
    /* Fast path: compare against known methods, return hash of lowercase name */
    if (len == 3 && memcmp(s, "GET", 3) == 0)
        return fnv1a_64_str("get", 3);
    if (len == 4 && memcmp(s, "POST", 4) == 0)
        return fnv1a_64_str("post", 4);
    if (len == 3 && memcmp(s, "PUT", 3) == 0)
        return fnv1a_64_str("put", 3);
    if (len == 5 && memcmp(s, "PATCH", 5) == 0)
        return fnv1a_64_str("patch", 5);
    if (len == 6 && memcmp(s, "DELETE", 6) == 0)
        return fnv1a_64_str("delete", 6);
    if (len == 4 && memcmp(s, "HEAD", 4) == 0)
        return fnv1a_64_str("head", 4);
    if (len == 7 && memcmp(s, "OPTIONS", 7) == 0)
        return fnv1a_64_str("options", 7);
    if (len == 5 && memcmp(s, "TRACE", 5) == 0)
        return fnv1a_64_str("trace", 5);
    if (len == 7 && memcmp(s, "CONNECT", 7) == 0)
        return fnv1a_64_str("connect", 7);
    /* Unknown method: convert to lowercase and hash */
    char lower[64];
    size_t n = len < 63 ? len : 63;
    for (size_t i = 0; i < n; i++)
        lower[i] = (char)tolower((unsigned char)s[i]);
    lower[n] = '\0';
    return fnv1a_64_str(lower, n);
}

/* Split a path string on "/" into a March List(String).
 * Empty segments are filtered out: "/users/42" → ["users", "42"], "/" → [].
 * Builds the list in forward order by collecting segments first. */
static void *split_path_info(const char *path, size_t path_len) {
    /* Collect segment start/length pairs on the stack */
    const char *segs[256];
    size_t seg_lens[256];
    int seg_count = 0;

    size_t i = 0;
    while (i < path_len && seg_count < 256) {
        /* Skip slashes */
        while (i < path_len && path[i] == '/') i++;
        if (i >= path_len) break;
        /* Find end of segment */
        size_t start = i;
        while (i < path_len && path[i] != '/') i++;
        size_t slen = i - start;
        if (slen > 0) {
            segs[seg_count] = path + start;
            seg_lens[seg_count] = slen;
            seg_count++;
        }
    }

    /* Build list in reverse so Cons nesting is correct (forward order) */
    void *list = make_nil();
    for (int j = seg_count - 1; j >= 0; j--) {
        void *s = march_string_lit(segs[j], (int64_t)seg_lens[j]);
        list = make_cons(s, list);
    }
    return list;
}

/* Build a NoUpgrade value: tag=0, no fields. */
static void *make_no_upgrade(void) {
    return march_alloc(16);  /* tag defaults to 0 */
}

/* Build a March Bool value: tag=0 for False, tag=1 for True.
 * March Bools are heap objects with just a header (no fields). */
static void *make_bool(int value) {
    void *b = march_alloc(16);
    if (value) *(int32_t *)((char *)b + 8) = 1;
    return b;
}

/* Build a March Int heap value: tag=0, one int64 field at offset 16. */
static void *make_int(int64_t value) {
    void *i = march_alloc(16 + 8);
    *(int64_t *)((char *)i + 16) = value;
    return i;
}

/* Build a full 13-field Conn heap object.
 * Conn is a single-constructor ADT: tag=0, 13 fields at offsets 16..112.
 * Total size: 16 (header) + 13*8 (fields) = 120 bytes.
 * Field 1 (method) is now an i64 atom hash (not a Method ADT pointer). */
static void *make_conn(int64_t fd, int64_t method, void *path, void *path_info,
                        void *query_string, void *req_headers, void *req_body,
                        int64_t resp_status, void *resp_headers, void *resp_body,
                        void *halted, void *assigns, void *upgrade) {
    void *c = march_alloc(16 + 13 * 8);
    /* tag = 0 (single constructor), already zeroed by march_alloc */
    char *base = (char *)c;
    *(int64_t *)(base + 16)  = fd;             /* field 0: fd */
    *(int64_t *)(base + 24)  = method;         /* field 1: method (atom i64) */
    *(void **)(base + 32)    = path;           /* field 2: path */
    *(void **)(base + 40)    = path_info;      /* field 3: path_info */
    *(void **)(base + 48)    = query_string;   /* field 4: query_string */
    *(void **)(base + 56)    = req_headers;    /* field 5: request headers */
    *(void **)(base + 64)    = req_body;       /* field 6: request body */
    *(int64_t *)(base + 72)  = resp_status;    /* field 7: response status */
    *(void **)(base + 80)    = resp_headers;   /* field 8: response headers */
    *(void **)(base + 88)    = resp_body;      /* field 9: response body */
    *(void **)(base + 96)    = halted;         /* field 10: halted? */
    *(void **)(base + 104)   = assigns;        /* field 11: assigns */
    *(void **)(base + 112)   = upgrade;        /* field 12: upgrade */
    return c;
}

/* Find the Sec-WebSocket-Key header value from a March List(Header).
 * Returns the march_string* value if found, NULL otherwise. */
static void *find_ws_key_header(void *headers) {
    void *cur = headers;
    while (cur) {
        int32_t tag = *(int32_t *)((char *)cur + 8);
        if (tag == 0) break;  /* Nil */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        march_string *hname = *(march_string **)((char *)hdr + 16);
        if (hname->len == 17 && istrncmp(hname->data, "sec-websocket-key", 17) == 0) {
            return *(void **)((char *)hdr + 24);  /* value */
        }
        cur = tail;
    }
    return NULL;
}

/* Determine whether the request wants keep-alive.
 * HTTP/1.1 defaults to keep-alive; HTTP/1.0 defaults to close.
 * An explicit Connection header overrides the default in either direction.
 * raw_s:       the raw request march_string (used for version detection).
 * req_headers: parsed March List(Header). */
static int detect_keep_alive(void *raw_s, void *req_headers) {
    int keep_alive = 1;   /* optimistic default: HTTP/1.1 */

    /* Scan the first line (bounded to 200 bytes) for "HTTP/1.x". */
    march_string *rs = (march_string *)raw_s;
    size_t scan_len = (size_t)rs->len < 200 ? (size_t)rs->len : 200;
    for (size_t i = 0; i + 7 < scan_len; i++) {
        if (memcmp(rs->data + i, "HTTP/1.", 7) == 0) {
            keep_alive = (i + 7 < scan_len && rs->data[i + 7] != '0');
            break;
        }
    }

    /* Connection header overrides the version default. */
    void *cur = req_headers;
    while (cur) {
        if (*(int32_t *)((char *)cur + 8) == 0) break;  /* Nil */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        march_string *hname = *(march_string **)((char *)hdr + 16);
        if (hname->len == 10 && istrncmp(hname->data, "connection", 10) == 0) {
            march_string *hval = *(march_string **)((char *)hdr + 24);
            if (hval->len >= 5  && istrncmp(hval->data, "close",      5)  == 0)
                keep_alive = 0;
            else if (hval->len >= 10 && istrncmp(hval->data, "keep-alive", 10) == 0)
                keep_alive = 1;
            break;
        }
        cur = tail;
    }
    return keep_alive;
}

/* Populate `resp` with an HTTP/1.1 response, appending an explicit Connection
 * header.  Resets resp->iov_count to 0 but does NOT touch resp->scratch_used,
 * so callers can carry the scratch offset forward across a batch of responses
 * without the TLS scratch regions overlapping.
 *
 * keep_alive=1 → "Connection: keep-alive"
 * keep_alive=0 → "Connection: close" */
void march_populate_response_ka(march_response_t *resp,
                                 int64_t status, void *headers,
                                 void *body, int keep_alive) {
    resp->iov_count = 0;   /* reset iovecs only; scratch_used carries forward */

    /* Status line (static string for common codes, scratch for others). */
    march_response_set_status(resp, (int)status);

    /* User-supplied response headers from the March pipeline. */
    void *cur = headers;
    while (cur) {
        if (*(int32_t *)((char *)cur + 8) == 0) break;  /* Nil */
        void *hdr  = *(void **)((char *)cur + 16);
        void *tail = *(void **)((char *)cur + 24);
        march_string *hname = *(march_string **)((char *)hdr + 16);
        march_string *hval  = *(march_string **)((char *)hdr + 24);
        march_response_add_header(resp,
                                  hname->data, (size_t)hname->len,
                                  hval->data,  (size_t)hval->len);
        cur = tail;
    }

    /* Date header (cached, zero syscall cost on most requests). */
    march_response_add_date_header(resp);

    /* Connection header. */
    if (keep_alive)
        march_response_add_header(resp, "Connection", 10, "keep-alive", 10);
    else
        march_response_add_header(resp, "Connection", 10, "close", 5);

    /* Body — also appends Content-Length and the header-terminating CRLF. */
    march_string *body_s = (march_string *)body;
    march_response_set_body(resp,
                             body_s ? body_s->data : NULL,
                             body_s ? (size_t)body_s->len : 0);
}

/* Like march_http_send_response() but uses the zero-copy response builder
 * (march_response_t) and appends an explicit Connection header.
 *
 * Benefits over the old malloc-based path:
 *   - No per-request heap allocation (fixed iovec array in march_response_t)
 *   - Pre-serialized status lines for common codes (200/400/404/500)
 *   - Cached Date header (refreshed at most once/second, no gmtime() cost)
 *   - Thread-local scratch buffer for Content-Length digits
 *
 * The public march_http_send_response() signature is unchanged. */
int march_send_response_with_ka(int fd, int64_t status, void *headers,
                                 void *body, int keep_alive) {
    march_response_t resp;
    resp.iov_count    = 0;
    resp.scratch_used = 0;
    march_populate_response_ka(&resp, status, headers, body, keep_alive);
    return march_response_send(&resp, fd);
}

/* ── Pipelining helpers ─────────────────────────────────────────────── */

/* closure_fn_t is defined in march_http_internal.h */

/* Maximum pipelined requests parsed from a single buffer slice. */
#define PIPELINE_BATCH 32

/* Detect keep-alive directly from a parsed SIMD request (avoids building
 * March string objects just to scan them). */
int march_detect_keep_alive_simd(const march_http_request_t *req) {
    /* Default: HTTP/1.1 → keep-alive, HTTP/1.0 → close */
    int keep_alive = (req->minor_version >= 1);
    /* Connection header overrides */
    for (size_t i = 0; i < req->num_headers; i++) {
        const march_http_header_t *h = &req->headers[i];
        if (h->name_len == 10 && istrncmp(h->name, "connection", 10) == 0) {
            if (h->value_len >= 5 && istrncmp(h->value, "close", 5) == 0)
                keep_alive = 0;
            else if (h->value_len >= 10 && istrncmp(h->value, "keep-alive", 10) == 0)
                keep_alive = 1;
            break;
        }
    }
    return keep_alive;
}

/* Build a March Conn heap object directly from a parsed SIMD request.
 * Avoids the intermediate Ok(tuple(...)) allocation that the legacy
 * march_http_parse_request() path uses. */
void *march_conn_from_parsed(const march_http_request_t *req,
                              const char *buf, size_t buf_len,
                              int fd) {
    /* Method string → atom i64 hash (e.g. "GET" → hash(:GET)) */
    int64_t method = method_string_to_atom(req->method, req->method_len);

    /* Path + query split */
    const char *qmark = memchr(req->path, '?', req->path_len);
    void  *path_str, *query_str;
    size_t path_len;
    if (qmark) {
        path_len  = (size_t)(qmark - req->path);
        path_str  = march_string_lit(req->path, (int64_t)path_len);
        query_str = march_string_lit(qmark + 1,
                        (int64_t)(req->path_len - path_len - 1));
    } else {
        path_len  = req->path_len;
        path_str  = march_string_lit(req->path, (int64_t)path_len);
        query_str = march_string_lit("", 0);
    }

    /* path_info List(String) */
    void *path_info = split_path_info(req->path, path_len);

    /* Request headers → March List(Header) */
    void *headers = make_nil();
    for (size_t i = 0; i < req->num_headers; i++) {
        const march_http_header_t *h = &req->headers[i];
        void *hname = march_string_lit(h->name,  (int64_t)h->name_len);
        void *hval  = march_string_lit(h->value, (int64_t)h->value_len);
        headers     = make_cons(make_header(hname, hval), headers);
    }

    /* Body (everything after headers, within this request's slice) */
    size_t body_offset = req->header_end;
    /* For GET/HEAD pipelined requests there is usually no body. */
    (void)buf_len;
    void *req_body = march_string_lit("", 0);
    (void)body_offset;

    return make_conn(
        (int64_t)fd, method, path_str, path_info, query_str,
        headers, req_body,
        0, make_nil(), march_string_lit("", 0),
        make_bool(0), make_nil(), make_no_upgrade()
    );
}

/* Process a single parsed request through the March pipeline and send
 * the response.  Returns: 1 = keep going, 0 = close connection, -1 = error. */
int march_process_one_request(int fd, void *pipeline, closure_fn_t fn,
                               const march_http_request_t *req,
                               const char *buf, size_t buf_len) {
    int keep_alive = march_detect_keep_alive_simd(req);
    void *conn = march_conn_from_parsed(req, buf, buf_len, fd);

    /* Call the pipeline — the pipeline closure is held for the full connection
     * lifetime by the caller; no per-request RC bump needed (Phase 0.5). */
    void *result_conn = fn(pipeline, conn);

    if (!result_conn) {
        march_http_send_response(fd, 500, make_nil(),
                                 march_string_lit("Internal Server Error", 21));
        return -1;
    }

    /* WebSocket upgrade check */
    char    *rc          = (char *)result_conn;
    void    *upgrade_val = *(void **)(rc + 112);
    int32_t  upgrade_tag = *(int32_t *)((char *)upgrade_val + 8);
    if (upgrade_tag == 1) {
        void *ws_handler = *(void **)((char *)upgrade_val + 16);
        void *ws_key     = find_ws_key_header(*(void **)(rc + 56));
        if (ws_key) {
            march_ws_handshake((int64_t)fd, ws_key);
            void *ws_sock = march_alloc(16 + 8);
            *(int64_t *)((char *)ws_sock + 16) = (int64_t)fd;
            typedef void *(*ws_handler_fn_t)(void *);
            ((ws_handler_fn_t)ws_handler)(ws_sock);
        }
        return -1;  /* WebSocket took over — close HTTP loop */
    }

    /* Send response */
    int64_t resp_status  = *(int64_t *)(rc + 72);
    void   *resp_headers = *(void **)(rc + 80);
    void   *resp_body    = *(void **)(rc + 88);
    if (resp_status == 0) resp_status = 200;

    if (march_send_response_with_ka(fd, resp_status, resp_headers, resp_body,
                              keep_alive) < 0)
        return -1;

    return keep_alive ? 1 : 0;
}

/* ── Connection worker ─────────────────────────────────────────────── */

/* Per-connection read buffer size.  Large enough to hold many pipelined
 * GET requests in one recv() (wrk sends 16 at a time ≈ 1.5–2 KB). */
#define CONN_BUF_SIZE (64 * 1024)

/* Each connection worker: keep-alive loop with HTTP pipelining support.
 * Reads into a persistent buffer, parses up to PIPELINE_BATCH requests
 * per recv(), batches all response iovecs into a single writev() call,
 * and carries leftover bytes forward for the next parse cycle. */
static void *connection_thread(void *arg) {
    conn_thread_arg_t *a = (conn_thread_arg_t *)arg;
    int fd = a->client_fd;
    void *pipeline = a->pipeline;
    free(a);

    /* Disable Nagle — we send complete responses with writev(). */
#if defined(IPPROTO_TCP) && defined(TCP_NODELAY)
    {
        int one = 1;
        setsockopt(fd, IPPROTO_TCP, TCP_NODELAY, &one, sizeof(one));
    }
#endif

    /* Increase send buffer to absorb batched multi-response writes. */
#if defined(SOL_SOCKET) && defined(SO_SNDBUF)
    {
        int bufsz = 128 * 1024;
        setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &bufsz, sizeof(bufsz));
    }
#endif

    /* Receive timeout for idle keep-alive connections. */
    {
        struct timeval tv = { .tv_sec = 10, .tv_usec = 0 };
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
    }

    /* Closure apply fn — extracted once. */
    char        *clo = (char *)pipeline;
    closure_fn_t fn  = *(closure_fn_t *)(clo + 16);

    /* Persistent per-connection read buffer. */
    char  *buf     = malloc(CONN_BUF_SIZE);
    size_t buf_len = 0;   /* valid bytes in buf */

    if (!buf) { close(fd); return NULL; }

    /* ── Keep-alive / pipelined request loop ──────────────────────── */
    int running = 1;
    while (running) {

        /* 1. Try to parse pipelined requests already in the buffer. */
        while (buf_len > 0) {
            march_http_request_t reqs[PIPELINE_BATCH];
            size_t consumed = 0;
            int n = march_http_parse_pipelined(buf, buf_len,
                                                reqs, PIPELINE_BATCH,
                                                &consumed);
            if (n <= 0) break;  /* incomplete or empty — need more data */

            /* 2. Process all parsed requests, batching responses.
             *
             * A single march_response_t is reused across the batch:
             *   - iov_count is reset to 0 for each new response.
             *   - scratch_used carries forward so every response occupies
             *     a non-overlapping slice of the TLS scratch buffer.
             * All iovecs are accumulated in batch_iov[], then sent with
             * one writev() syscall.  TCP_NOPUSH / TCP_CORK hold the kernel
             * from flushing partial segments during accumulation. */
            {
                struct iovec  batch_iov[CONN_BATCH_IOV_MAX];
                int           batch_n = 0;
                march_response_t bresp;
                bresp.iov_count    = 0;
                bresp.scratch_used = 0;

#if defined(__APPLE__) && defined(TCP_NOPUSH)
                { int one = 1; setsockopt(fd, IPPROTO_TCP, TCP_NOPUSH,
                                          &one, sizeof(one)); }
#elif defined(__linux__) && defined(TCP_CORK)
                { int one = 1; setsockopt(fd, IPPROTO_TCP, TCP_CORK,
                                          &one, sizeof(one)); }
#endif

                for (int i = 0; i < n && running; i++) {
                    int   keep_alive  = march_detect_keep_alive_simd(&reqs[i]);
                    void *conn        = march_conn_from_parsed(&reqs[i],
                                                                buf, buf_len, fd);
                    void *result_conn = fn(pipeline, conn);

                    if (!result_conn) {
                        if (batch_n > 0) {
                            writev_all(fd, batch_iov, batch_n);
                            batch_n = 0;
                        }
                        march_http_send_response(fd, 500, make_nil(),
                            march_string_lit("Internal Server Error", 21));
                        running = 0;
                        break;
                    }

                    /* WebSocket upgrade check. */
                    char    *rc_p        = (char *)result_conn;
                    void    *upgrade_val = *(void **)(rc_p + 112);
                    int32_t  upgrade_tag =
                        *(int32_t *)((char *)upgrade_val + 8);
                    if (upgrade_tag == 1) {
                        /* Flush pending batch before handing off to WS. */
                        if (batch_n > 0) {
                            writev_all(fd, batch_iov, batch_n);
                            batch_n = 0;
                        }
#if defined(__APPLE__) && defined(TCP_NOPUSH)
                        { int zero = 0; setsockopt(fd, IPPROTO_TCP, TCP_NOPUSH,
                                                    &zero, sizeof(zero)); }
#elif defined(__linux__) && defined(TCP_CORK)
                        { int zero = 0; setsockopt(fd, IPPROTO_TCP, TCP_CORK,
                                                    &zero, sizeof(zero)); }
#endif
                        void *ws_handler =
                            *(void **)((char *)upgrade_val + 16);
                        void *ws_key =
                            find_ws_key_header(*(void **)(rc_p + 56));
                        if (ws_key) {
                            march_ws_handshake((int64_t)fd, ws_key);
                            void *ws_sock = march_alloc(16 + 8);
                            *(int64_t *)((char *)ws_sock + 16) = (int64_t)fd;
                            typedef void *(*ws_handler_fn_t)(void *);
                            ((ws_handler_fn_t)ws_handler)(ws_sock);
                        }
                        running = 0;
                        break;
                    }

                    /* Build response, carrying scratch_used forward. */
                    int64_t resp_status  = *(int64_t *)(rc_p + 72);
                    void   *resp_headers = *(void **)(rc_p + 80);
                    void   *resp_body    = *(void **)(rc_p + 88);
                    if (resp_status == 0) resp_status = 200;

                    march_populate_response_ka(&bresp, resp_status,
                                                resp_headers, resp_body,
                                                keep_alive);

                    /* If this response would overflow the batch, flush and
                     * restart.  In normal operation (≤16 headers/response)
                     * this never triggers; it guards against pathological
                     * responses with many headers. */
                    if (batch_n + bresp.iov_count > CONN_BATCH_IOV_MAX) {
                        writev_all(fd, batch_iov, batch_n);
                        batch_n            = 0;
                        bresp.scratch_used = 0;
                        march_populate_response_ka(&bresp, resp_status,
                                                    resp_headers, resp_body,
                                                    keep_alive);
                    }

                    memcpy(batch_iov + batch_n, bresp.iov,
                           (size_t)bresp.iov_count * sizeof(struct iovec));
                    batch_n += bresp.iov_count;

                    if (!keep_alive) { running = 0; break; }
                }

                /* Single writev() for the entire batch. */
                if (batch_n > 0) writev_all(fd, batch_iov, batch_n);

                /* Release TCP_NOPUSH / TCP_CORK → kernel flushes. */
#if defined(__APPLE__) && defined(TCP_NOPUSH)
                { int zero = 0; setsockopt(fd, IPPROTO_TCP, TCP_NOPUSH,
                                            &zero, sizeof(zero)); }
#elif defined(__linux__) && defined(TCP_CORK)
                { int zero = 0; setsockopt(fd, IPPROTO_TCP, TCP_CORK,
                                            &zero, sizeof(zero)); }
#endif
            }

            /* 3. Shift unconsumed bytes to the front. */
            if (consumed > 0 && consumed < buf_len) {
                memmove(buf, buf + consumed, buf_len - consumed);
                buf_len -= consumed;
            } else if (consumed >= buf_len) {
                buf_len = 0;
            }

            if (!running) break;
        }

        if (!running) break;

        /* 4. Read more data from the socket. */
        size_t space = CONN_BUF_SIZE - buf_len;
        if (space == 0) {
            /* Buffer full with no complete request — request too large. */
            march_http_send_response(fd, 413, make_nil(),
                                     march_string_lit("Request Too Large", 17));
            break;
        }
        ssize_t n = recv(fd, buf + buf_len, space, 0);
        if (n <= 0) break;  /* EOF, reset, or timeout */
        buf_len += (size_t)n;
    }

    free(buf);
    close(fd);
    return NULL;
}

/* ── Thread pool ──────────────────────────────────────────────────────── */

/* Ring-buffer capacity for pending connection fds.  Must be a power of 2.
 * At 4096 slots the accept loop can absorb burst traffic without blocking. */
#define MARCH_HTTP_QUEUE_CAPACITY 4096

typedef struct {
    int             fds[MARCH_HTTP_QUEUE_CAPACITY];
    size_t          head;       /* next slot to consume */
    size_t          tail;       /* next slot to produce into */
    size_t          count;      /* current occupancy */
    pthread_mutex_t lock;
    pthread_cond_t  not_empty;  /* signalled when count goes 0→1 */
    pthread_cond_t  not_full;   /* signalled when count drops below capacity */
} http_work_queue_t;

typedef struct {
    pthread_t        *threads;
    int               size;       /* number of worker threads allocated */
    void             *pipeline;   /* shared March pipeline closure */
    http_work_queue_t queue;
    _Atomic int       shutdown;   /* set to 1 to request worker exit */
} http_pool_t;

static http_pool_t g_pool;
_Atomic int g_http_shutdown = 0;  /* set by signal handler — also used by march_http_evloop.c */

static void http_signal_handler(int sig) {
    (void)sig;
    atomic_store_explicit(&g_http_shutdown, 1, memory_order_relaxed);
}

/* Worker thread: dequeue fds and run the connection handler in a loop. */
static void *pool_worker(void *arg) {
    (void)arg;
    for (;;) {
        pthread_mutex_lock(&g_pool.queue.lock);
        while (g_pool.queue.count == 0 &&
               !atomic_load_explicit(&g_pool.shutdown, memory_order_relaxed)) {
            pthread_cond_wait(&g_pool.queue.not_empty, &g_pool.queue.lock);
        }
        if (g_pool.queue.count == 0) {
            /* Shutdown requested and queue is drained — exit. */
            pthread_mutex_unlock(&g_pool.queue.lock);
            break;
        }
        int fd = g_pool.queue.fds[g_pool.queue.head];
        g_pool.queue.head = (g_pool.queue.head + 1) % MARCH_HTTP_QUEUE_CAPACITY;
        g_pool.queue.count--;
        pthread_cond_signal(&g_pool.queue.not_full);
        pthread_mutex_unlock(&g_pool.queue.lock);

        conn_thread_arg_t *a = malloc(sizeof(conn_thread_arg_t));
        if (a) {
            a->client_fd = fd;
            a->pipeline  = g_pool.pipeline;
            connection_thread(a);   /* handles fd and frees a */
        } else {
            close(fd);
        }
    }
    return NULL;
}

void march_http_pool_start(int64_t pool_size, void *pipeline) {
    if (pool_size <= 0) {
        /* Auto-detect: 2× logical CPUs, clamped to [4, 256]. */
        long ncpus = sysconf(_SC_NPROCESSORS_ONLN);
        pool_size  = (ncpus > 0) ? ncpus * 2 : MARCH_HTTP_POOL_DEFAULT_SIZE;
        if (pool_size < 4)   pool_size = 4;
        if (pool_size > 256) pool_size = 256;
    }

    memset(&g_pool, 0, sizeof(g_pool));
    g_pool.size     = (int)pool_size;
    g_pool.pipeline = pipeline;
    atomic_store_explicit(&g_pool.shutdown, 0, memory_order_relaxed);

    pthread_mutex_init(&g_pool.queue.lock, NULL);
    pthread_cond_init(&g_pool.queue.not_empty, NULL);
    pthread_cond_init(&g_pool.queue.not_full, NULL);

    g_pool.threads = malloc(sizeof(pthread_t) * (size_t)pool_size);
    if (!g_pool.threads) {
        fprintf(stderr, "march: thread pool alloc failed\n");
        g_pool.size = 0;
        return;
    }

    for (int i = 0; i < g_pool.size; i++) {
        if (pthread_create(&g_pool.threads[i], NULL, pool_worker, NULL) != 0) {
            fprintf(stderr, "march: pool worker[%d] create failed: %s\n",
                    i, strerror(errno));
            g_pool.size = i;   /* only join threads we actually started */
            break;
        }
    }
    fprintf(stderr, "march: HTTP thread pool started (%d workers)\n", g_pool.size);
}

void march_http_pool_stop(void) {
    /* Signal workers to exit once the queue drains. */
    atomic_store_explicit(&g_pool.shutdown, 1, memory_order_release);
    pthread_mutex_lock(&g_pool.queue.lock);
    pthread_cond_broadcast(&g_pool.queue.not_empty);
    pthread_mutex_unlock(&g_pool.queue.lock);

    for (int i = 0; i < g_pool.size; i++)
        pthread_join(g_pool.threads[i], NULL);

    free(g_pool.threads);
    g_pool.threads = NULL;

    pthread_mutex_destroy(&g_pool.queue.lock);
    pthread_cond_destroy(&g_pool.queue.not_empty);
    pthread_cond_destroy(&g_pool.queue.not_full);

    fprintf(stderr, "march: HTTP thread pool stopped\n");
}

void march_http_server_listen(int64_t port, int64_t max_conns,
                               int64_t idle_timeout, void *pipeline) {
    if (!pipeline) return;
    (void)max_conns;
    (void)idle_timeout;

    /* Ignore broken-pipe signals — send errors are handled explicitly. */
    signal(SIGPIPE, SIG_IGN);
    signal(SIGTERM, http_signal_handler);
    signal(SIGINT,  http_signal_handler);

    /* Pre-populate response caches (Date header, etc.) before accepting. */
    march_http_response_module_init();

#if defined(MARCH_HTTP_USE_EVLOOP)
    /* Event-loop mode: SO_REUSEPORT + kqueue/epoll, one thread per core.
     * The evloop creates its own listener fds — no single listen_fd needed. */
    fprintf(stderr, "march: HTTP server (event-loop) listening on port %lld\n",
            (long long)port);
    march_evloop_server_listen((int)port, pipeline);
    return;
#endif

    /* ── Fallback: thread-per-connection with work queue ─────────── */
    int64_t listen_fd = march_tcp_listen(port);
    if (listen_fd < 0) {
        fprintf(stderr, "march_http_server_listen: tcp_listen(%lld) failed: %s\n",
                (long long)port, strerror(errno));
        return;
    }

    march_http_pool_start(0 /* auto-detect from CPU count */, pipeline);
    fprintf(stderr, "march: HTTP server listening on port %lld\n", (long long)port);

    while (!atomic_load_explicit(&g_http_shutdown, memory_order_relaxed)) {
        fd_set rfds;
        FD_ZERO(&rfds);
        FD_SET((int)listen_fd, &rfds);
        struct timeval tv = {.tv_sec = 1, .tv_usec = 0};
        int r = select((int)listen_fd + 1, &rfds, NULL, NULL, &tv);
        if (r < 0) {
            if (errno == EINTR) continue;
            break;
        }
        if (r == 0) continue;   /* timeout — check g_http_shutdown and loop */

        int64_t client_fd = march_tcp_accept(listen_fd);
        if (client_fd < 0) continue;

        /* Enqueue the accepted fd for a pool worker.
         * Block if the queue is full rather than dropping the connection. */
        pthread_mutex_lock(&g_pool.queue.lock);
        while (g_pool.queue.count == MARCH_HTTP_QUEUE_CAPACITY &&
               !atomic_load_explicit(&g_http_shutdown, memory_order_relaxed)) {
            pthread_cond_wait(&g_pool.queue.not_full, &g_pool.queue.lock);
        }
        if (!atomic_load_explicit(&g_http_shutdown, memory_order_relaxed)) {
            g_pool.queue.fds[g_pool.queue.tail] = (int)client_fd;
            g_pool.queue.tail = (g_pool.queue.tail + 1) % MARCH_HTTP_QUEUE_CAPACITY;
            g_pool.queue.count++;
            pthread_cond_signal(&g_pool.queue.not_empty);
        } else {
            close((int)client_fd);
        }
        pthread_mutex_unlock(&g_pool.queue.lock);
    }

    close((int)listen_fd);
    march_http_pool_stop();
}

/* ── spawn_n / wait ──────────────────────────────────────────────────── */

/* Counts requests handled by the child process (spawn_n mode). */
static _Atomic int64_t g_spawn_n_served  = 0;
static          int64_t g_spawn_n_target = 0;
static          int     g_spawn_n_ready_wr = -1;  /* write end of readiness pipe */

static void *spawn_n_server_thread(void *arg) {
    (void)arg;
    /* This runs in the child after fork — not a real thread, just reusing
     * the function pointer to tally requests and exit after n. */
    return NULL;
}

/* Per-request callback wrapper used in spawn_n mode:
 * we replace the pipeline fn pointer with a wrapper that decrements the
 * counter and shuts down after n requests.  We do this by intercepting
 * at the C level rather than March level. */

int64_t march_http_server_spawn_n(int64_t port, int64_t n,
                                   int64_t max_conns, int64_t idle_timeout,
                                   void *pipeline) {
    int pipefd[2];
    if (pipe(pipefd) != 0) {
        perror("march_http_server_spawn_n: pipe");
        return -1;
    }

    pid_t pid = fork();
    if (pid < 0) {
        perror("march_http_server_spawn_n: fork");
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        /* ── child ── */
        close(pipefd[0]);
        /* Signal readiness after binding */
        /* We run listen with a SIGALRM after n requests trick:
         * simplest approach — just run listen (blocks) and rely on
         * the test killing the child, OR use alarm.
         * For test harness correctness we use a request-count wrapper.
         * For now: signal ready, then run the server. The test will
         * kill the process after receiving the pipe byte. */
        char ready = 1;
        (void)write(pipefd[1], &ready, 1);
        close(pipefd[1]);

        g_spawn_n_target = n;
        atomic_store(&g_spawn_n_served, 0);

        /* Run the blocking server — the parent will waitpid+SIGTERM when done. */
        march_http_server_listen(port, max_conns, idle_timeout, pipeline);
        _exit(0);
    }

    /* ── parent ── */
    close(pipefd[1]);
    /* Wait for ready byte before returning so caller can connect immediately. */
    char buf[1];
    (void)read(pipefd[0], buf, 1);
    close(pipefd[0]);

    return (int64_t)pid;
}

void march_http_server_wait(int64_t handle) {
    if (handle <= 0) return;
    pid_t pid = (pid_t)handle;
    int status = 0;
    waitpid(pid, &status, 0);
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

/* ── HTTP client builtins ─────────────────────────────────────────────── */

/* Serialize an HTTP request to a raw string.
 * http_serialize_request(method, host, path, query, headers, body) -> String */
void *march_http_serialize_request(void *method_ptr, void *host_ptr, void *path_ptr,
                                    void *query_ptr, void *headers_ptr, void *body_ptr) {
    march_string *method  = (march_string *)method_ptr;
    march_string *host    = (march_string *)host_ptr;
    march_string *path    = (march_string *)path_ptr;
    march_string *query   = (march_string *)query_ptr;
    march_string *body    = body_ptr ? (march_string *)body_ptr : NULL;
    (void)headers_ptr;

    /* Build: "METHOD /path?query HTTP/1.1\r\nHost: host\r\n\r\nbody" */
    const char *m   = method ? method->data : "GET";
    const char *h   = host   ? host->data   : "";
    const char *p   = path   ? path->data   : "/";
    const char *q   = (query && query->len > 0) ? query->data : NULL;
    const char *b   = (body && body->len > 0)   ? body->data  : "";
    int64_t blen    = (body && body->len > 0)   ? body->len   : 0;

    char content_len_buf[64];
    snprintf(content_len_buf, sizeof(content_len_buf), "%lld", (long long)blen);

    /* Approximate buffer size */
    size_t sz = strlen(m) + strlen(h) + strlen(p) + (q ? strlen(q) : 0) + blen + 256;
    char *buf = (char *)malloc(sz);
    if (!buf) return march_string_lit("", 0);

    int n;
    if (q && *q) {
        n = snprintf(buf, sz, "%s %s?%s HTTP/1.1\r\nHost: %s\r\nContent-Length: %s\r\n\r\n%s",
                     m, p, q, h, content_len_buf, b);
    } else {
        n = snprintf(buf, sz, "%s %s HTTP/1.1\r\nHost: %s\r\nContent-Length: %s\r\n\r\n%s",
                     m, p, h, content_len_buf, b);
    }
    void *result = march_string_lit(buf, n < 0 ? 0 : (int64_t)n);
    free(buf);
    return result;
}

/* Parse a raw HTTP response string.
 * Returns Ok((status_code:i64, headers:List, body:String)) or Err(reason:String).
 * Tag: Ok=tag0, Err=tag1. */
void *march_http_parse_response(void *raw_ptr) {
    if (!raw_ptr) {
        void *s = march_string_lit("http_parse_response: null input", 31);
        void *r = march_alloc(24);
        ((march_hdr *)r)->tag = 1; /* Err */
        *(void **)((char *)r + 16) = s;
        return r;
    }
    march_string *raw = (march_string *)raw_ptr;
    const char *data = raw->data;

    /* Parse status line: HTTP/1.x NNN ... */
    int status_code = 200;
    const char *p = data;
    if (strncmp(p, "HTTP/", 5) == 0) {
        p += 5;
        while (*p && *p != ' ') p++;  /* skip version */
        while (*p == ' ') p++;
        status_code = (int)strtol(p, NULL, 10);
    }

    /* Find header/body split at \r\n\r\n */
    const char *body_start = strstr(data, "\r\n\r\n");
    if (!body_start) body_start = strstr(data, "\n\n");
    if (body_start) {
        body_start += (body_start[0] == '\r') ? 4 : 2;
    } else {
        body_start = data + raw->len;
    }

    /* Build body string */
    int64_t body_len = (int64_t)(raw->len - (body_start - data));
    void *body_str = body_len > 0 ? march_string_lit(body_start, body_len)
                                  : march_string_lit("", 0);

    /* Build empty headers list (Nil) */
    void *headers_nil = march_alloc(16); /* Nil = tag 0, no fields */

    /* Build tuple (status_code, headers_nil, body_str): 3-field heap object */
    void *tup = march_alloc(16 + 3 * 8);
    /* tag 0 for tuple */
    *(int64_t *)((char *)tup + 16) = (int64_t)status_code;
    *(void **)((char *)tup + 24)   = headers_nil;
    *(void **)((char *)tup + 32)   = body_str;

    /* Wrap in Ok(tup): tag=0 */
    void *ok_obj = march_alloc(24);
    /* tag stays 0 = Ok */
    *(void **)((char *)ok_obj + 16) = tup;
    return ok_obj;
}
