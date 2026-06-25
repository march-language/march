/* tweetnacl.c — ed25519 implementation (public domain, TweetNaCl-derived).
 *
 * Only ed25519 is included; SHA-512 is implemented inline.
 * Based on the public domain TweetNaCl by Bernstein, van Gastel, Janssen, Lange,
 * Peters, and Schwabe.  See https://tweetnacl.cr.yp.to/.
 */
#include "tweetnacl.h"
#include <stdio.h>
#include <string.h>
#include <stdint.h>

/* ── SHA-512 ──────────────────────────────────────────────────────────────── */

static const uint64_t SHA512_K[80] = {
    0x428a2f98d728ae22ULL,0x7137449123ef65cdULL,0xb5c0fbcfec4d3b2fULL,0xe9b5dba58189dbbcULL,
    0x3956c25bf348b538ULL,0x59f111f1b605d019ULL,0x923f82a4af194f9bULL,0xab1c5ed5da6d8118ULL,
    0xd807aa98a3030242ULL,0x12835b0145706fbeULL,0x243185be4ee4b28cULL,0x550c7dc3d5ffb4e2ULL,
    0x72be5d74f27b896fULL,0x80deb1fe3b1696b1ULL,0x9bdc06a725c71235ULL,0xc19bf174cf692694ULL,
    0xe49b69c19ef14ad2ULL,0xefbe4786384f25e3ULL,0x0fc19dc68b8cd5b5ULL,0x240ca1cc77ac9c65ULL,
    0x2de92c6f592b0275ULL,0x4a7484aa6ea6e483ULL,0x5cb0a9dcbd41fbd4ULL,0x76f988da831153b5ULL,
    0x983e5152ee66dfabULL,0xa831c66d2db43210ULL,0xb00327c898fb213fULL,0xbf597fc7beef0ee4ULL,
    0xc6e00bf33da88fc2ULL,0xd5a79147930aa725ULL,0x06ca6351e003826fULL,0x142929670a0e6e70ULL,
    0x27b70a8546d22ffcULL,0x2e1b21385c26c926ULL,0x4d2c6dfc5ac42aedULL,0x53380d139d95b3dfULL,
    0x650a73548baf63deULL,0x766a0abb3c77b2a8ULL,0x81c2c92e47edaee6ULL,0x92722c851482353bULL,
    0xa2bfe8a14cf10364ULL,0xa81a664bbc423001ULL,0xc24b8b70d0f89791ULL,0xc76c51a30654be30ULL,
    0xd192e819d6ef5218ULL,0xd69906245565a910ULL,0xf40e35855771202aULL,0x106aa07032bbd1b8ULL,
    0x19a4c116b8d2d0c8ULL,0x1e376c085141ab53ULL,0x2748774cdf8eeb99ULL,0x34b0bcb5e19b48a8ULL,
    0x391c0cb3c5c95a63ULL,0x4ed8aa4ae3418acbULL,0x5b9cca4f7763e373ULL,0x682e6ff3d6b2b8a3ULL,
    0x748f82ee5defb2fcULL,0x78a5636f43172f60ULL,0x84c87814a1f0ab72ULL,0x8cc702081a6439ecULL,
    0x90befffa23631e28ULL,0xa4506cebde82bde9ULL,0xbef9a3f7b2c67915ULL,0xc67178f2e372532bULL,
    0xca273eceea26619cULL,0xd186b8c721c0c207ULL,0xeada7dd6cde0eb1eULL,0xf57d4f7fee6ed178ULL,
    0x06f067aa72176fbaULL,0x0a637dc5a2c898a6ULL,0x113f9804bef90daeULL,0x1b710b35131c471bULL,
    0x28db77f523047d84ULL,0x32caab7b40c72493ULL,0x3c9ebe0a15c9bebcULL,0x431d67c49c100d4cULL,
    0x4cc5d4becb3e42b6ULL,0x597f299cfc657e2aULL,0x5fcb6fab3ad6faecULL,0x6c44198c4a475817ULL
};

static uint64_t ror64(uint64_t x, int n) { return (x >> n) | (x << (64 - n)); }

