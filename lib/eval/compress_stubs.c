/* compress_stubs.c — OCaml C stubs for gzip/deflate/zstd/brotli.
 *
 * Each stub takes OCaml string(s), performs compression/decompression, and
 * either returns an OCaml string (the result bytes) or raises Failure(msg)
 * on error.  eval.ml wraps the return into Ok(Bytes) / Err(String).
 *
 * Compiled as part of march_eval via foreign_stubs in lib/eval/dune.
 *
 * Flags in dune set MARCH_HAVE_ZSTD and MARCH_HAVE_BROTLI when the optional
 * libraries are present.  Without them the stubs raise "not available".
 */

#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <zlib.h>

/* Mirror the limits from march_compress.c. Input cap ensures
 * compressBound(in_len)+overhead fits in a 32-bit uInt.
 * Output cap is checked in grow loops before every realloc. */
#define MAX_INPUT_SIZE      ((size_t)(256 * 1024 * 1024))
#define MAX_DECOMPRESS_SIZE ((size_t)(256 * 1024 * 1024))

/* ── Gzip ────────────────────────────────────────────────────────────────── */

/* caml_march_gzip_encode(input: string, level: int) : string
 * level = -1 means Z_DEFAULT_COMPRESSION */
CAMLprim value caml_march_gzip_encode(value input, value level_val) {
    CAMLparam2(input, level_val);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);
    int lvl = Int_val(level_val);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("gzip_encode: input too large");

    /* Copy input before any OCaml allocation so GC cannot move String_val(input). */
    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("gzip_encode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    uLong bound = compressBound((uLong)in_len) + 32;
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) { free(in_buf); caml_failwith("gzip_encode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    /* windowBits 15+16 → gzip format */
    if (deflateInit2(&zs, lvl, Z_DEFLATED, 15 + 16, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(in_buf); free(out_buf);
        caml_failwith("gzip_encode: deflateInit2 failed");
    }

    zs.next_in   = (Bytef *)in_buf;
    zs.avail_in  = (uInt)in_len;
    zs.next_out  = out_buf;
    zs.avail_out = (uInt)bound;

    int rc = deflate(&zs, Z_FINISH);
    deflateEnd(&zs);
    free(in_buf);

    if (rc != Z_STREAM_END) {
        free(out_buf);
        caml_failwith("gzip_encode: deflate failed");
    }

    size_t out_len = bound - zs.avail_out;
    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

/* caml_march_gzip_decode(input: string) : string */
CAMLprim value caml_march_gzip_decode(value input) {
    CAMLparam1(input);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("gzip_decode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("gzip_decode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    size_t out_size = in_len < 64 ? 256 : in_len * 4;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); caml_failwith("gzip_decode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    /* windowBits 15+32 → auto-detect gzip/zlib */
    if (inflateInit2(&zs, 15 + 32) != Z_OK) {
        free(in_buf); free(out_buf);
        caml_failwith("gzip_decode: inflateInit2 failed");
    }

    zs.next_in   = (Bytef *)in_buf;
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
            caml_failwith("gzip_decode: inflate failed (invalid data)");
        }
        if (zs.avail_out == 0) {
            if (out_size >= MAX_DECOMPRESS_SIZE) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                caml_failwith("gzip_decode: output size limit exceeded");
            }
            size_t done = out_size;
            out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
            uint8_t *tmp = realloc(out_buf, out_size);
            if (!tmp) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                caml_failwith("gzip_decode: out of memory");
            }
            out_buf = tmp;
            zs.next_out  = out_buf + done;
            zs.avail_out = (uInt)(out_size - done);
        }
    }

    size_t out_len = out_size - zs.avail_out;
    inflateEnd(&zs);
    free(in_buf);

    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

/* ── Deflate ─────────────────────────────────────────────────────────────── */

CAMLprim value caml_march_deflate_encode(value input) {
    CAMLparam1(input);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("deflate_encode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("deflate_encode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    uLong bound = compressBound((uLong)in_len);
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) { free(in_buf); caml_failwith("deflate_encode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (deflateInit2(&zs, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -15, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(in_buf); free(out_buf);
        caml_failwith("deflate_encode: deflateInit2 failed");
    }

    zs.next_in   = (Bytef *)in_buf;
    zs.avail_in  = (uInt)in_len;
    zs.next_out  = out_buf;
    zs.avail_out = (uInt)bound;

    int rc = deflate(&zs, Z_FINISH);
    deflateEnd(&zs);
    free(in_buf);

    if (rc != Z_STREAM_END) {
        free(out_buf);
        caml_failwith("deflate_encode: deflate failed");
    }

    size_t out_len = bound - zs.avail_out;
    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

CAMLprim value caml_march_deflate_decode(value input) {
    CAMLparam1(input);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("deflate_decode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("deflate_decode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    size_t out_size = in_len < 64 ? 256 : in_len * 4;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); caml_failwith("deflate_decode: out of memory"); }

    z_stream zs;
    memset(&zs, 0, sizeof(zs));
    if (inflateInit2(&zs, -15) != Z_OK) {
        free(in_buf); free(out_buf);
        caml_failwith("deflate_decode: inflateInit2 failed");
    }

    zs.next_in   = (Bytef *)in_buf;
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
            caml_failwith("deflate_decode: inflate failed (invalid data)");
        }
        if (zs.avail_out == 0) {
            if (out_size >= MAX_DECOMPRESS_SIZE) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                caml_failwith("deflate_decode: output size limit exceeded");
            }
            size_t done = out_size;
            out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
            uint8_t *tmp = realloc(out_buf, out_size);
            if (!tmp) {
                inflateEnd(&zs);
                free(in_buf); free(out_buf);
                caml_failwith("deflate_decode: out of memory");
            }
            out_buf = tmp;
            zs.next_out  = out_buf + done;
            zs.avail_out = (uInt)(out_size - done);
        }
    }

    size_t out_len = out_size - zs.avail_out;
    inflateEnd(&zs);
    free(in_buf);

    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

