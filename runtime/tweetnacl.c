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
        o[(i+1) & 15] += (i < 15) ? c : 38*c;
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
/* l = 2^252 + 27742317777372353535851937790883648493 */

static const uint8_t L[32] = {
    0xed,0xd3,0xf5,0x5c,0x1a,0x63,0x12,0x58,0xd6,0x9c,0xf7,0xa2,0xde,0xf9,0xde,0x14,
    0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x00,0x10
};

static void mod_l(uint8_t r[64], const long long x[64]) {
    long long t[64]; int i;
    for (i = 0; i < 64; i++) t[i] = x[i];
    for (i = 63; i >= 32; i--) {
        long long c = t[i]; int j;
        t[i-32] += -c * 683901L;  /* = c * (2^32 - L[0..7]) */
        t[i-31] += c * 646383L;   /* Barrett reduction coefficients for L */
        t[i-30] -= c * 1515980L;
        t[i-29] += c * 1346650L;
        t[i-28] -= c * 407664L;
        t[i-27] += c * 1147784L;
        t[i-26] -= c * 659183L;
        t[i-25] += c * 1432811L;
        t[i-24] -= c * 258563L;
        t[i-23] += c * 742985L;
        t[i-22] -= c * 256767L;
        t[i-21] += c * 874869L;
        t[i-20] -= c * 1188233L;
        t[i-19] -= c * 1651917L;
        t[i-18] += c * 1095438L;
        t[i-17] -= c * 1099701L;
        t[i-16] -= c * 2200603L;
        t[i-15] += c * 978729L;
        t[i-14] -= c * 1659840L;
        t[i-13] += c * 2140587L;
        t[i-12] -= c * 1049312L;
        t[i-11] += c * 1399326L;
        t[i-10] -= c * 1406606L;
        t[i-9]  += c * 2288695L;
        t[i-8]  -= c * 1804556L;
        t[i-7]  += c * 1785233L;
        t[i-6]  -= c * 2028688L;
        t[i-5]  += c * 1359941L;
        t[i-4]  -= c * 2037965L;
        t[i-3]  += c * 648833L;
        t[i-2]  -= c * 1077862L;
        t[i-1]  += c * 1173584L;
        t[i]     = 0;
    }
    /* Carry propagation */
    long long carry[32] = {0};
    for (i = 0; i < 31; i++) {
        carry[i] = (t[i] + (1LL << 20)) >> 21;
        t[i+1] += carry[i];
        t[i] -= carry[i] * (1LL << 21);
    }
    /* Final reduction */
    long long b = 1;
    for (i = 0; i < 32; i++) { b = b + 0xff + t[i]; r[i] = (uint8_t)(b & 0xff); b >>= 8; }
}

/* Reduce a 64-byte hash modulo l, writing result to r[32] */
static void sc_reduce(uint8_t r[64]) {
    long long x[64];
    for (int i = 0; i < 64; i++) x[i] = r[i];
    uint8_t out[64] = {0};
    mod_l(out, x);
    memcpy(r, out, 32);
    memset(r + 32, 0, 32);
}

/* Compute s = (r + h*a) mod l, all inputs as 32-byte little-endian.
 * r, h, a are 32-byte values; out is 32 bytes. */