typedef struct {
    uint64_t h[8];
    uint8_t  buf[128];
    uint64_t total_len;
    uint32_t buflen;
} sha512_ctx_t;

static void sha512_init(sha512_ctx_t *ctx) {
    ctx->h[0]=0x6a09e667f3bcc908ULL; ctx->h[1]=0xbb67ae8584caa73bULL;
    ctx->h[2]=0x3c6ef372fe94f82bULL; ctx->h[3]=0xa54ff53a5f1d36f1ULL;
    ctx->h[4]=0x510e527fade682d1ULL; ctx->h[5]=0x9b05688c2b3e6c1fULL;
    ctx->h[6]=0x1f83d9abfb41bd6bULL; ctx->h[7]=0x5be0cd19137e2179ULL;
    ctx->total_len = 0; ctx->buflen = 0;
}

static void sha512_block(sha512_ctx_t *ctx) {
    uint64_t w[80], a,b,c,d,e,f,g,h,t1,t2;
    for (int i = 0; i < 16; i++) {
        w[i] = 0;
        for (int j = 0; j < 8; j++) w[i] = (w[i] << 8) | ctx->buf[i*8+j];
    }
    for (int i = 16; i < 80; i++)
        w[i] = (ror64(w[i-2],19)^ror64(w[i-2],61)^(w[i-2]>>6))
             + w[i-7]
             + (ror64(w[i-15],1)^ror64(w[i-15],8)^(w[i-15]>>7))
             + w[i-16];
    a=ctx->h[0]; b=ctx->h[1]; c=ctx->h[2]; d=ctx->h[3];
    e=ctx->h[4]; f=ctx->h[5]; g=ctx->h[6]; h=ctx->h[7];
    for (int i = 0; i < 80; i++) {
        t1 = h + (ror64(e,14)^ror64(e,18)^ror64(e,41)) + ((e&f)^(~e&g)) + SHA512_K[i] + w[i];
        t2 = (ror64(a,28)^ror64(a,34)^ror64(a,39)) + ((a&b)^(a&c)^(b&c));
        h=g; g=f; f=e; e=d+t1; d=c; c=b; b=a; a=t1+t2;
    }
    ctx->h[0]+=a; ctx->h[1]+=b; ctx->h[2]+=c; ctx->h[3]+=d;
    ctx->h[4]+=e; ctx->h[5]+=f; ctx->h[6]+=g; ctx->h[7]+=h;
}

static void sha512_update(sha512_ctx_t *ctx, const uint8_t *data, size_t len) {
    ctx->total_len += len;
    while (len > 0) {
        uint32_t n = 128 - ctx->buflen;
        if (n > (uint32_t)len) n = (uint32_t)len;
        memcpy(ctx->buf + ctx->buflen, data, n);
        ctx->buflen += n; data += n; len -= n;
        if (ctx->buflen == 128) { sha512_block(ctx); ctx->buflen = 0; }
    }
}

static void sha512_final(sha512_ctx_t *ctx, uint8_t out[64]) {
    uint64_t bits = ctx->total_len * 8;
    uint8_t pad = 0x80;
    sha512_update(ctx, &pad, 1);
    while (ctx->buflen != 112) { uint8_t z = 0; sha512_update(ctx, &z, 1); }
    uint8_t lb[16] = {0};
    for (int i = 15; bits; i--, bits >>= 8) lb[i] = bits & 0xff;
    sha512_update(ctx, lb, 16);
    for (int i = 0; i < 8; i++)
        for (int j = 0; j < 8; j++)
            out[i*8+j] = (uint8_t)(ctx->h[i] >> (56 - 8*j));
}

static void sha512_hash(const uint8_t *m, size_t mlen, uint8_t out[64]) {
    sha512_ctx_t ctx; sha512_init(&ctx); sha512_update(&ctx, m, mlen); sha512_final(&ctx, out);
}

