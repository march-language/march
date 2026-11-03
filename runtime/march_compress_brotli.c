/* march_compress_brotli.c -- the brotli shim for the March native compiler
 * (Compress.Brotli).  Needs libbrotlienc/libbrotlidec.
 *
 * The driver compiles this file only when libbrotlienc/libbrotlidec resolves, and refuses a program
 * that reaches Compress.Brotli when it does not, naming the package
 * (apk add brotli-dev | apt install libbrotli-dev | brew install brotli): the binary's behaviour never depends on the build host
 * (specs/2026-09-23-static-compile-output-design.md, decision D3).  It is an
 * archive member, so a program that never calls it neither links it nor
 * records libbrotlienc/libbrotlidec.
 *
 * MARCH_BROTLI_STUB: the REPL/JIT runtime .so (bin/toolchain.ml), which links every
 * member and has no program to refuse, builds the not-available stubs below
 * when libbrotlienc/libbrotlidec is missing.  The driver never defines it. */

#include "march_compress_common.h"

#ifndef MARCH_BROTLI_STUB
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

#else /* MARCH_BROTLI_STUB */

void *march_brotli_encode(void *bytes_val, int64_t mode, int64_t quality) {
    (void)bytes_val; (void)mode; (void)quality;
    return compress_make_err("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

void *march_brotli_decode(void *bytes_val) {
    (void)bytes_val;
    return compress_make_err("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

#endif /* MARCH_BROTLI_STUB */
