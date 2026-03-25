/* runtime/march_http_parse_simd.c — SIMD-accelerated HTTP/1.x request parser.
 *
 * Fast path: SSE4.2 PCMPESTRI scans 16 bytes per cycle to locate HTTP
 * delimiters (\r, \n, :, space).  Enabled at compile time when the
 * translation unit is built with -msse4.2 (or equivalent).
 *
 * Fallback: plain scalar byte-by-byte scan, always compiled in.
 *
 * Technique adapted from picohttpparser (Kazuho Oku, MIT licence).
 * We implement the same SIMD ideas independently.
 *
 * Compile:
 *   # x86-64 — enables SSE4.2 fast path:
 *   cc -std=gnu11 -msse4.2 -O2 march_http_parse_simd.c
 *
 *   # ARM64 / other — uses scalar fallback, -msse4.2 is harmless:
 *   cc -std=gnu11 -O2 march_http_parse_simd.c
 */

#include "march_http_parse_simd.h"

#include <string.h>
#include <stdlib.h>

/* ── SSE4.2 availability ─────────────────────────────────────────────── */

#if defined(__SSE4_2__)
#  include <nmmintrin.h>   /* _mm_cmpestri, _mm_loadu_si128, etc. */
#  define HAVE_SSE42 1
#else
#  define HAVE_SSE42 0
#endif

int march_http_simd_available(void) {
    return HAVE_SSE42;
}

/* ── Delimiter sets ──────────────────────────────────────────────────── */

/* Chars that end the HTTP method field: space only. */
#define TOKEN_METHOD_END ' '
/* Chars that end the URI / path field: space only. */
#define TOKEN_PATH_END   ' '

/* ── Scalar helpers ──────────────────────────────────────────────────── */

/* Find the next occurrence of ch in s[0..len).
 * Returns pointer to found char, or NULL if not found. */
static inline const char *scalar_find_ch(const char *s, size_t len, char ch) {
    for (size_t i = 0; i < len; i++) {
        if (s[i] == ch) return s + i;
    }
    return NULL;
}

/* Find the next occurrence of \r\n in s[0..len).
 * Returns pointer to the \r, or NULL if not found. */
static const char *scalar_find_crlf(const char *s, size_t len) {
    if (len < 2) return NULL;
    for (size_t i = 0; i + 1 < len; i++) {
        if (s[i] == '\r' && s[i+1] == '\n') return s + i;
    }
    return NULL;
}

/* Find the next ':' or '\r' in s[0..len), used for header name scanning. */
static const char *scalar_find_colon_or_cr(const char *s, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (s[i] == ':' || s[i] == '\r') return s + i;
    }
    return NULL;
}

/* ── SIMD helpers (x86-64 SSE4.2 only) ──────────────────────────────── */

#if HAVE_SSE42

/* Delimiter set for header scanning: CR, LF, colon, space.
 * PCMPESTRI with _SIDD_CMP_EQUAL_ANY returns the index of the first
 * byte in the 16-byte chunk that matches any of these 4 characters. */
static const char SIMD_DELIMITERS[16] = {
    '\r', '\n', ':', ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
};
#define SIMD_DELIM_COUNT 4

/* Find the first delimiter byte in s[0..len), processing 16 bytes at a time.
 * Returns pointer to first delimiter found, or s+len if none in range. */
__attribute__((target("sse4.2")))
static const char *simd_find_delimiter(const char *s, size_t len) {
    __m128i delims = _mm_loadu_si128((const __m128i *)SIMD_DELIMITERS);

    size_t i = 0;
    /* Process 16-byte chunks with PCMPESTRI */
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(s + i));
        int idx = _mm_cmpestri(delims, SIMD_DELIM_COUNT,
                               chunk, 16,
                               _SIDD_UBYTE_OPS | _SIDD_CMP_EQUAL_ANY |
                               _SIDD_LEAST_SIGNIFICANT);
        if (idx < 16) return s + i + idx;
        i += 16;
    }
    /* Scalar tail */
    for (; i < len; i++) {
        char c = s[i];
        if (c == '\r' || c == '\n' || c == ':' || c == ' ')
            return s + i;
    }
    return s + len;
}