/* Multi-part SHA-512 for signing (avoids copying large messages) */
static void sha512_3parts(const uint8_t *m1, size_t l1,
                           const uint8_t *m2, size_t l2,
                           const uint8_t *m3, size_t l3,
                           uint8_t out[64]) {
    sha512_ctx_t ctx; sha512_init(&ctx);
    sha512_update(&ctx, m1, l1);
    sha512_update(&ctx, m2, l2);
    sha512_update(&ctx, m3, l3);
    sha512_final(&ctx, out);
}

static void sha512_2parts(const uint8_t *m1, size_t l1,
                           const uint8_t *m2, size_t l2,
                           uint8_t out[64]) {
    sha512_3parts(m1, l1, m2, l2, NULL, 0, out);
}

/* ── GF(2^255-19) arithmetic in radix 2^16 ─────────────────────────────── */

typedef long long gf[16];

/* Named constants */
static const gf GF_D = {
    0x78a3,0x1359,0x4dca,0x75eb,0xd8ab,0x4141,0x0a4d,0x0070,
    0xe898,0x7779,0x4079,0x8cc7,0xfe73,0x2b6f,0x6cee,0x5203
};
static const gf GF_D2 = {
    0xf159,0x26b2,0x9b94,0xebd6,0xb156,0x8283,0x149a,0x00e0,
    0xd130,0xeef3,0x80f2,0x198e,0xfce7,0x56df,0xd9dc,0x2406
};
static const gf GF_X = {
    0xd51a,0x8f25,0x2d60,0xc956,0xa7b2,0x9525,0xc760,0x692c,
    0xdc5c,0xfdd6,0xe231,0xc0a4,0x53fe,0xcd6e,0x36d3,0x2169
};
static const gf GF_Y = {
    0x6658,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,
    0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666,0x6666
};
static const gf GF_I = {
    0xa0b0,0x4a0e,0x1b27,0xc4ee,0xe478,0xad2f,0x1806,0x2f43,
    0xd7a7,0x3dfb,0x0099,0x2b4d,0xdf0b,0x4fc1,0x2480,0x2b83
};

static void gf_0(gf o)              { for(int i=0;i<16;i++) o[i]=0; }
static void gf_1(gf o)              { gf_0(o); o[0]=1; }
static void gf_cpy(gf o, const gf a){ for(int i=0;i<16;i++) o[i]=a[i]; }
static void gf_add(gf o, const gf a, const gf b){ for(int i=0;i<16;i++) o[i]=a[i]+b[i]; }
static void gf_sub(gf o, const gf a, const gf b){ for(int i=0;i<16;i++) o[i]=a[i]-b[i]; }

static void gf_reduce(gf o) {
    long long c;
    for (int i = 0; i < 16; i++) {
        o[i] += (1LL<<16);
        c = o[i] >> 16;
        /* Subtract 1 from carry to cancel the 2^16 bias we added above.
         * Original TweetNaCl car25519 uses (c-1) not c. */
        if (i < 15) o[i+1] += c - 1;
        else        o[0]    += 38*(c - 1);
        o[i] -= c * (1LL<<16);
    }
}

static void gf_mul(gf o, const gf a, const gf b) {
    long long t[31] = {0};
    for (int i = 0; i < 16; i++)
        for (int j = 0; j < 16; j++)
            t[i+j] += a[i] * b[j];
    for (int i = 16; i < 31; i++) t[i-16] += 38 * t[i];
    for (int i = 0; i < 16; i++) o[i] = t[i];
    gf_reduce(o);
    gf_reduce(o);
}

static void gf_sqr(gf o, const gf a) { gf_mul(o, a, a); }

static void gf_cswap(gf p, gf q, int b) {
    long long c = ~((long long)b - 1);
    for (int i = 0; i < 16; i++) {
        long long t = c & (p[i] ^ q[i]);
        p[i] ^= t; q[i] ^= t;
    }
}

