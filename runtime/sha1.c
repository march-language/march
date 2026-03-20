/* runtime/sha1.c — minimal RFC 3174 SHA-1 for WebSocket handshake.
 * No dynamic allocation; uses alloca for the padded message buffer.
 * Not intended for general cryptographic use — WebSocket handshake only. */
#include <stdint.h>
#include <string.h>
#include <alloca.h>

static uint32_t sha1_rotate(uint32_t x, int n) {
    return (x << n) | (x >> (32 - n));
}

void sha1(const uint8_t *msg, size_t len, uint8_t out[20]) {
    uint32_t h0 = 0x67452301u, h1 = 0xEFCDAB89u, h2 = 0x98BADCFEu,
             h3 = 0x10325476u, h4 = 0xC3D2E1F0u;

    /* Pre-process: pad message to a multiple of 512 bits.
     * Append bit '1' (0x80), then zeros, then 64-bit big-endian bit-length. */
    uint64_t ml = (uint64_t)len * 8;
    size_t padded_len = ((len + 8) / 64 + 1) * 64;
    uint8_t *padded = (uint8_t *)alloca(padded_len);
    memset(padded, 0, padded_len);
    memcpy(padded, msg, len);
    padded[len] = 0x80;
    /* Append original bit-length as 64-bit big-endian */
    for (int i = 0; i < 8; i++)
        padded[padded_len - 8 + i] = (uint8_t)((ml >> (56 - 8 * i)) & 0xFF);

    /* Process each 512-bit (64-byte) block */
    for (size_t i = 0; i < padded_len; i += 64) {
        uint32_t w[80];
        /* Load 16 big-endian words */
        for (int j = 0; j < 16; j++)
            w[j] = ((uint32_t)padded[i + j*4    ] << 24) |
                   ((uint32_t)padded[i + j*4 + 1] << 16) |
                   ((uint32_t)padded[i + j*4 + 2] <<  8) |
                   ((uint32_t)padded[i + j*4 + 3]);
        /* Extend to 80 words */
        for (int j = 16; j < 80; j++)
            w[j] = sha1_rotate(w[j-3] ^ w[j-8] ^ w[j-14] ^ w[j-16], 1);

        uint32_t a = h0, b = h1, c = h2, d = h3, e = h4;
        for (int j = 0; j < 80; j++) {
            uint32_t f, k;
            if (j < 20) {
                f = (b & c) | (~b & d);
                k = 0x5A827999u;
            } else if (j < 40) {
                f = b ^ c ^ d;
                k = 0x6ED9EBA1u;
            } else if (j < 60) {
                f = (b & c) | (b & d) | (c & d);
                k = 0x8F1BBCDCu;
            } else {
                f = b ^ c ^ d;
                k = 0xCA62C1D6u;
            }
            uint32_t temp = sha1_rotate(a, 5) + f + e + k + w[j];
            e = d;
            d = c;
            c = sha1_rotate(b, 30);
            b = a;
            a = temp;
        }
        h0 += a; h1 += b; h2 += c; h3 += d; h4 += e;
    }

    /* Write 20-byte output big-endian */
    uint32_t hash[5] = {h0, h1, h2, h3, h4};
    for (int i = 0; i < 5; i++)
        for (int j = 0; j < 4; j++)
            out[i*4 + j] = (uint8_t)((hash[i] >> (24 - 8*j)) & 0xFF);
}
