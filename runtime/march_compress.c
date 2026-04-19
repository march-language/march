/* march_compress.c — gzip, deflate, zstd, and brotli shims for the March
 * native compiler.  Each function receives/returns March heap values
 * (Bytes(List(Int)) and Result(Bytes, String)) via the same helpers used in
 * march_extras.c.
 *
 * Link flags required:
 *   always:   -lz          (zlib, system library on macOS/Linux)
 *   optional: -lzstd       (brew install zstd  / apt install libzstd-dev)
 *   optional: -lbrotlienc -lbrotlidec
 *             (brew install brotli / apt install libbrotli-dev)
 *
 * When optional libraries are absent the functions return Err("...not available").
 */

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

static void *compress_bytes_from_raw(const uint8_t *data, size_t len) {
    void *list = march_alloc(16); /* Nil */
    for (ssize_t i = (ssize_t)len - 1; i >= 0; i--) {
        void *node = march_alloc(16 + 8 + 8);
        *(int32_t *)((char *)node + 8) = 1; /* tag = Cons */
        *(int64_t *)((char *)node + 16) = (int64_t)data[i];
        *(void **)((char *)node + 24) = list;
        list = node;
    }
    void *b = march_alloc(16 + 8);
    /* tag = 0 = Bytes ctor */
    *(void **)((char *)b + 16) = list;
    return b;
}

static uint8_t *compress_bytes_to_raw(void *bytes_val, size_t *out_len) {
    void *list = *(void **)((char *)bytes_val + 16);
    size_t n = 0;
    void *p = list;
    while (p) {
        int32_t tag = *(int32_t *)((char *)p + 8);
        if (tag == 0) break;
        n++;
        p = *(void **)((char *)p + 24);
    }
    uint8_t *buf = malloc(n > 0 ? n : 1);
    if (!buf) { *out_len = 0; return NULL; }
    *out_len = n;
    p = list; size_t i = 0;
    while (p && i < n) {
        int32_t tag = *(int32_t *)((char *)p + 8);
        if (tag == 0) break;
        buf[i++] = (uint8_t)(*(int64_t *)((char *)p + 16) & 0xFF);
        p = *(void **)((char *)p + 24);
    }
    return buf;
}

static void *compress_make_ok(void *val) {
    void *r = march_alloc(16 + 8);
    /* tag = 0 = Ok */
    *(void **)((char *)r + 16) = val;
    return r;
}

static void *compress_make_err(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1; /* tag = 1 = Err */
    *(void **)((char *)r + 16) = s;
    return r;
}

/* ── Gzip / Deflate (always available via zlib) ──────────────────────────── */

#include <zlib.h>

/* gzip_encode: level = -1 for Z_DEFAULT_COMPRESSION, 1–9 explicit */
void *march_gzip_encode(void *bytes_val, int64_t level) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("gzip_encode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("gzip_encode: input too large");
    }

    /* Bound from zlib docs: deflateBound + gzip header overhead */
    uLong bound = compressBound((uLong)in_len) + 18;
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) {
        free(in_buf);
        return compress_make_err("gzip_encode: out of memory");
    }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    int lvl = (level < 0) ? Z_DEFAULT_COMPRESSION : (int)level;
    /* windowBits = 15 + 16 → gzip format */
    if (deflateInit2(&zs, lvl, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(in_buf); free(out_buf);
        return compress_make_err("gzip_encode: deflateInit2 failed");
    }

    zs.next_in  = in_buf;
    zs.avail_in = (uInt)in_len;
    zs.next_out = out_buf;
    zs.avail_out = (uInt)bound;

    int rc = deflate(&zs, Z_FINISH);
    deflateEnd(&zs);
    free(in_buf);

    if (rc != Z_STREAM_END) {
        free(out_buf);
        return compress_make_err("gzip_encode: deflate failed");
    }

    size_t out_len = bound - zs.avail_out;
    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

void *march_gzip_decode(void *bytes_val) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("gzip_decode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("gzip_decode: input too large");
    }

    /* Start with 4× the input size, grow as needed */
    size_t out_size = in_len < 64 ? 256 : in_len * 4;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); return compress_make_err("gzip_decode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    /* windowBits = 15 + 32 → auto-detect gzip/zlib */
    if (inflateInit2(&zs, 15 + 32) != Z_OK) {
        free(in_buf); free(out_buf);
        return compress_make_err("gzip_decode: inflateInit2 failed");
    }

    zs.next_in  = in_buf;
    zs.avail_in = (uInt)in_len;
    zs.next_out = out_buf;
    zs.avail_out = (uInt)out_size;

    int rc;
    while (1) {
        rc = inflate(&zs, Z_NO_FLUSH);
        if (rc == Z_STREAM_END) break;
        if (rc != Z_OK && rc != Z_BUF_ERROR) {
            inflateEnd(&zs);
            free(in_buf); free(out_buf);
            return compress_make_err("gzip_decode: inflate failed");
        }
        if (zs.avail_out == 0) {
            if (out_size >= MAX_DECOMPRESS_SIZE) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                return compress_make_err("gzip_decode: output size limit exceeded");
            }
            size_t done = out_size;
            out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
            uint8_t *tmp = realloc(out_buf, out_size);
            if (!tmp) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                return compress_make_err("gzip_decode: out of memory");
            }
            out_buf = tmp;
            zs.next_out  = out_buf + done;
            zs.avail_out = (uInt)(out_size - done);
        }
    }

    size_t out_len = out_size - zs.avail_out;
    inflateEnd(&zs);
    free(in_buf);
    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