static void gf_pack(uint8_t o[32], const gf n) {
    gf m, t;
    gf_cpy(t, n);
    gf_reduce(t); gf_reduce(t); gf_reduce(t);
    for (int j = 0; j < 2; j++) {
        m[0] = t[0] - 0xffed;
        for (int i = 1; i < 15; i++) {
            m[i] = t[i] - 0xffff - ((m[i-1] >> 16) & 1);
            m[i-1] &= 0xffff;
        }
        m[15] = t[15] - 0x7fff - ((m[14] >> 16) & 1);
        int bv = (m[15] >> 16) & 1;
        m[14] &= 0xffff;
        gf_cswap(t, m, 1 - bv);
    }
    for (int i = 0; i < 16; i++) {
        o[2*i]   = (uint8_t)(t[i] & 0xff);
        o[2*i+1] = (uint8_t)(t[i] >> 8);
    }
}

static void gf_unpack(gf o, const uint8_t n[32]) {
    for (int i = 0; i < 16; i++)
        o[i] = (long long)(n[2*i] & 0xff) | ((long long)(n[2*i+1]) << 8);
    o[15] &= 0x7fff;
}

static uint8_t gf_par(const gf a) {
    uint8_t d[32]; gf_pack(d, a); return d[0] & 1;
}

static void gf_inv(gf o, const gf a) {
    gf c; gf_cpy(c, a);
    for (int i = 253; i >= 0; i--) {
        gf_sqr(c, c);
        if (i != 2 && i != 4) gf_mul(c, c, a);
    }
    gf_cpy(o, c);
}

static void gf_pow2523(gf o, const gf a) {
    gf c; gf_cpy(c, a);
    for (int i = 250; i >= 0; i--) {
        gf_sqr(c, c);
        if (i != 1) gf_mul(c, c, a);
    }
    gf_cpy(o, c);
}

/* ── Ed25519 extended Edwards point operations ─────────────────────────── */

/* Extended twisted Edwards: (X:Y:Z:T) with y=Y/Z, x=X/Z, T=X*Y/Z */

static void ed_add(gf p[4], const gf q[4]) {
    gf a, b, c, d, e, f, g, h, t;
    gf_sub(a, p[1], p[0]);
    gf_sub(t, q[1], q[0]);
    gf_mul(a, a, t);
    gf_add(b, p[0], p[1]);
    gf_add(t, q[0], q[1]);
    gf_mul(b, b, t);
    gf_mul(c, p[3], q[3]);
    gf_mul(c, c, GF_D2);
    gf_mul(d, p[2], q[2]);
    gf_add(d, d, d);
    gf_sub(e, b, a);
    gf_sub(f, d, c);
    gf_add(g, d, c);
    gf_add(h, b, a);
    gf_mul(p[0], e, f);
    gf_mul(p[1], h, g);
    gf_mul(p[2], g, f);
    gf_mul(p[3], e, h);
}

static void ed_cswap(gf p[4], gf q[4], int b) {
    for (int i = 0; i < 4; i++) gf_cswap(p[i], q[i], b);
}

static void scalarmult(gf p[4], gf q[4], const uint8_t s[32]) {
    gf_0(p[0]); gf_1(p[1]); gf_1(p[2]); gf_0(p[3]);
    for (int i = 255; i >= 0; i--) {
        int b = (s[i/8] >> (i & 7)) & 1;
        ed_cswap(p, q, b);
        ed_add(q, p);
        ed_add(p, p);
        ed_cswap(p, q, b);
    }
}

static void scalarbase(gf p[4], const uint8_t s[32]) {
    gf q[4];
    gf_cpy(q[0], GF_X); gf_cpy(q[1], GF_Y); gf_1(q[2]); gf_mul(q[3], GF_X, GF_Y);
    scalarmult(p, q, s);
}

/* Pack an extended Edwards point to its 32-byte compressed form */
static void ed_pack(uint8_t r[32], gf p[4]) {
    gf tx, ty, zi;
    gf_inv(zi, p[2]);
    gf_mul(tx, p[0], zi);
    gf_mul(ty, p[1], zi);
    gf_pack(r, ty);
    r[31] ^= (uint8_t)(gf_par(tx) << 7);
}

