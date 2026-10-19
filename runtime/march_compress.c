/* march_compress.c -- the gzip and deflate shims for the March native
 * compiler (Compress.Gzip, Compress.Deflate), over zlib (-lz, a system library
 * on macOS and Linux).  Each function receives/returns March heap values
 * (Bytes and Result(Bytes, String)) through march_compress_common.h.
 *
 * zstd and brotli live in march_compress_zstd.c and march_compress_brotli.c,
 * one archive member per codec, so a program links only the codecs it calls
 * (specs/2026-09-23-static-compile-output-design.md, Stage 3).
 */

#include "march_compress_common.h"

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
        /* Z_BUF_ERROR with input exhausted but no Z_STREAM_END: truncated/invalid */
        if (rc == Z_BUF_ERROR && zs.avail_in == 0 && zs.avail_out > 0) {
            inflateEnd(&zs);
            free(in_buf); free(out_buf);
            return compress_make_err("gzip_decode: unexpected end of compressed data");
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
        /* Z_BUF_ERROR with input exhausted but no Z_STREAM_END: truncated/invalid */
        if (rc == Z_BUF_ERROR && zs.avail_in == 0 && zs.avail_out > 0) {
            inflateEnd(&zs);
            free(in_buf); free(out_buf);
            return compress_make_err("deflate_decode: unexpected end of compressed data");
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