/* Raw deflate (no gzip header; windowBits = -15) */
void *march_deflate_encode(void *bytes_val) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("deflate_encode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("deflate_encode: input too large");
    }

    uLong bound = compressBound((uLong)in_len);
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) { free(in_buf); return compress_make_err("deflate_encode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (deflateInit2(&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(in_buf); free(out_buf);
        return compress_make_err("deflate_encode: deflateInit2 failed");
    }

    zs.next_in   = in_buf;
    zs.avail_in  = (uInt)in_len;
    zs.next_out  = out_buf;
    zs.avail_out = (uInt)bound;

    int rc = deflate(&zs, Z_FINISH);
    deflateEnd(&zs);
    free(in_buf);

    if (rc != Z_STREAM_END) {
        free(out_buf);
        return compress_make_err("deflate_encode: deflate failed");
    }

    size_t out_len = bound - zs.avail_out;
    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

void *march_deflate_decode(void *bytes_val) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("deflate_decode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("deflate_decode: input too large");
    }

    size_t out_size = in_len < 64 ? 256 : in_len * 4;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); return compress_make_err("deflate_decode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (inflateInit2(&zs, -15) != Z_OK) {
        free(in_buf); free(out_buf);
        return compress_make_err("deflate_decode: inflateInit2 failed");
    }

    zs.next_in   = in_buf;
    zs.avail_in  = (uInt)in_len;
    zs.next_out  = out_buf;
    zs.avail_out = (uInt)out_size;

    int rc;
    while (1) {
        rc = inflate(&zs, Z_NO_FLUSH);
        if (rc == Z_STREAM_END) break;
        if (rc != Z_OK && rc != Z_BUF_ERROR) {
            inflateEnd(&zs);
            free(in_buf); free(out_buf);
            return compress_make_err("deflate_decode: inflate failed");
        }
        if (zs.avail_out == 0) {
            if (out_size >= MAX_DECOMPRESS_SIZE) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                return compress_make_err("deflate_decode: output size limit exceeded");
            }
            size_t done = out_size;
            out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
            uint8_t *tmp = realloc(out_buf, out_size);
            if (!tmp) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                return compress_make_err("deflate_decode: out of memory");
            }
            out_buf = tmp;
            zs.next_out  = out_buf + done;
            zs.avail_out = (uInt)(out_size - done);
        }
    }

    size_t out_len = out_size - zs.avail_out;
    inflateEnd(&zs);
    free(in_buf);
    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

/* ── Zstd (optional) ─────────────────────────────────────────────────────── */

#ifdef MARCH_HAVE_ZSTD
#include <zstd.h>

void *march_zstd_encode(void *bytes_val, int64_t level) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("zstd_encode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("zstd_encode: input too large");
    }

    size_t bound = ZSTD_compressBound(in_len);
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) { free(in_buf); return compress_make_err("zstd_encode: out of memory"); }

    int lvl = (int)level;
    size_t out_len = ZSTD_compress(out_buf, bound, in_buf, in_len, lvl);
    free(in_buf);

    if (ZSTD_isError(out_len)) {
        free(out_buf);
        return compress_make_err(ZSTD_getErrorName(out_len));
    }

    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