/* Unpack a compressed point, returns 0 on success, -1 on invalid */
static int ed_unpack(gf r[4], const uint8_t p[32]) {
    gf t, chk, num, den, den2, den4, den6;
    int sgn = p[31] >> 7;
    uint8_t pp[32]; memcpy(pp, p, 32); pp[31] &= 0x7f;
    gf_unpack(r[1], pp);
    gf_1(r[2]);
    gf_sqr(num, r[1]);      /* y^2 */
    gf_mul(den, num, GF_D); /* d*y^2 */
    gf_sub(num, num, r[2]); /* y^2 - 1 */
    gf_add(den, den, r[2]); /* d*y^2 + 1 */
    /* x^2 = num/den */
    gf_sqr(den2, den);
    gf_sqr(den4, den2);
    gf_mul(den6, den4, den2);
    gf_mul(t, den6, num);
    gf_mul(t, t, den);  /* t = num * den^7 */
    gf_pow2523(t, t);   /* t = (num*den^7)^((p-5)/8) */
    gf_mul(t, t, num);
    gf_mul(t, t, den);
    gf_mul(t, t, den);
    gf_mul(r[0], t, den);  /* candidate x = num * den^3 * t */

    gf_sqr(chk, r[0]);
    gf_mul(chk, chk, den);
    /* check chk == num */
    int ok = 1;
    {   gf diff; gf_sub(diff, chk, num);
        uint8_t d32[32]; gf_pack(d32, diff);
        for (int i = 0; i < 32; i++) if (d32[i]) { ok = 0; break; }
    }
    if (!ok) {
        gf_mul(r[0], r[0], GF_I);
        gf_sqr(chk, r[0]);
        gf_mul(chk, chk, den);
        gf_sub(chk, chk, num);
        uint8_t d32[32]; gf_pack(d32, chk);
        for (int i = 0; i < 32; i++) if (d32[i]) return -1;
    }
    if (gf_par(r[0]) != (uint8_t)sgn) {
        for (int i = 0; i < 16; i++) r[0][i] = -r[0][i];
    }
    gf_mul(r[3], r[0], r[1]);
    return 0;
}

/* ── Scalar reduction mod l (group order of Ed25519) ───────────────────── */
/* Verbatim from TweetNaCl reference (tweetnacl-20140427.c), byte-level arithmetic. */

static const long long sc_L[32] = {
    0xed,0xd3,0xf5,0x5c,0x1a,0x63,0x12,0x58,0xd6,0x9c,0xf7,0xa2,0xde,0xf9,0xde,0x14,
    0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0x10
};

/* Reduce a 64-element byte-array x mod l, writing 32-byte result to r. */
static void sc_modL(uint8_t *r, long long x[64]) {
    long long carry, i, j, k;
    for (i = 63; i >= 32; --i) {
        carry = 0;
        for (j = i - 32, k = i - 12; j < k; ++j) {
            x[j] += carry - 16 * x[i] * sc_L[j - (i - 32)];
            carry = (x[j] + 128) >> 8;
            x[j] -= carry * 256;
        }
        x[j] += carry;
        x[i] = 0;
    }
    carry = 0;
    for (j = 0; j < 32; ++j) {
        x[j] += carry - (x[31] >> 4) * sc_L[j];
        carry = x[j] >> 8;
        x[j] &= 255;
    }
    for (j = 0; j < 32; ++j) x[j] -= carry * sc_L[j];
    for (i = 0; i < 32; ++i) {
        x[i+1] += x[i] >> 8;
        r[i] = (uint8_t)(x[i] & 255);
    }
}

/* Reduce a 64-byte value mod l in-place, zeroing the upper 32 bytes. */
static void sc_reduce(uint8_t r[64]) {
    long long x[64];
    int i;
    for (i = 0; i < 64; i++) x[i] = (long long)(unsigned char)r[i];
    memset(r, 0, 64);
    sc_modL(r, x);
}

/* ── Clamp scalar per ed25519 spec ─────────────────────────────────────── */

static void clamp(uint8_t a[32]) {
    a[0]  &= 248;
    a[31] &= 127;
    a[31] |= 64;
}

/* ── PRNG (uses system entropy via /dev/urandom) ────────────────────────── */

static int randombytes(uint8_t *out, size_t len) {
    FILE *f = fopen("/dev/urandom", "rb");
    if (!f) return -1;
    size_t n = fread(out, 1, len, f);
    fclose(f);
    return (n == len) ? 0 : -1;
}