/* Find CR in s[0..len) using SIMD (for end-of-line scanning). */
__attribute__((target("sse4.2")))
static const char *simd_find_cr(const char *s, size_t len) {
    /* Delimiter set: just \r repeated to fill 4 slots */
    static const char CR_SET[16] = {
        '\r', '\r', '\r', '\r', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    __m128i delims = _mm_loadu_si128((const __m128i *)CR_SET);

    size_t i = 0;
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(s + i));
        int idx = _mm_cmpestri(delims, 4, chunk, 16,
                               _SIDD_UBYTE_OPS | _SIDD_CMP_EQUAL_ANY |
                               _SIDD_LEAST_SIGNIFICANT);
        if (idx < 16) return s + i + idx;
        i += 16;
    }
    for (; i < len; i++) {
        if (s[i] == '\r') return s + i;
    }
    return NULL;
}

/* Find space in s[0..len) using SIMD (for method / path end). */
__attribute__((target("sse4.2")))
static const char *simd_find_space(const char *s, size_t len) {
    static const char SP_SET[16] = {
        ' ', ' ', ' ', ' ', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    __m128i delims = _mm_loadu_si128((const __m128i *)SP_SET);

    size_t i = 0;
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(s + i));
        int idx = _mm_cmpestri(delims, 4, chunk, 16,
                               _SIDD_UBYTE_OPS | _SIDD_CMP_EQUAL_ANY |
                               _SIDD_LEAST_SIGNIFICANT);
        if (idx < 16) return s + i + idx;
        i += 16;
    }
    for (; i < len; i++) {
        if (s[i] == ' ') return s + i;
    }
    return NULL;
}

/* Find colon or CR in s[0..len) using SIMD (header name end). */
__attribute__((target("sse4.2")))
static const char *simd_find_colon_or_cr(const char *s, size_t len) {
    static const char COLON_CR[16] = {
        ':', '\r', ':', '\r', 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
    };
    __m128i delims = _mm_loadu_si128((const __m128i *)COLON_CR);

    size_t i = 0;
    while (i + 16 <= len) {
        __m128i chunk = _mm_loadu_si128((const __m128i *)(s + i));
        int idx = _mm_cmpestri(delims, 4, chunk, 16,
                               _SIDD_UBYTE_OPS | _SIDD_CMP_EQUAL_ANY |
                               _SIDD_LEAST_SIGNIFICANT);
        if (idx < 16) return s + i + idx;
        i += 16;
    }
    for (; i < len; i++) {
        if (s[i] == ':' || s[i] == '\r') return s + i;
    }
    return NULL;
}

#endif /* HAVE_SSE42 */

/* ── Unified dispatch wrappers ───────────────────────────────────────── */
/* These call the SIMD version when available, scalar otherwise. */

static inline const char *find_space(const char *s, size_t len) {
#if HAVE_SSE42
    return simd_find_space(s, len);
#else
    return scalar_find_ch(s, len, ' ');
#endif
}

static inline const char *find_crlf(const char *s, size_t len) {
#if HAVE_SSE42
    /* Use simd_find_cr then verify the LF follows */
    const char *cr = simd_find_cr(s, len);
    if (!cr) return NULL;
    size_t remaining = (size_t)(s + len - cr);
    /* Walk from cr position looking for \r\n */
    for (size_t i = 0; i + 1 < remaining; i++) {
        if (cr[i] == '\r' && cr[i+1] == '\n') return cr + i;
        /* Not a CRLF at this \r; skip and let scalar handle rest */
    }
    return NULL;
#else
    return scalar_find_crlf(s, len);
#endif
}

static inline const char *find_colon_or_cr(const char *s, size_t len) {
#if HAVE_SSE42
    return simd_find_colon_or_cr(s, len);
#else
    return scalar_find_colon_or_cr(s, len);
#endif
}

/* ── Token validation helpers ────────────────────────────────────────── */

/* Check that the method string contains only valid HTTP token chars.
 * We accept A-Z and a-z (some extensions use lowercase). */