static void sc_muladd(uint8_t *s, const uint8_t *a, const uint8_t *b, const uint8_t *c) {
    /* s = a*b + c mod l  — used as: S = (r + H * a_scalar) mod l */
    long long a0,a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11;
    long long b0,b1,b2,b3,b4,b5,b6,b7,b8,b9,b10,b11;
    long long c0,c1,c2,c3,c4,c5,c6,c7,c8,c9,c10,c11;
    long long s0,s1,s2,s3,s4,s5,s6,s7,s8,s9,s10,s11,s12,s13,s14,s15,s16,s17,s18,s19,s20,s21,s22,s23;
    long long carry0,carry1,carry2,carry3,carry4,carry5,carry6,carry7,carry8,carry9,carry10,carry11;
    long long carry12,carry13,carry14,carry15,carry16,carry17,carry18,carry19,carry20,carry21,carry22;
    /* Unpack 3-byte limbs (21 bits each) */
    #define LOAD3H(p, i) ((long long)((p)[(i)] | ((p)[(i)+1]<<8) | ((p)[(i)+2]<<16)) >> 5)
    #define LOAD4(p, i)  ((long long)((p)[(i)] | ((p)[(i)+1]<<8) | ((p)[(i)+2]<<16) | ((int32_t)((p)[(i)+3])<<24)))
    a0 =  2097151 & (((long long)a[0])|(((long long)a[1])<<8)|(((long long)a[2])<<16));
    a1 =  2097151 & ((((long long)a[2])>>5)|(((long long)a[3])<<3)|(((long long)a[4])<<11)|(((long long)a[5])<<19));
    a2 =  2097151 & ((((long long)a[5])>>2)|(((long long)a[6])<<6)|(((long long)a[7])<<14));
    a3 =  2097151 & ((((long long)a[7])>>7)|(((long long)a[8])<<1)|(((long long)a[9])<<9)|(((long long)a[10])<<17));
    a4 =  2097151 & ((((long long)a[10])>>4)|(((long long)a[11])<<4)|(((long long)a[12])<<12));
    a5 =  2097151 & ((((long long)a[12])>>1)|(((long long)a[13])<<7)|(((long long)a[14])<<15));
    a6 =  2097151 & ((((long long)a[14])>>6)|(((long long)a[15])<<2)|(((long long)a[16])<<10));
    a7 =  2097151 & ((((long long)a[16])>>3)|(((long long)a[17])<<5)|(((long long)a[18])<<13));
    a8 =  2097151 & (((long long)a[19])|(((long long)a[20])<<8)|(((long long)a[21])<<16));
    a9 =  2097151 & ((((long long)a[21])>>5)|(((long long)a[22])<<3)|(((long long)a[23])<<11)|(((long long)a[24])<<19));
    a10 = 2097151 & ((((long long)a[24])>>2)|(((long long)a[25])<<6)|(((long long)a[26])<<14));
    a11 = (((long long)a[26])>>7)|(((long long)a[27])<<1)|(((long long)a[28])<<9)|(((long long)a[29])<<17)|(((long long)a[30])<<25)|(((long long)a[31])<<33);

    b0 =  2097151 & (((long long)b[0])|(((long long)b[1])<<8)|(((long long)b[2])<<16));
    b1 =  2097151 & ((((long long)b[2])>>5)|(((long long)b[3])<<3)|(((long long)b[4])<<11)|(((long long)b[5])<<19));
    b2 =  2097151 & ((((long long)b[5])>>2)|(((long long)b[6])<<6)|(((long long)b[7])<<14));
    b3 =  2097151 & ((((long long)b[7])>>7)|(((long long)b[8])<<1)|(((long long)b[9])<<9)|(((long long)b[10])<<17));
    b4 =  2097151 & ((((long long)b[10])>>4)|(((long long)b[11])<<4)|(((long long)b[12])<<12));
    b5 =  2097151 & ((((long long)b[12])>>1)|(((long long)b[13])<<7)|(((long long)b[14])<<15));
    b6 =  2097151 & ((((long long)b[14])>>6)|(((long long)b[15])<<2)|(((long long)b[16])<<10));
    b7 =  2097151 & ((((long long)b[16])>>3)|(((long long)b[17])<<5)|(((long long)b[18])<<13));
    b8 =  2097151 & (((long long)b[19])|(((long long)b[20])<<8)|(((long long)b[21])<<16));
    b9 =  2097151 & ((((long long)b[21])>>5)|(((long long)b[22])<<3)|(((long long)b[23])<<11)|(((long long)b[24])<<19));
    b10 = 2097151 & ((((long long)b[24])>>2)|(((long long)b[25])<<6)|(((long long)b[26])<<14));
    b11 = (((long long)b[26])>>7)|(((long long)b[27])<<1)|(((long long)b[28])<<9)|(((long long)b[29])<<17)|(((long long)b[30])<<25)|(((long long)b[31])<<33);

    c0 =  2097151 & (((long long)c[0])|(((long long)c[1])<<8)|(((long long)c[2])<<16));
    c1 =  2097151 & ((((long long)c[2])>>5)|(((long long)c[3])<<3)|(((long long)c[4])<<11)|(((long long)c[5])<<19));
    c2 =  2097151 & ((((long long)c[5])>>2)|(((long long)c[6])<<6)|(((long long)c[7])<<14));
    c3 =  2097151 & ((((long long)c[7])>>7)|(((long long)c[8])<<1)|(((long long)c[9])<<9)|(((long long)c[10])<<17));
    c4 =  2097151 & ((((long long)c[10])>>4)|(((long long)c[11])<<4)|(((long long)c[12])<<12));
    c5 =  2097151 & ((((long long)c[12])>>1)|(((long long)c[13])<<7)|(((long long)c[14])<<15));
    c6 =  2097151 & ((((long long)c[14])>>6)|(((long long)c[15])<<2)|(((long long)c[16])<<10));
    c7 =  2097151 & ((((long long)c[16])>>3)|(((long long)c[17])<<5)|(((long long)c[18])<<13));
    c8 =  2097151 & (((long long)c[19])|(((long long)c[20])<<8)|(((long long)c[21])<<16));
    c9 =  2097151 & ((((long long)c[21])>>5)|(((long long)c[22])<<3)|(((long long)c[23])<<11)|(((long long)c[24])<<19));
    c10 = 2097151 & ((((long long)c[24])>>2)|(((long long)c[25])<<6)|(((long long)c[26])<<14));
    c11 = (((long long)c[26])>>7)|(((long long)c[27])<<1)|(((long long)c[28])<<9)|(((long long)c[29])<<17)|(((long long)c[30])<<25)|(((long long)c[31])<<33);

    s0 = c0 + a0*b0;
    s1 = c1 + a0*b1 + a1*b0;
    s2 = c2 + a0*b2 + a1*b1 + a2*b0;
    s3 = c3 + a0*b3 + a1*b2 + a2*b1 + a3*b0;
    s4 = c4 + a0*b4 + a1*b3 + a2*b2 + a3*b1 + a4*b0;
    s5 = c5 + a0*b5 + a1*b4 + a2*b3 + a3*b2 + a4*b1 + a5*b0;
    s6 = c6 + a0*b6 + a1*b5 + a2*b4 + a3*b3 + a4*b2 + a5*b1 + a6*b0;
    s7 = c7 + a0*b7 + a1*b6 + a2*b5 + a3*b4 + a4*b3 + a5*b2 + a6*b1 + a7*b0;
    s8 = c8 + a0*b8 + a1*b7 + a2*b6 + a3*b5 + a4*b4 + a5*b3 + a6*b2 + a7*b1 + a8*b0;
    s9 = c9 + a0*b9 + a1*b8 + a2*b7 + a3*b6 + a4*b5 + a5*b4 + a6*b3 + a7*b2 + a8*b1 + a9*b0;
    s10= c10+ a0*b10+ a1*b9 + a2*b8 + a3*b7 + a4*b6 + a5*b5 + a6*b4 + a7*b3 + a8*b2 + a9*b1 + a10*b0;
    s11= c11+ a0*b11+ a1*b10+ a2*b9 + a3*b8 + a4*b7 + a5*b6 + a6*b5 + a7*b4 + a8*b3 + a9*b2 + a10*b1 + a11*b0;
    s12=      a1*b11+ a2*b10+ a3*b9 + a4*b8 + a5*b7 + a6*b6 + a7*b5 + a8*b4 + a9*b3 + a10*b2 + a11*b1;
    s13=      a2*b11+ a3*b10+ a4*b9 + a5*b8 + a6*b7 + a7*b6 + a8*b5 + a9*b4 + a10*b3 + a11*b2;
    s14=      a3*b11+ a4*b10+ a5*b9 + a6*b8 + a7*b7 + a8*b6 + a9*b5 + a10*b4 + a11*b3;
    s15=      a4*b11+ a5*b10+ a6*b9 + a7*b8 + a8*b7 + a9*b6 + a10*b5 + a11*b4;
    s16=      a5*b11+ a6*b10+ a7*b9 + a8*b8 + a9*b7 + a10*b6 + a11*b5;
    s17=      a6*b11+ a7*b10+ a8*b9 + a9*b8 + a10*b7 + a11*b6;
    s18=      a7*b11+ a8*b10+ a9*b9 + a10*b8 + a11*b7;
    s19=      a8*b11+ a9*b10+ a10*b9 + a11*b8;
    s20=      a9*b11+ a10*b10+ a11*b9;
    s21=      a10*b11+ a11*b10;
    s22=      a11*b11;
    s23= 0;

    #define CARRY21(i) carry##i = (s##i + (1<<20)) >> 21; s##i##1 += carry##i; s##i -= carry##i * (1LL<<21)
    /* reduce s12..s23 using l coefficients */
    s11 += s23 * 666643; s10 += s23 * 470296; s9  += s23 * 654183;
    s8  -= s23 * 997805; s7  += s23 * 136657; s6  -= s23 * 683901; s23 = 0;
    s10 += s22 * 666643; s9  += s22 * 470296; s8  += s22 * 654183;
    s7  -= s22 * 997805; s6  += s22 * 136657; s5  -= s22 * 683901; s22 = 0;
    s9  += s21 * 666643; s8  += s21 * 470296; s7  += s21 * 654183;
    s6  -= s21 * 997805; s5  += s21 * 136657; s4  -= s21 * 683901; s21 = 0;
    s8  += s20 * 666643; s7  += s20 * 470296; s6  += s20 * 654183;
    s5  -= s20 * 997805; s4  += s20 * 136657; s3  -= s20 * 683901; s20 = 0;
    s7  += s19 * 666643; s6  += s19 * 470296; s5  += s19 * 654183;
    s4  -= s19 * 997805; s3  += s19 * 136657; s2  -= s19 * 683901; s19 = 0;
    s6  += s18 * 666643; s5  += s18 * 470296; s4  += s18 * 654183;
    s3  -= s18 * 997805; s2  += s18 * 136657; s1  -= s18 * 683901; s18 = 0;

    carry6  = (s6  + (1<<20)) >> 21; s7  += carry6;  s6  -= carry6  * (1LL<<21);
    carry8  = (s8  + (1<<20)) >> 21; s9  += carry8;  s8  -= carry8  * (1LL<<21);
    carry10 = (s10 + (1<<20)) >> 21; s11 += carry10; s10 -= carry10 * (1LL<<21);
    carry12 = (s12 + (1<<20)) >> 21; s13 += carry12; s12 -= carry12 * (1LL<<21);
    carry14 = (s14 + (1<<20)) >> 21; s15 += carry14; s14 -= carry14 * (1LL<<21);
    carry16 = (s16 + (1<<20)) >> 21; s17 += carry16; s16 -= carry16 * (1LL<<21);
    carry7  = (s7  + (1<<20)) >> 21; s8  += carry7;  s7  -= carry7  * (1LL<<21);
    carry9  = (s9  + (1<<20)) >> 21; s10 += carry9;  s9  -= carry9  * (1LL<<21);
    carry11 = (s11 + (1<<20)) >> 21; s12 += carry11; s11 -= carry11 * (1LL<<21);
    carry13 = (s13 + (1<<20)) >> 21; s14 += carry13; s13 -= carry13 * (1LL<<21);
    carry15 = (s15 + (1<<20)) >> 21; s16 += carry15; s15 -= carry15 * (1LL<<21);

    s5  += s17 * 666643; s4  += s17 * 470296; s3  += s17 * 654183;
    s2  -= s17 * 997805; s1  += s17 * 136657; s0  -= s17 * 683901; s17 = 0;
    s4  += s16 * 666643; s3  += s16 * 470296; s2  += s16 * 654183;
    s1  -= s16 * 997805; s0  += s16 * 136657;
    carry16 = (s16 * 666643) >> 21; /* unused if s16 already 0 after above */
    s1  -= s16 * 683901; s16 = 0;

    s3  += s15 * 666643; s2  += s15 * 470296; s1  += s15 * 654183;
    s0  -= s15 * 997805;
    carry15 = (s15 * 136657 + (1<<20)) >> 21;
    s0  += s15 * 136657; s15 -= s15 * 683901; s15 = 0;

    s2  += s14 * 666643; s1  += s14 * 470296; s0  += s14 * 654183;
    carry14 = (s14 * (-997805) + (1<<20)) >> 21;
    s0  -= s14 * 997805; s14 = 0;

    s1  += s13 * 666643; s0  += s13 * 470296;
    carry13 = (s13 * 654183 + (1<<20)) >> 21;
    s0  += s13 * 654183; s13 = 0;

    s0  += s12 * 666643;
    s12 = 0;

    carry0  = (s0  + (1<<20)) >> 21; s1  += carry0;  s0  -= carry0  * (1LL<<21);
    carry2  = (s2  + (1<<20)) >> 21; s3  += carry2;  s2  -= carry2  * (1LL<<21);
    carry4  = (s4  + (1<<20)) >> 21; s5  += carry4;  s4  -= carry4  * (1LL<<21);
    carry6  = (s6  + (1<<20)) >> 21; s7  += carry6;  s6  -= carry6  * (1LL<<21);
    carry8  = (s8  + (1<<20)) >> 21; s9  += carry8;  s8  -= carry8  * (1LL<<21);
    carry10 = (s10 + (1<<20)) >> 21; s11 += carry10; s10 -= carry10 * (1LL<<21);
    carry1  = (s1  + (1<<20)) >> 21; s2  += carry1;  s1  -= carry1  * (1LL<<21);
    carry3  = (s3  + (1<<20)) >> 21; s4  += carry3;  s3  -= carry3  * (1LL<<21);
    carry5  = (s5  + (1<<20)) >> 21; s6  += carry5;  s5  -= carry5  * (1LL<<21);
    carry7  = (s7  + (1<<20)) >> 21; s8  += carry7;  s7  -= carry7  * (1LL<<21);
    carry9  = (s9  + (1<<20)) >> 21; s10 += carry9;  s9  -= carry9  * (1LL<<21);
    carry11 = (s11 + (1<<20)) >> 21; s12 += carry11; s11 -= carry11 * (1LL<<21);

    s0  += s12 * 666643; s1  += s12 * 470296; s2  += s12 * 654183;
    s3  -= s12 * 997805; s4  += s12 * 136657; s5  -= s12 * 683901; s12 = 0;

    carry0 = (s0 + (1<<20)) >> 21; s1  += carry0; s0  -= carry0  * (1LL<<21);
    carry1 = (s1 + (1<<20)) >> 21; s2  += carry1; s1  -= carry1  * (1LL<<21);
    carry2 = (s2 + (1<<20)) >> 21; s3  += carry2; s2  -= carry2  * (1LL<<21);
    carry3 = (s3 + (1<<20)) >> 21; s4  += carry3; s3  -= carry3  * (1LL<<21);
    carry4 = (s4 + (1<<20)) >> 21; s5  += carry4; s4  -= carry4  * (1LL<<21);
    carry5 = (s5 + (1<<20)) >> 21; s6  += carry5; s5  -= carry5  * (1LL<<21);
    carry6 = (s6 + (1<<20)) >> 21; s7  += carry6; s6  -= carry6  * (1LL<<21);
    carry7 = (s7 + (1<<20)) >> 21; s8  += carry7; s7  -= carry7  * (1LL<<21);
    carry8 = (s8 + (1<<20)) >> 21; s9  += carry8; s8  -= carry8  * (1LL<<21);
    carry9 = (s9 + (1<<20)) >> 21; s10 += carry9; s9  -= carry9  * (1LL<<21);
    carry10= (s10+ (1<<20)) >> 21; s11 += carry10;s10 -= carry10 * (1LL<<21);
    carry11= (s11+ (1<<20)) >> 21; s12 += carry11;s11 -= carry11 * (1LL<<21);

    s[0]  = (uint8_t)(s0  >> 0 );
    s[1]  = (uint8_t)(s0  >> 8 );
    s[2]  = (uint8_t)((s0 >> 16) | (s1  << 5));
    s[3]  = (uint8_t)(s1  >> 3 );
    s[4]  = (uint8_t)(s1  >> 11);
    s[5]  = (uint8_t)((s1 >> 19) | (s2  << 2));
    s[6]  = (uint8_t)(s2  >> 6 );
    s[7]  = (uint8_t)((s2 >> 14) | (s3  << 7));
    s[8]  = (uint8_t)(s3  >> 1 );
    s[9]  = (uint8_t)(s3  >> 9 );
    s[10] = (uint8_t)((s3 >> 17) | (s4  << 4));
    s[11] = (uint8_t)(s4  >> 4 );
    s[12] = (uint8_t)(s4  >> 12);
    s[13] = (uint8_t)((s4 >> 20) | (s5  << 1));
    s[14] = (uint8_t)(s5  >> 7 );
    s[15] = (uint8_t)((s5 >> 15) | (s6  << 6));
    s[16] = (uint8_t)(s6  >> 2 );
    s[17] = (uint8_t)(s6  >> 10);
    s[18] = (uint8_t)((s6 >> 18) | (s7  << 3));
    s[19] = (uint8_t)(s7  >> 5 );
    s[20] = (uint8_t)(s7  >> 13);
    s[21] = (uint8_t)(s8  >> 0 );
    s[22] = (uint8_t)(s8  >> 8 );
    s[23] = (uint8_t)((s8 >> 16) | (s9  << 5));
    s[24] = (uint8_t)(s9  >> 3 );
    s[25] = (uint8_t)(s9  >> 11);
    s[26] = (uint8_t)((s9 >> 19) | (s10 << 2));
    s[27] = (uint8_t)(s10 >> 6 );
    s[28] = (uint8_t)((s10>> 14) | (s11 << 7));
    s[29] = (uint8_t)(s11 >> 1 );
    s[30] = (uint8_t)(s11 >> 9 );
    s[31] = (uint8_t)(s11 >> 17);
    (void)carry16; (void)s23; (void)s22; (void)s21; (void)s20; (void)s19; (void)s18;
    (void)s17; (void)s16; (void)s15; (void)s14; (void)s13;
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
    uint8_t h[64], r[64], nonce[64], hram[64];
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

    /* S = nonce + hram * az */
    sc_muladd(sm + 32, hram, az, nonce);

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