/* ── Public API ──────────────────────────────────────────────────────────── */

int crypto_sign_keypair(unsigned char *pk, unsigned char *sk) {
    uint8_t seed[32], h[64];
    if (randombytes(seed, 32) != 0) return -1;
    sha512_hash(seed, 32, h);
    clamp(h);
    gf p[4];
    scalarbase(p, h);
    ed_pack(pk, p);
    memcpy(sk, seed, 32);
    memcpy(sk + 32, pk, 32);
    return 0;
}

int crypto_sign(unsigned char *sm, unsigned long long *smlen,
                const unsigned char *m, unsigned long long mlen,
                const unsigned char *sk) {
    uint8_t nonce[64], hram[64];
    uint8_t az[64], pk[32];

    memcpy(pk, sk + 32, 32);
    sha512_hash(sk, 32, az);
    clamp(az);

    /* nonce = H(az[32..63] || m) */
    sha512_2parts(az + 32, 32, m, (size_t)mlen, nonce);

    /* R = nonce * B */
    gf p[4];
    sc_reduce(nonce);
    scalarbase(p, nonce);
    ed_pack(sm, p);

    memcpy(sm + 32, pk, 32);

    /* hram = H(R || pk || m) */
    sha512_3parts(sm, 32, pk, 32, m, (size_t)mlen, hram);
    sc_reduce(hram);

    /* S = nonce + hram * az mod l (TweetNaCl byte-level) */
    {
        long long x[64]; int i, j;
        for (i = 0; i < 64; i++) x[i] = 0;
        for (i = 0; i < 32; i++) x[i] = (long long)(unsigned char)nonce[i];
        for (i = 0; i < 32; i++)
            for (j = 0; j < 32; j++)
                x[i+j] += (long long)(unsigned char)hram[i] * (long long)(unsigned char)az[j];
        sc_modL(sm + 32, x);
    }

    memcpy(sm + 64, m, (size_t)mlen);
    if (smlen) *smlen = mlen + 64;
    return 0;
}

int crypto_sign_open(unsigned char *m, unsigned long long *mlen,
                     const unsigned char *sm, unsigned long long smlen,
                     const unsigned char *pk) {
    if (smlen < 64) return -1;

    uint8_t h[64];
    gf p[4], q[4];

    /* Unpack pk into q */
    if (ed_unpack(q, pk) != 0) return -1;

    /* Unpack R from sm[0..31] into p */
    uint8_t Rbuf[32]; memcpy(Rbuf, sm, 32);
    if (ed_unpack(p, Rbuf) != 0) return -1;

    /* h = H(R || pk || m) */
    sha512_3parts(sm, 32, pk, 32, sm + 64, (size_t)(smlen - 64), h);
    sc_reduce(h);

    /* check: S*B == R + h*A
     * Negate A: compute -q
     * Rewrite as: s*B - h*A == R  =>  s*B + h*(-A) == R */
    /* Negate q[0] (negate x coordinate) */
    for (int i = 0; i < 16; i++) q[0][i] = -q[0][i];
    /* Also negate q[3] = T = X*Y/Z, so negate T too */
    for (int i = 0; i < 16; i++) q[3][i] = -q[3][i];

    /* Compute S*B */
    uint8_t S[32]; memcpy(S, sm + 32, 32);
    gf rq[4];
    scalarbase(rq, S);

    /* Compute h*(-A) by scalarmult */
    gf hA[4];
    scalarmult(hA, q, h);

    /* rq = S*B + h*(-A) */
    ed_add(rq, hA);

    /* Pack rq and compare to sm[0..31] */
    uint8_t computed_R[32];
    ed_pack(computed_R, rq);
    int diff = 0;
    for (int i = 0; i < 32; i++) diff |= computed_R[i] ^ sm[i];
    if (diff != 0) return -1;

    unsigned long long msglen = smlen - 64;
    if (m) memcpy(m, sm + 64, (size_t)msglen);
    if (mlen) *mlen = msglen;
    return 0;
}
