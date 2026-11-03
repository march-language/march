/* march_compress_common.h -- what the compression shims share: the input and
 * output caps and the Bytes/Result helpers.  Static inline, so each codec file
 * (march_compress.c: gzip/deflate over zlib; march_compress_zstd.c;
 * march_compress_brotli.c) is a self-contained archive member: a program that
 * reaches one codec links that member and its library, never another's
 * (specs/2026-09-23-static-compile-output-design.md, Stage 3). */
#ifndef MARCH_COMPRESS_COMMON_H
#define MARCH_COMPRESS_COMMON_H

#include "march_runtime.h"
#include "march_gc.h"

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>
#include <limits.h>

/* 256 MB limits guard against decompression bombs and uInt overflow.
 * Input cap ensures compressBound(in_len)+overhead fits in a 32-bit uInt.
 * Output cap is checked in grow loops before every realloc. */
#define MAX_INPUT_SIZE      ((size_t)(256 * 1024 * 1024))
#define MAX_DECOMPRESS_SIZE ((size_t)(256 * 1024 * 1024))

/* ── Helpers (mirrors march_extras.c) ────────────────────────────────────── */

/* Bytes is Bytes(String): a one-field boxed ADT cell whose field 0 (offset 16)
 * is a march_string — one allocation, explicit length, contiguous payload.
 *
 * This is the hottest instance of the old representation's cost.  Building a
 * Bytes from raw used to allocate one ~32-byte cons cell per byte, so
 * march_gzip_decode of a 12 MB tar allocated ~12M cells (hundreds of MB) and
 * a 3.1 MB tarball could not be processed at all; reading one back walked the
 * whole spine twice.  Both are now a single memcpy.  See
 * specs/plans/2026-08-10-array-backed-bytes-design.md. */
static inline void *compress_bytes_from_raw(const uint8_t *data, size_t len) {
    void *s = march_string_lit((const char *)data, (int64_t)len);
    void *b = march_alloc(16 + 8);
    /* tag = 0 = Bytes ctor */
    ((march_hdr *)b)->pad = march_bytes_type_id();
    *(void **)((char *)b + 16) = s;
    return b;
}

/* Returns a malloc'd copy; caller frees.  The copy (rather than borrowing
 * march_string::data) is kept because every caller below owns and frees the
 * buffer, and zlib/zstd/brotli want a plain uint8_t* they may not alias the
 * March heap for. */
static inline uint8_t *compress_bytes_to_raw(void *bytes_val, size_t *out_len) {
    march_string *ms = *(march_string **)((char *)bytes_val + 16);
    size_t n = ms ? (size_t)ms->len : 0;
    uint8_t *buf = malloc(n > 0 ? n : 1);
    if (!buf) { *out_len = 0; return NULL; }
    if (n > 0) memcpy(buf, ms->data, n);
    *out_len = n;
    return buf;
}

static inline void *compress_make_ok(void *val) {
    void *r = march_alloc(16 + 8);
    /* tag = 0 = Ok */
    *(void **)((char *)r + 16) = val;
    return r;
}

static inline void *compress_make_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1; /* tag = 1 = Err */
    *(void **)((char *)r + 16) = s;
    return r;
}

#endif /* MARCH_COMPRESS_COMMON_H */