static inline int valid_method(const char *m, size_t len) {
    if (len == 0 || len > 16) return 0;
    for (size_t i = 0; i < len; i++) {
        char c = m[i];
        /* Standard HTTP methods are uppercase alpha; also allow lowercase */
        if (!((c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
              c == '_' || c == '-'))
            return 0;
    }
    return 1;
}

/* ── Core parser ─────────────────────────────────────────────────────── */

int march_http_parse_request_simd(const char *buf, size_t len,
                                   march_http_request_t *req) {
    if (!buf || !req || len == 0) return -1;

    const char *p   = buf;
    const char *end = buf + len;

#define REMAINING()  ((size_t)(end - p))
#define ADVANCE(n)   do { p += (n); } while (0)
#define NEED(n)      do { if (REMAINING() < (size_t)(n)) return 0; } while (0)

    /* ── Request line: METHOD SP path SP HTTP/1.x CRLF ── */

    /* Find end of method */
    const char *sp = find_space(p, REMAINING());
    if (!sp) {
        /* No space yet — incomplete if buffer might grow */
        return 0;
    }
    req->method     = p;
    req->method_len = (size_t)(sp - p);
    if (!valid_method(req->method, req->method_len)) return -1;

    ADVANCE(req->method_len + 1); /* skip method + space */

    /* Find end of path (next space) */
    sp = find_space(p, REMAINING());
    if (!sp) return 0; /* incomplete */

    req->path     = p;
    req->path_len = (size_t)(sp - p);
    if (req->path_len == 0) return -1; /* empty path */

    ADVANCE(req->path_len + 1); /* skip path + space */

    /* Parse HTTP version: "HTTP/1.x" */
    NEED(8);
    if (p[0] != 'H' || p[1] != 'T' || p[2] != 'T' || p[3] != 'P' ||
        p[4] != '/' || p[5] != '1' || p[6] != '.') {
        return -1;
    }
    if (p[7] == '0') {
        req->minor_version = 0;
    } else if (p[7] == '1') {
        req->minor_version = 1;
    } else {
        return -1;
    }
    ADVANCE(8); /* past "HTTP/1.x" */

    /* Expect CRLF after version */
    NEED(2);
    if (p[0] != '\r' || p[1] != '\n') return -1;
    ADVANCE(2);

    /* ── Headers ── */
    req->num_headers = 0;

    for (;;) {
        /* Check for end-of-headers blank line */
        NEED(2);
        if (p[0] == '\r' && p[1] == '\n') {
            ADVANCE(2);
            break; /* end of headers */
        }

        if (req->num_headers >= MARCH_HTTP_MAX_HEADERS) return -1;

        march_http_header_t *hdr = &req->headers[req->num_headers];

        /* Header name: up to ':' */
        const char *colon = find_colon_or_cr(p, REMAINING());
        if (!colon) return 0; /* incomplete */
        if (*colon == '\r') return -1; /* no colon on this line */
        if (colon == p) return -1; /* empty name */

        hdr->name     = p;
        hdr->name_len = (size_t)(colon - p);
        ADVANCE(hdr->name_len + 1); /* skip name + ':' */

        /* Skip optional leading whitespace in value */
        while (REMAINING() > 0 && (*p == ' ' || *p == '\t')) ADVANCE(1);

        /* Header value: up to CRLF */
        const char *crlf = find_crlf(p, REMAINING());
        if (!crlf) return 0; /* incomplete */

        /* Trim trailing whitespace from value */
        const char *val_end = crlf;
        while (val_end > p && (val_end[-1] == ' ' || val_end[-1] == '\t'))
            val_end--;

        hdr->value     = p;
        hdr->value_len = (size_t)(val_end - p);
        ADVANCE((size_t)(crlf - p) + 2); /* skip value + CRLF */

        req->num_headers++;
    }

    req->header_end = (size_t)(p - buf);

#undef REMAINING
#undef ADVANCE
#undef NEED

    return (int)req->header_end;
}

/* ── Pipelined request parser ────────────────────────────────────────── */

int march_http_parse_pipelined(const char *buf, size_t len,
                                march_http_request_t *reqs, int max_reqs,
                                size_t *consumed) {
    *consumed = 0;
    int count = 0;

    while (count < max_reqs && *consumed < len) {
        march_http_request_t *req = &reqs[count];
        const char *cur = buf + *consumed;
        size_t remaining = len - *consumed;

        int result = march_http_parse_request_simd(cur, remaining, req);
        if (result <= 0) {
            /* 0 = incomplete, -1 = error; stop pipeline parsing */
            break;
        }

        /* Adjust all pointers in req to be relative to buf (they already
         * point into the original buffer since cur is a slice of buf). */
        *consumed += (size_t)result;
        count++;
    }

    return count;
}