/* ── Zstd (optional) ─────────────────────────────────────────────────────── */

#ifdef MARCH_HAVE_ZSTD
#include <zstd.h>

CAMLprim value caml_march_zstd_encode(value input, value level_val) {
    CAMLparam2(input, level_val);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);
    int lvl = Int_val(level_val);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("zstd_encode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("zstd_encode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    size_t bound = ZSTD_compressBound(in_len);
    uint8_t *out_buf = malloc(bound);
    if (!out_buf) { free(in_buf); caml_failwith("zstd_encode: out of memory"); }

    size_t out_len = ZSTD_compress(out_buf, bound, in_buf, in_len, lvl);
    free(in_buf);
    if (ZSTD_isError(out_len)) {
        const char *emsg = ZSTD_getErrorName(out_len);
        free(out_buf);
        caml_failwith(emsg);
    }

    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

CAMLprim value caml_march_zstd_decode(value input) {
    CAMLparam1(input);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("zstd_decode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("zstd_decode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    unsigned long long frame_size = ZSTD_getFrameContentSize(in_buf, in_len);
    size_t out_size;
    if (frame_size == ZSTD_CONTENTSIZE_UNKNOWN || frame_size == ZSTD_CONTENTSIZE_ERROR) {
        out_size = in_len * 4 < 4096 ? 4096 : in_len * 4;
        if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    } else {
        if (frame_size > (unsigned long long)MAX_DECOMPRESS_SIZE) {
            free(in_buf);
            caml_failwith("zstd_decode: frame content size exceeds limit");
        }
        out_size = (size_t)frame_size;
    }

    uint8_t *out_buf = malloc(out_size > 0 ? out_size : 1);
    if (!out_buf) { free(in_buf); caml_failwith("zstd_decode: out of memory"); }

    size_t out_len = ZSTD_decompress(out_buf, out_size, in_buf, in_len);
    free(in_buf);
    if (ZSTD_isError(out_len)) {
        const char *emsg = ZSTD_getErrorName(out_len);
        free(out_buf);
        caml_failwith(emsg);
    }

    result = caml_alloc_string(out_len);
    memcpy(Bytes_val(result), out_buf, out_len);
    free(out_buf);
    CAMLreturn(result);
}

#else /* !MARCH_HAVE_ZSTD */

CAMLprim value caml_march_zstd_encode(value input, value level_val) {
    CAMLparam2(input, level_val);
    (void)input; (void)level_val;
    caml_failwith("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

CAMLprim value caml_march_zstd_decode(value input) {
    CAMLparam1(input);
    (void)input;
    caml_failwith("Compress.Zstd: libzstd not available — install libzstd and rebuild");
}

#endif /* MARCH_HAVE_ZSTD */

/* ── Brotli (optional) ───────────────────────────────────────────────────── */

#ifdef MARCH_HAVE_BROTLI
#include <brotli/encode.h>
#include <brotli/decode.h>

CAMLprim value caml_march_brotli_encode(value input, value mode_val, value quality_val) {
    CAMLparam3(input, mode_val, quality_val);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);
    int mode    = Int_val(mode_val);
    int quality = Int_val(quality_val);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("brotli_encode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("brotli_encode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    size_t out_size = BrotliEncoderMaxCompressedSize(in_len);
    if (out_size == 0) out_size = in_len + 64;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); caml_failwith("brotli_encode: out of memory"); }

    BrotliEncoderMode bmode;
    switch (mode) {
        case 1:  bmode = BROTLI_MODE_TEXT;  break;
        case 2:  bmode = BROTLI_MODE_FONT;  break;
        default: bmode = BROTLI_MODE_GENERIC; break;
    }

    BROTLI_BOOL ok = BrotliEncoderCompress(
        quality, BROTLI_DEFAULT_WINDOW, bmode,
        in_len, in_buf, &out_size, out_buf);
    free(in_buf);

    if (!ok) {
        free(out_buf);
        caml_failwith("brotli_encode: compression failed");
    }

    result = caml_alloc_string(out_size);
    memcpy(Bytes_val(result), out_buf, out_size);
    free(out_buf);
    CAMLreturn(result);
}

CAMLprim value caml_march_brotli_decode(value input) {
    CAMLparam1(input);
    CAMLlocal1(result);

    mlsize_t in_len = caml_string_length(input);

    if (in_len > MAX_INPUT_SIZE)
        caml_failwith("brotli_decode: input too large");

    uint8_t *in_buf = malloc(in_len > 0 ? in_len : 1);
    if (!in_buf) caml_failwith("brotli_decode: out of memory");
    memcpy(in_buf, String_val(input), in_len);

    size_t out_size = in_len < 64 ? 1024 : in_len * 8;
    if (out_size > MAX_DECOMPRESS_SIZE) out_size = MAX_DECOMPRESS_SIZE;
    uint8_t *out_buf = malloc(out_size);
    if (!out_buf) { free(in_buf); caml_failwith("brotli_decode: out of memory"); }

    BrotliDecoderResult res;
    while (1) {
        size_t decoded = out_size;
        res = BrotliDecoderDecompress(in_len, in_buf, &decoded, out_buf);
        if (res == BROTLI_DECODER_RESULT_SUCCESS) {
            free(in_buf);
            result = caml_alloc_string(decoded);
            memcpy(Bytes_val(result), out_buf, decoded);
            free(out_buf);
            CAMLreturn(result);
        }
        if (res != BROTLI_DECODER_RESULT_NEEDS_MORE_OUTPUT) break;
        if (out_size >= MAX_DECOMPRESS_SIZE) {
            free(in_buf); free(out_buf);
            caml_failwith("brotli_decode: output size limit exceeded");
        }
        out_size = out_size * 2 > MAX_DECOMPRESS_SIZE ? MAX_DECOMPRESS_SIZE : out_size * 2;
        uint8_t *tmp = realloc(out_buf, out_size);
        if (!tmp) {
            free(in_buf); free(out_buf);
            caml_failwith("brotli_decode: out of memory");
        }
        out_buf = tmp;
    }

    free(in_buf); free(out_buf);
    caml_failwith("brotli_decode: decompression failed");
}

#else /* !MARCH_HAVE_BROTLI */

CAMLprim value caml_march_brotli_encode(value input, value mode_val, value quality_val) {
    CAMLparam3(input, mode_val, quality_val);
    (void)input; (void)mode_val; (void)quality_val;
    caml_failwith("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

CAMLprim value caml_march_brotli_decode(value input) {
    CAMLparam1(input);
    (void)input;
    caml_failwith("Compress.Brotli: libbrotli not available — install libbrotli and rebuild");
}

#endif /* MARCH_HAVE_BROTLI */
