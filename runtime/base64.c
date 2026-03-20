/* runtime/base64.c — minimal Base64 encoder for WebSocket handshake.
 * Only encoding is needed (for Sec-WebSocket-Accept). No decoding. */
#include <stdint.h>
#include <stddef.h>

static const char b64chars[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

/* Encode `len` bytes from `in` into `out` (null-terminated).
 * `out_sz` must be >= ceil(len/3)*4 + 1.
 * Returns number of base64 chars written (excluding null terminator),
 * or -1 if the output buffer is too small. */
int base64_encode(const uint8_t *in, size_t len, char *out, size_t out_sz) {
    size_t i = 0, j = 0;

    /* Encode full 3-byte groups */
    while (len - i >= 3) {
        uint32_t v = ((uint32_t)in[i] << 16) |
                     ((uint32_t)in[i+1] << 8) |
                     (uint32_t)in[i+2];
        if (j + 4 >= out_sz) return -1;
        out[j++] = b64chars[(v >> 18) & 0x3F];
        out[j++] = b64chars[(v >> 12) & 0x3F];
        out[j++] = b64chars[(v >>  6) & 0x3F];
        out[j++] = b64chars[ v        & 0x3F];
        i += 3;
    }

    /* Handle remaining 1 or 2 bytes with padding */
    if (len - i == 1) {
        /* One remaining byte: two chars + "==" */
        uint32_t v = (uint32_t)in[i];
        if (j + 4 >= out_sz) return -1;
        out[j++] = b64chars[(v >> 2) & 0x3F];
        out[j++] = b64chars[(v << 4) & 0x3F];
        out[j++] = '=';
        out[j++] = '=';
    } else if (len - i == 2) {
        /* Two remaining bytes: three chars + "=" */
        uint32_t v = ((uint32_t)in[i] << 8) | (uint32_t)in[i+1];
        if (j + 4 >= out_sz) return -1;
        out[j++] = b64chars[(v >> 10) & 0x3F];
        out[j++] = b64chars[(v >>  4) & 0x3F];
        out[j++] = b64chars[(v <<  2) & 0x3F];
        out[j++] = '=';
    }

    out[j] = '\0';
    return (int)j;
}