void *march_zstd_decode(void *bytes_val) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("zstd_decode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("zstd_decode: input too large");
    }

    /* Try to get decompressed size hint from the frame */
    unsigned long long frame_size = ZSTD_getFrameContentSize(in_buf, in_len);
    size_t out_size;
    if (frame_size == ZSTD_CONTENTSIZE_UNKNOWN || frame_size == ZSTD_CONTENTSIZE_ERROR) {
        out_size = in_len * 4 < 4096 ? 4096 : in_len * 4;
        if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    } else {
        /* Reject frames that claim to expand beyond our limit */
        if (frame_size > (unsigned long long)MAX_DECOMPRESS_SIZE) {
            free(in_buf);
            return compress_make_err("zstd_decode: frame content size exceeds limit");
        }
        out_size = (size_t)frame_size;
    }

    uint8_t *out_buf = malloc(out_size > 0 ? out_size : 1);
    if (!out_buf) { free(in_buf); return compress_make_err("zstd_decode: out of memory"); }

    size_t out_len = ZSTD_decompress(out_buf, out_size, in_buf, in_len);
    free(in_buf);

    if (ZSTD_isError(out_len)) {
        free(out_buf);
        return compress_make_err(ZSTD_getErrorName(out_len));
    }

    void *result = compress_bytes_from_raw(out_buf, out_len);
    free(out_buf);
    return compress_make_ok(result);
}

#else /* !MARCH_HAVE_ZSTD */

void *march_zstd_encode(void *bytes_val, int64_t level) {
    (void)bytes_val; (void)level;
    return compress_make_err("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

void *march_zstd_decode(void *bytes_val) {
    (void)bytes_val;
    return compress_make_err("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

#endif /* MARCH_HAVE_ZSTD */

/* ── Brotli (optional) ───────────────────────────────────────────────────── */

#ifdef MARCH_HAVE_BROTLI
#include <brotli/encode.h>
#include <brotli/decode.h>

void *march_brotli_encode(void *bytes_val, int64_t mode, int64_t quality) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("brotli_encode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("brotli_encode: input too large");
    }

    size_t out_size = BrotliEncoderMaxCompressedSize(in_len);
    if (out_size == 0) out_size = in_len + 64;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); return compress_make_err("brotli_encode: out of memory"); }

    BrotliEncoderMode bmode;
    switch ((int)mode) {
        case 1:  bmode = BROTLI_MODE_TEXT;  break;
        case 2:  bmode = BROTLI_MODE_FONT;  break;
        default: bmode = BROTLI_MODE_GENERIC; break;
    }

    BROTLI_BOOL ok = BrotliEncoderCompress(
        (int)quality, BROTLI_DEFAULT_WINDOW, bmode,
        in_len, in_buf, &out_size, out_buf);
    free(in_buf);

    if (!ok) {
        free(out_buf);
        return compress_make_err("brotli_encode: compression failed");
    }

    void *result = compress_bytes_from_raw(out_buf, out_size);
    free(out_buf);
    return compress_make_ok(result);
}

void *march_brotli_decode(void *bytes_val) {
    size_t in_len;
    uint8_t *in_buf = compress_bytes_to_raw(bytes_val, &in_len);
    if (!in_buf) return compress_make_err("brotli_decode: out of memory");
    if (in_len > MAX_INPUT_SIZE) {
        free(in_buf);
        return compress_make_err("brotli_decode: input too large");
    }

    size_t out_size = in_len < 64 ? 1024 : in_len * 8;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); return compress_make_err("brotli_decode: out of memory"); }

    BrotliDecoderResult res;
    while (1) {
        size_t decoded = out_size;
        res = BrotliDecoderDecompress(in_len, in_buf, &decoded, out_buf);
        if (res == BROTLI_DECODER_RESULT_SUCCESS) {
            free(in_buf);
            void *result = compress_bytes_from_raw(out_buf, decoded);
            free(out_buf);
            return compress_make_ok(result);
        }
        if (res != BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT) break;
        if (out_size >= MAX_DECOMPRESS_SIZE) {
            free(in_buf); free(out_buf);
            return compress_make_err("brotli_decode: output size limit exceeded");
        }
        out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
        uint8_t *tmp = realloc(out_buf, out_size);
        if (!tmp) {
            free(in_buf); free(out_buf);
            return compress_make_err("brotli_decode: out of memory");
        }
        out_buf = tmp;
    }

    free(in_buf); free(out_buf);
    return compress_make_err("brotli_decode: decompression failed");
}

#else /* !MARCH_HAVE_BROTLI */

void *march_brotli_encode(void *bytes_val, int64_t mode, int64_t quality) {
    (void)bytes_val; (void)mode; (void)quality;
    return compress_make_err("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

void *march_brotli_decode(void *bytes_val) {
    (void)bytes_val;
    return compress_make_err("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

#endif /* MARCH_HAVE_BROTLI */
