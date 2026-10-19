/* march_compress_zstd.c -- the zstd shim for the March native compiler
 * (Compress.Zstd).  Needs libzstd.
 *
 * The driver compiles this file only when libzstd resolves, and refuses a program
 * that reaches Compress.Zstd when it does not, naming the package
 * (apk add zstd-dev | apt install libzstd-dev | brew install zstd): the binary's behaviour never depends on the build host
 * (specs/2026-09-23-static-compile-output-design.md, decision D3).  It is an
 * archive member, so a program that never calls it neither links it nor
 * records libzstd.
 *
 * MARCH_ZSTD_STUB: the REPL/JIT runtime .so (bin/toolchain.ml), which links every
 * member and has no program to refuse, builds the not-available stubs below
 * when libzstd is missing.  The driver never defines it. */

#include "march_compress_common.h"

#ifndef MARCH_ZSTD_STUB
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

#else /* MARCH_ZSTD_STUB */

void *march_zstd_encode(void *bytes_val, int64_t level) {
    (void)bytes_val; (void)level;
    return compress_make_err("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

void *march_zstd_decode(void *bytes_val) {
    (void)bytes_val;
    return compress_make_err("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

#endif /* MARCH_ZSTD_STUB */
