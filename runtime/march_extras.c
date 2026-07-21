/* runtime/march_extras.c — Vault, crypto, base64, UUID, sys, and other builtins.
 *
 * This file provides runtime implementations for March standard-library
 * builtins that are not in march_runtime.c or march_http.c.
 *
 * Implemented here:
 *   - Vault (in-memory named hash tables — ETS-like)
 *   - SHA-256, HMAC-SHA256, PBKDF2-SHA256 (via CommonCrypto on Apple; pure-C elsewhere)
 *   - Base64 encode/decode (march_ wrappers)
 *   - Random bytes (arc4random_buf / /dev/urandom)
 *   - UUID v4
 *   - sys_* builtins (uptime, cpu_count, heap_bytes, word_size, gc_counts, actor_count)
 *   - march_get_version
 *   - march_sha512 (stub — returns same as sha256 for now)
 */

#include "march_runtime.h"
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#ifdef __APPLE__
#  include <sys/sysctl.h>
#  include <mach/mach.h>
#  include <CommonCrypto/CommonCrypto.h>
#  include <CommonCrypto/CommonDigest.h>
#  include <CommonCrypto/CommonHMAC.h>
#  include <CommonCrypto/CommonKeyDerivation.h>
#  define HAS_COMMON_CRYPTO 1
#else
#  include <sys/sysinfo.h>
#  define HAS_COMMON_CRYPTO 0
#endif

/* ── SHA-256 (pure C fallback when CommonCrypto unavailable) ──────────── */

#if !HAS_COMMON_CRYPTO

#define ROTR32(x, n) (((x) >> (n)) | ((x) << (32 - (n))))
#define SHR(x, n)    ((x) >> (n))
#define CH(x,y,z)    (((x)&(y))^(~(x)&(z)))
#define MAJ(x,y,z)   (((x)&(y))^((x)&(z))^((y)&(z)))
#define EP0(x)       (ROTR32(x,2)^ROTR32(x,13)^ROTR32(x,22))
#define EP1(x)       (ROTR32(x,6)^ROTR32(x,11)^ROTR32(x,25))
#define SIG0(x)      (ROTR32(x,7)^ROTR32(x,18)^SHR(x,3))
#define SIG1(x)      (ROTR32(x,17)^ROTR32(x,19)^SHR(x,10))

static const uint32_t sha256_K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,
    0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,
    0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,
    0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,
    0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,
    0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,
    0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,
    0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,
    0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2
};

static void sha256_transform(uint32_t H[8], const uint8_t blk[64]) {
    uint32_t W[64], a,b,c,d,e,f,g,h,T1,T2;
    for (int i = 0; i < 16; i++)
        W[i] = ((uint32_t)blk[4*i]<<24)|((uint32_t)blk[4*i+1]<<16)|
               ((uint32_t)blk[4*i+2]<<8)|(uint32_t)blk[4*i+3];
    for (int i = 16; i < 64; i++)
        W[i] = SIG1(W[i-2])+W[i-7]+SIG0(W[i-15])+W[i-16];
    a=H[0];b=H[1];c=H[2];d=H[3];e=H[4];f=H[5];g=H[6];h=H[7];
    for (int i = 0; i < 64; i++) {
        T1=h+EP1(e)+CH(e,f,g)+sha256_K[i]+W[i];
        T2=EP0(a)+MAJ(a,b,c);
        h=g;g=f;f=e;e=d+T1;d=c;c=b;b=a;a=T1+T2;
    }
    H[0]+=a;H[1]+=b;H[2]+=c;H[3]+=d;
    H[4]+=e;H[5]+=f;H[6]+=g;H[7]+=h;
}

static void sha256_raw(const uint8_t *data, size_t len, uint8_t out[32]) {
    uint32_t H[8] = {
        0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,
        0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19
    };
    uint8_t block[64]; size_t i = 0;
    for (; i + 64 <= len; i += 64) sha256_transform(H, data + i);
    size_t rem = len - i;
    memset(block,0,64); memcpy(block, data+i, rem);
    block[rem] = 0x80;
    uint64_t bits = (uint64_t)len * 8;
    if (rem >= 56) { sha256_transform(H,block); memset(block,0,64); }
    block[56]=(uint8_t)(bits>>56);block[57]=(uint8_t)(bits>>48);
    block[58]=(uint8_t)(bits>>40);block[59]=(uint8_t)(bits>>32);
    block[60]=(uint8_t)(bits>>24);block[61]=(uint8_t)(bits>>16);
    block[62]=(uint8_t)(bits>>8); block[63]=(uint8_t)bits;
    sha256_transform(H,block);
    for (int j=0;j<8;j++){
        out[4*j]=(uint8_t)(H[j]>>24);out[4*j+1]=(uint8_t)(H[j]>>16);
        out[4*j+2]=(uint8_t)(H[j]>>8);out[4*j+3]=(uint8_t)(H[j]);
    }
}

static void hmac_sha256_raw(const uint8_t *key, size_t klen,
                             const uint8_t *msg, size_t mlen,
                             uint8_t out[32]) {
    uint8_t K[64], ipad[64], opad[64], tmp[32];
    if (klen > 64) { sha256_raw(key, klen, K); klen = 32; key = K; }
    memset(ipad,0x36,64); memset(opad,0x5c,64);
    for (size_t i=0;i<klen;i++){ipad[i]^=key[i];opad[i]^=key[i];}
    /* inner = sha256(ipad || msg) */
    size_t ilen = 64 + mlen;
    uint8_t *ibuf = malloc(ilen);
    memcpy(ibuf, ipad, 64); memcpy(ibuf+64, msg, mlen);
    sha256_raw(ibuf, ilen, tmp); free(ibuf);
    /* outer = sha256(opad || inner) */
    uint8_t obuf[64+32];
    memcpy(obuf, opad, 64); memcpy(obuf+64, tmp, 32);
    sha256_raw(obuf, 64+32, out);
}

static void pbkdf2_sha256_raw(const uint8_t *pass, size_t plen,
                               const uint8_t *salt, size_t slen,
                               uint64_t iters, uint32_t dklen,
                               uint8_t *dk) {
    /* Single PRF block (dklen <= 32) */
    uint8_t *u = malloc(slen + 4);
    memcpy(u, salt, slen);
    u[slen]=0;u[slen+1]=0;u[slen+2]=0;u[slen+3]=1;
    uint8_t U[32], T[32];
    hmac_sha256_raw(pass, plen, u, slen+4, U);
    free(u);
    memcpy(T, U, 32);
    for (uint64_t i=1; i<iters; i++) {
        hmac_sha256_raw(pass, plen, U, 32, U);
        for (int j=0;j<32;j++) T[j]^=U[j];
    }
    memcpy(dk, T, dklen < 32 ? dklen : 32);
}

#endif /* !HAS_COMMON_CRYPTO */

/* ── Platform SHA-256 / HMAC / PBKDF2 wrappers ───────────────────────── */

static void do_sha256(const uint8_t *data, size_t len, uint8_t out[32]) {
#if HAS_COMMON_CRYPTO
    CC_SHA256(data, (CC_LONG)len, out);
#else
    sha256_raw(data, len, out);
#endif
}

static void do_hmac_sha256(const uint8_t *key, size_t klen,
                            const uint8_t *msg, size_t mlen,
                            uint8_t out[32]) {
#if HAS_COMMON_CRYPTO
    CCHmac(kCCHmacAlgSHA256, key, klen, msg, mlen, out);
#else
    hmac_sha256_raw(key, klen, msg, mlen, out);
#endif
}

static void do_pbkdf2_sha256(const uint8_t *pass, size_t plen,
                              const uint8_t *salt, size_t slen,
                              uint64_t iters, uint32_t dklen,
                              uint8_t *dk) {
#if HAS_COMMON_CRYPTO
    CCKeyDerivationPBKDF(kCCPBKDF2, (const char *)pass, plen,
                         salt, slen, kCCPRFHmacAlgSHA256,
                         (uint)iters, dk, dklen);
#else
    pbkdf2_sha256_raw(pass, plen, salt, slen, iters, dklen, dk);
#endif
}

/* ── Random bytes ─────────────────────────────────────────────────────── */

static void platform_random_bytes(uint8_t *buf, size_t n) {
#ifdef __APPLE__
    arc4random_buf(buf, n);
#else
    int fd = open("/dev/urandom", O_RDONLY | O_CLOEXEC);
    if (fd >= 0) {
        size_t got = 0;
        while (got < n) {
            ssize_t r = read(fd, buf + got, n - got);
            if (r <= 0) break;
            got += (size_t)r;
        }
        close(fd);
    }
#endif
}

/* ── Base64 (using the existing base64.c encoder) ─────────────────────── */

/* Forward-declare the low-level function from base64.c */
int base64_encode(const uint8_t *in, size_t len, char *out, size_t out_sz);

/* Decode table: -1 = invalid, -2 = padding, 0-63 = value */
static int b64_decode_table[256];
static pthread_once_t b64_decode_init_once = PTHREAD_ONCE_INIT;

static void b64_decode_init(void) {
    memset(b64_decode_table, -1, sizeof(b64_decode_table));
    const char *enc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    for (int i = 0; i < 64; i++)
        b64_decode_table[(unsigned char)enc[i]] = i;
    b64_decode_table[(unsigned char)'='] = -2;
}

/* ── Bytes(List(Int)) helpers ─────────────────────────────────────────── */

/* Create a Cons(int, tail) list node.  Transfers ownership of tail.
 * The Int payload is pre-tagged with (n<<1)|1: under the uniform low-bit
 * integer tagging scheme, compiled code emits `ashr #1` when extracting an
 * Int field from a generic constructor slot, so a raw value would be halved
 * on untag.  (Same convention as make_int_cons in march_http.c.) */
static void *int_cons(int64_t n, void *tail) {
    void *node = march_alloc(16 + 16);   /* hdr(16) + i64(8) + ptr(8) */
    *(int32_t *)((char *)node + 8)  = 1; /* tag = 1 = Cons */
    *(int64_t *)((char *)node + 16) = (n << 1) | 1;
    *(void **)((char *)node + 24)   = tail;
    return node;
}

/* Create a Bytes(list) wrapper.  Transfers ownership of list. */
static void *bytes_wrap(void *list) {
    void *b = march_alloc(16 + 8);       /* hdr(16) + ptr(8) */
    /* tag stays 0 = Bytes ctor */
    *(void **)((char *)b + 16) = list;
    return b;
}

/* Build a Bytes(List(Int)) from raw bytes.  Returns owned reference. */
static void *bytes_from_raw(const uint8_t *data, size_t len) {
    void *list = march_alloc(16); /* Nil: tag=0, rc=1 */
    for (ssize_t i = (ssize_t)len - 1; i >= 0; i--)
        list = int_cons((int64_t)data[i], list);
    return bytes_wrap(list);
}

/* Extract raw bytes from a Bytes(List(Int)) value. Returns malloc'd buffer,
 * sets *out_len. Caller must free. */
static uint8_t *bytes_to_raw(void *bytes_val, size_t *out_len) {
    /* Bytes(list): field 0 at offset 16 is the list pointer */
    void *list = *(void **)((char *)bytes_val + 16);
    /* Count entries first */
    size_t n = 0;
    void *p = list;
    while (p) {
        int32_t tag = *(int32_t *)((char *)p + 8);
        if (tag == 0) break; /* Nil */
        n++;
        p = *(void **)((char *)p + 24);
    }
    uint8_t *buf = malloc(n > 0 ? n : 1);
    *out_len = n;
    p = list; size_t i = 0;
    while (p && i < n) {
        int32_t tag = *(int32_t *)((char *)p + 8);
        if (tag == 0) break;
        /* Untag the Int payload: generic ctor slots store (n<<1)|1. */
        buf[i++] = (uint8_t)((*(int64_t *)((char *)p + 16) >> 1) & 0xFF);
        p = *(void **)((char *)p + 24);
    }
    return buf;
}

/* Extract bytes from a march_string.  Returns malloc'd buffer. */
static uint8_t *string_to_raw(void *str, size_t *out_len) {
    march_string *ms = (march_string *)str;
    uint8_t *buf = malloc(ms->len > 0 ? ms->len : 1);
    memcpy(buf, ms->data, ms->len);
    *out_len = (size_t)ms->len;
    return buf;
}

/* ── Result helpers ───────────────────────────────────────────────────── */

static void *make_ok(void *val) {
    void *r = march_alloc(16 + 8);
    /* tag stays 0 = Ok */
    *(void **)((char *)r + 16) = val;
    return r;
}

static void *make_err_str(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;   /* tag = 1 = Err */
    *(void **)((char *)r + 16) = s;
    return r;
}

/* ── Option helpers — NICHE encoding (None=0, Some(v)=v).
 * All March values in ptr slots are either tagged scalars (odd-bit, nonzero)
 * or heap pointers (even, nonzero from march_alloc).  The only exceptions are
 * Float 0.0 (bitcast to 0) and Unit (inttoptr 0 = null), which are stored
 * through separate boxed Option paths and never reach make_some/make_none. */

static void *make_some(void *val) { return val; }
static void *make_none(void) { return (void *)0; }

/* ── Kind-aware Option helpers for march_record_get ─────────────────────────
 * Kind chars match shape_kind_char in llvm_emit.ml:
 *   'i' = Int/Bool/Unit/Atom (tagged (raw<<1)|1, always odd, nonzero)
 *   'p' = String/List/heap ptr (nonzero march_alloc address)
 *   'f' = Float (raw IEEE754 bits)
 *   'g' = generic/TVar
 *
 * ALL kinds use the NICHE encoding (None = 0, Some(v) = v).  record_get's
 * March type is Option(a) with an ERASED payload, and the compiled side
 * decodes erased Options with the niche convention everywhere (emit_case's
 * abstract-arg niche path, ensure_adt_eq_fn, the erased alloc paths).  The
 * previous boxed cells for 'f'/'g' were misread by those niche decoders as
 * Some(cell) — the cell then flowed on as a "record" and every downstream
 * record_get/record_entries panicked with "no record shape metadata"
 * (74 depot failures).  Niche-encoding costs the two known erased-niche edge
 * cases (Float 0.0 and raw-0 Unit read as None) — the same trade the
 * compiled convention already makes; consistency wins. */

/* Float is the one record kind that is NOT niche-safe: 0.0's bits are 0, which
 * collides with the None niche, and a nonzero float's bits are not a valid heap
 * pointer.  llvm_emit decodes a *concrete* Option(Float) as BOXED
 * (Repr.niche_payload_ok TFloat = false): None = tag-0 heap cell, Some(f) =
 * tag-1 cell with the double at offset 16 (see EAlloc alloc-none-boxed /
 * alloc-some-boxed).  So for an 'f' *call site* we must return that boxed shape;
 * the uniform niche return would read stored 0.0 back as None and make the boxed
 * decoder dereference raw float bits as a pointer → SIGSEGV.
 *
 * Keyed on the CALL-SITE expected_kind, never the stored kind: an erased ('g')
 * read still gets the niche encoding both sides expect, so this does not
 * reintroduce the boxed-cell-misread-by-niche-decoder regression (the "74 depot
 * failures" that motivated niche-for-erased). */
static void *rec_box_none_float(void) {
    return march_alloc(16);                     /* tag=0 (None), no fields */
}
static void *rec_box_some_float(int64_t bits) {
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8)  = 1;           /* tag = 1 = Some */
    *(int64_t *)((char *)r + 16) = bits;        /* raw IEEE-754 double bits */
    return r;
}

static void *rec_some_k(int64_t bits, char kind) {
    if (kind == 'f') return rec_box_some_float(bits);
    return (void *)(uintptr_t)bits;
}

static void *rec_none_k(char kind) {
    if (kind == 'f') return rec_box_none_float();
    return (void *)0;
}

/* ── Hex encoding ─────────────────────────────────────────────────────── */

static void bytes_to_hex(const uint8_t *b, size_t n, char *out) {
    static const char hex[] = "0123456789abcdef";
    for (size_t i = 0; i < n; i++) {
        out[2*i]   = hex[b[i] >> 4];
        out[2*i+1] = hex[b[i] & 0xf];
    }
    out[2*n] = '\0';
}

/* ── march_sha1_bytes ───────────────────────────────────────────────── */

/* Forward declaration from sha1.c */
void sha1(const uint8_t *msg, size_t len, uint8_t out[20]);

/* Takes a String and returns a Bytes(List(Int)) of the 20-byte SHA-1 hash. */
void *march_sha1_bytes(void *str) {
    size_t len;
    uint8_t *bytes = string_to_raw(str, &len);
    uint8_t hash[20];
    sha1(bytes, len, hash);
    free(bytes);
    return bytes_from_raw(hash, 20);
}

/* ── march_sha256 ────────────────────────────────────────────────────── */

/* Takes a String (or Bytes) and returns a 64-char lowercase hex String */
void *march_sha256(void *data) {
    size_t len;
    uint8_t *bytes;
    /* Distinguish String vs Bytes by looking at the int64 at offset 8.
     * String: offset 8 = int64_t len (string length, typically > 0 or 0 for empty).
     * Bytes ctor: offset 8 = int32_t tag (0) + int32_t pad (0) = 0 as int64.
     * Heuristic: if the value at offset 8 is likely a tag (0 or small int),
     * treat as Bytes; otherwise treat as String. */
    int64_t field8 = *(int64_t *)((char *)data + 8);
    if ((uint32_t)field8 == 0 && (uint32_t)(field8 >> 32) == 0) {
        /* Looks like Bytes(List(Int)): field8 = (tag=0, pad=0) = 0 */
        bytes = bytes_to_raw(data, &len);
    } else {
        bytes = string_to_raw(data, &len);
    }
    uint8_t hash[32];
    do_sha256(bytes, len, hash);
    free(bytes);
    char hex[65];
    bytes_to_hex(hash, 32, hex);
    return march_string_lit(hex, 64);
}

/* ── march_sha512 ────────────────────────────────────────────────────── */

/* Stub: returns sha256 hex (proper sha512 requires additional implementation) */
void *march_sha512(void *data) {
    return march_sha256(data);
}

/* ── march_md5 ───────────────────────────────────────────────────────── */

/* RFC 1321 MD5 — portable pure-C implementation.
 * Returns the 32-character lowercase hex digest of the input string. */
static void md5_raw(const uint8_t *msg, size_t len, uint8_t out[16]) {
    uint32_t s[64] = {
        7,12,17,22, 7,12,17,22, 7,12,17,22, 7,12,17,22,
        5, 9,14,20, 5, 9,14,20, 5, 9,14,20, 5, 9,14,20,
        4,11,16,23, 4,11,16,23, 4,11,16,23, 4,11,16,23,
        6,10,15,21, 6,10,15,21, 6,10,15,21, 6,10,15,21
    };
    uint32_t K[64] = {
        0xd76aa478,0xe8c7b756,0x242070db,0xc1bdceee,0xf57c0faf,0x4787c62a,
        0xa8304613,0xfd469501,0x698098d8,0x8b44f7af,0xffff5bb1,0x895cd7be,
        0x6b901122,0xfd987193,0xa679438e,0x49b40821,0xf61e2562,0xc040b340,
        0x265e5a51,0xe9b6c7aa,0xd62f105d,0x02441453,0xd8a1e681,0xe7d3fbc8,
        0x21e1cde6,0xc33707d6,0xf4d50d87,0x455a14ed,0xa9e3e905,0xfcefa3f8,
        0x676f02d9,0x8d2a4c8a,0xfffa3942,0x8771f681,0x6d9d6122,0xfde5380c,
        0xa4beea44,0x4bdecfa9,0xf6bb4b60,0xbebfbc70,0x289b7ec6,0xeaa127fa,
        0xd4ef3085,0x04881d05,0xd9d4d039,0xe6db99e5,0x1fa27cf8,0xc4ac5665,
        0xf4292244,0x432aff97,0xab9423a7,0xfc93a039,0x655b59c3,0x8f0ccc92,
        0xffeff47d,0x85845dd1,0x6fa87e4f,0xfe2ce6e0,0xa3014314,0x4e0811a1,
        0xf7537e82,0xbd3af235,0x2ad7d2bb,0xeb86d391
    };
    uint32_t a0=0x67452301,b0=0xefcdab89,c0=0x98badcfe,d0=0x10325476;
    size_t orig_len = len;
    size_t new_len = len + 1;
    while (new_len % 64 != 56) new_len++;
    new_len += 8;
    uint8_t *m = (uint8_t *)calloc(new_len, 1);
    memcpy(m, msg, len);
    m[len] = 0x80;
    uint64_t bits = (uint64_t)orig_len * 8;
    memcpy(m + new_len - 8, &bits, 8);
    for (size_t off = 0; off < new_len; off += 64) {
        uint32_t M[16];
        memcpy(M, m + off, 64);
        uint32_t A=a0,B=b0,C=c0,D=d0,F,g;
        for (uint32_t i=0;i<64;i++){
            if(i<16){F=(B&C)|(~B&D);g=i;}
            else if(i<32){F=(D&B)|(~D&C);g=(5*i+1)%16;}
            else if(i<48){F=B^C^D;g=(3*i+5)%16;}
            else{F=C^(B|(~D));g=(7*i)%16;}
            F=F+A+K[i]+M[g];
            A=D;D=C;C=B;
            B=B+((F<<s[i])|(F>>(32-s[i])));
        }
        a0+=A;b0+=B;c0+=C;d0+=D;
    }
    free(m);
    uint32_t digest[4]={a0,b0,c0,d0};
    memcpy(out,digest,16);
}

void *march_md5(void *data) {
    size_t len;
    uint8_t *bytes = string_to_raw(data, &len);
    uint8_t hash[16];
    md5_raw(bytes, len, hash);
    free(bytes);
    char hex[33];
    bytes_to_hex(hash, 16, hex);
    return march_string_lit(hex, 32);
}

/* ── march_hmac_sha256 ───────────────────────────────────────────────── */

/* Takes key:String, msg:String, returns Result(Bytes, String) */
void *march_hmac_sha256(void *key, void *msg) {
    size_t klen, mlen;
    uint8_t *kbytes = string_to_raw(key, &klen);
    uint8_t *mbytes = string_to_raw(msg, &mlen);
    uint8_t out[32];
    do_hmac_sha256(kbytes, klen, mbytes, mlen, out);
    free(kbytes); free(mbytes);
    void *bval = bytes_from_raw(out, 32);
    return make_ok(bval);
}

/* ── march_hmac_sha256_bytes ─────────────────────────────────────────── */

/* Takes key:Bytes, msg:Bytes, returns bare Bytes (raw 32-byte MAC).
 * Bytes-domain variant for HKDF-style constructions where the key is
 * raw key material that must never round-trip through a String. */
void *march_hmac_sha256_bytes(void *key, void *msg) {
    size_t klen, mlen;
    uint8_t *kbytes = bytes_to_raw(key, &klen);
    uint8_t *mbytes = bytes_to_raw(msg, &mlen);
    uint8_t out[32];
    do_hmac_sha256(kbytes, klen, mbytes, mlen, out);
    free(kbytes); free(mbytes);
    return bytes_from_raw(out, 32);
}

/* ── march_pbkdf2_sha256 ─────────────────────────────────────────────── */

/* Takes pass:String, salt:Bytes, iters:Int, dklen:Int.
 * Returns Result(Bytes, String). */
void *march_pbkdf2_sha256(void *pass, void *salt, int64_t iters, int64_t dklen) {
    if (dklen <= 0 || dklen > 1024 || iters <= 0) {
        return make_err_str("pbkdf2_sha256: invalid parameters");
    }
    size_t plen, slen;
    uint8_t *pbytes = string_to_raw(pass, &plen);
    uint8_t *sbytes = bytes_to_raw(salt, &slen);
    uint8_t *dk = malloc((size_t)dklen);
    do_pbkdf2_sha256(pbytes, plen, sbytes, slen, (uint64_t)iters, (uint32_t)dklen, dk);
    free(pbytes); free(sbytes);
    void *bval = bytes_from_raw(dk, (size_t)dklen);
    free(dk);
    return make_ok(bval);
}

/* ── march_base64_encode ─────────────────────────────────────────────── */

/* Takes Bytes or String, returns String (base64 encoded). */
void *march_base64_encode(void *input) {
    size_t len;
    uint8_t *raw;
    int64_t field8 = *(int64_t *)((char *)input + 8);
    if ((uint32_t)field8 == 0 && (uint32_t)(field8 >> 32) == 0)
        raw = bytes_to_raw(input, &len);
    else
        raw = string_to_raw(input, &len);

    size_t out_sz = ((len + 2) / 3) * 4 + 2;
    char *out_buf = malloc(out_sz);
    int written = base64_encode(raw, len, out_buf, out_sz);
    free(raw);
    if (written < 0) { free(out_buf); return march_string_lit("", 0); }
    void *s = march_string_lit(out_buf, (int64_t)written);
    free(out_buf);
    return s;
}

/* ── march_base64_decode ─────────────────────────────────────────────── */

/* Takes String (base64), returns Result(Bytes, String) — must match the
 * `base64_decode`/`stdlib_base64_decode` builtin type in typecheck.ml and
 * llvm_emit.ml.  This previously built Option(Bytes) (make_some/make_none),
 * whose ctor tags read back inverted under Result (Some=1=Err, None=0=Ok),
 * so every compiled decode "failed" with Err of garbage. */
void *march_base64_decode(void *str) {
    pthread_once(&b64_decode_init_once, b64_decode_init);
    march_string *ms = (march_string *)str;
    const uint8_t *src = (const uint8_t *)ms->data;
    size_t slen = (size_t)ms->len;

    /* Decode: ignore whitespace, stop at padding */
    uint8_t *out = malloc(slen);
    size_t out_i = 0;
    uint32_t buf = 0; int bits = 0;
    for (size_t i = 0; i < slen; i++) {
        int v = b64_decode_table[src[i]];
        if (v == -1) { free(out); return make_err_str("base64_decode: invalid character"); }
        if (v == -2) break; /* padding */
        buf = (buf << 6) | (uint32_t)v;
        bits += 6;
        if (bits >= 8) {
            bits -= 8;
            out[out_i++] = (uint8_t)(buf >> bits);
            buf &= (1u << bits) - 1;
        }
    }
    void *bval = bytes_from_raw(out, out_i);
    free(out);
    return make_ok(bval);
}

/* ── march_random_bytes ──────────────────────────────────────────────── */

void *march_random_bytes(int64_t n) {
    if (n <= 0) return bytes_from_raw(NULL, 0);
    uint8_t *buf = malloc((size_t)n);
    platform_random_bytes(buf, (size_t)n);
    void *result = bytes_from_raw(buf, (size_t)n);
    free(buf);
    return result;
}

/* ── march_uuid_v4 ───────────────────────────────────────────────────── */

void *march_uuid_v4(void) {
    uint8_t b[16];
    platform_random_bytes(b, 16);
    b[6] = (b[6] & 0x0f) | 0x40; /* version 4 */
    b[8] = (b[8] & 0x3f) | 0x80; /* variant */
    char s[37];
    snprintf(s, 37,
        "%02x%02x%02x%02x-%02x%02x-%02x%02x-%02x%02x-%02x%02x%02x%02x%02x%02x",
        b[0],b[1],b[2],b[3], b[4],b[5], b[6],b[7],
        b[8],b[9], b[10],b[11],b[12],b[13],b[14],b[15]);
    return march_string_lit(s, 36);
}

/* ── Vault ─────────────────────────────────────────────────────────────── */

#define VAULT_BUCKETS 512

typedef struct vault_node {
    char             *key;        /* C string (malloc'd copy) */
    void             *value;      /* March heap value (RC managed) */
    int64_t           expires_ms; /* 0 = no expiry */
    struct vault_node *next;
} vault_node;

typedef struct {
    pthread_mutex_t mutex;
    vault_node     *buckets[VAULT_BUCKETS];
    int64_t         count;
} vault_data;

/* Named vault registry */
typedef struct vault_reg_entry {
    char                  *name;
    void                  *handle; /* March heap object */
    struct vault_reg_entry *next;
} vault_reg_entry;

static vault_reg_entry  *vault_registry       = NULL;
static pthread_mutex_t   vault_registry_mutex = PTHREAD_MUTEX_INITIALIZER;

static uint32_t vault_hash(const char *s) {
    uint32_t h = 2166136261u;
    while (*s) { h ^= (uint8_t)*s++; h *= 16777619u; }
    return h % VAULT_BUCKETS;
}

static int64_t vault_now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000LL + (int64_t)(ts.tv_nsec / 1000000);
}

/* Convert a March string value to a C string key.
 * The key is always a march_string* — cast directly to read its content.
 * Previously this called march_value_to_string() which reads the len field
 * as a tag (int32_t), returning "#<tag:N>" for all strings of length N,
 * causing all same-length keys to collide in the vault. */
static char *vault_key_cstr(void *key) {
    march_string *ms = (march_string *)key;
    char *buf = malloc((size_t)ms->len + 1);
    memcpy(buf, ms->data, (size_t)ms->len);
    buf[ms->len] = '\0';
    return buf;
}

/* Create a new vault_data wrapped in a March heap handle. */
static void *vault_new_handle(void) {
    vault_data *vd = calloc(1, sizeof(vault_data));
    pthread_mutex_init(&vd->mutex, NULL);
    /* Wrap in a March heap object: [rc=1][tag=0][pad=0][ptr_to_vd] */
    void *handle = march_alloc(16 + 8);
    *(void **)((char *)handle + 16) = vd;
    return handle;
}

static vault_data *vault_get_data(void *handle) {
    return *(vault_data **)((char *)handle + 16);
}

/* Find a live entry in vd for the given C string key. */
static vault_node *vault_find(vault_data *vd, const char *key, int64_t now_ms) {
    uint32_t h = vault_hash(key);
    vault_node *n = vd->buckets[h];
    while (n) {
        if (strcmp(n->key, key) == 0) {
            if (n->expires_ms != 0 && now_ms > n->expires_ms) return NULL;
            return n;
        }
        n = n->next;
    }
    return NULL;
}

/* ── march_vault_new ──────────────────────────────────────────────────── */

void *march_vault_new(void *name_val) {
    char *name = vault_key_cstr(name_val);
    pthread_mutex_lock(&vault_registry_mutex);
    /* Check if already registered */
    vault_reg_entry *e = vault_registry;
    while (e) {
        if (strcmp(e->name, name) == 0) {
            void *h = e->handle;
            march_incrc(h);
            pthread_mutex_unlock(&vault_registry_mutex);
            free(name);
            return h;
        }
        e = e->next;
    }
    /* Create new vault */
    void *handle = vault_new_handle();
    vault_reg_entry *ne = malloc(sizeof(vault_reg_entry));
    ne->name   = name;
    ne->handle = handle;
    march_incrc(handle); /* registry holds a ref */
    ne->next   = vault_registry;
    vault_registry = ne;
    pthread_mutex_unlock(&vault_registry_mutex);
    return handle;
}

/* ── march_vault_whereis ──────────────────────────────────────────────── */

void *march_vault_whereis(void *name_val) {
    char *name = vault_key_cstr(name_val);
    pthread_mutex_lock(&vault_registry_mutex);
    vault_reg_entry *e = vault_registry;
    while (e) {
        if (strcmp(e->name, name) == 0) {
            void *h = e->handle;
            march_incrc(h);
            pthread_mutex_unlock(&vault_registry_mutex);
            free(name);
            return make_some(h);
        }
        e = e->next;
    }
    pthread_mutex_unlock(&vault_registry_mutex);
    free(name);
    return make_none();
}

/* ── march_vault_set ──────────────────────────────────────────────────── */

void *march_vault_set(void *handle, void *key_val, void *value) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);
    vault_node *n = vd->buckets[h];
    while (n) {
        if (strcmp(n->key, key) == 0) {
            /* Overwrite */
            march_decrc(n->value);
            march_incrc(value);
            n->value      = value;
            n->expires_ms = 0;
            (void)now;
            pthread_mutex_unlock(&vd->mutex);
            free(key);
            return march_alloc(16); /* Unit */
        }
        n = n->next;
    }
    /* Insert new */
    vault_node *nn = malloc(sizeof(vault_node));
    nn->key        = key;
    nn->expires_ms = 0;
    march_incrc(value);
    nn->value      = value;
    nn->next       = vd->buckets[h];
    vd->buckets[h] = nn;
    vd->count++;
    pthread_mutex_unlock(&vd->mutex);
    return march_alloc(16); /* Unit */
}

/* ── march_vault_set_ttl ─────────────────────────────────────────────── */

void *march_vault_set_ttl(void *handle, void *key_val, void *value, int64_t ttl_secs) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    int64_t expires = vault_now_ms() + ttl_secs * 1000LL;
    pthread_mutex_lock(&vd->mutex);
    vault_node *n = vd->buckets[h];
    while (n) {
        if (strcmp(n->key, key) == 0) {
            march_decrc(n->value);
            march_incrc(value);
            n->value      = value;
            n->expires_ms = expires;
            pthread_mutex_unlock(&vd->mutex);
            free(key);
            return march_alloc(16);
        }
        n = n->next;
    }
    vault_node *nn = malloc(sizeof(vault_node));
    nn->key        = key;
    nn->expires_ms = expires;
    march_incrc(value);
    nn->value      = value;
    nn->next       = vd->buckets[h];
    vd->buckets[h] = nn;
    vd->count++;
    pthread_mutex_unlock(&vd->mutex);
    return march_alloc(16);
}

/* ── march_vault_put_new ──────────────────────────────────────────────── */
/* Atomic insert-if-absent. Returns 1 if this call inserted `value`, 0 if a
 * live entry already existed for `key`. ttl_secs <= 0 means no expiry. The
 * check-and-insert happens under one lock, so concurrent callers racing on the
 * same key cannot both win. Returned as i64 (March Bool ABI). */
int64_t march_vault_put_new(void *handle, void *key_val, void *value, int64_t ttl_secs) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    int64_t now = vault_now_ms();
    int64_t expires = (ttl_secs > 0) ? (now + ttl_secs * 1000LL) : 0;
    pthread_mutex_lock(&vd->mutex);
    vault_node *n = vd->buckets[h];
    while (n) {
        if (strcmp(n->key, key) == 0) {
            if (n->expires_ms == 0 || now <= n->expires_ms) {
                /* live entry already present — do not overwrite */
                pthread_mutex_unlock(&vd->mutex);
                free(key);
                return 0;
            }
            /* expired entry — claim it in place */
            march_decrc(n->value);
            march_incrc(value);
            n->value      = value;
            n->expires_ms = expires;
            pthread_mutex_unlock(&vd->mutex);
            free(key);
            return 1;
        }
        n = n->next;
    }
    /* absent — insert */
    vault_node *nn = malloc(sizeof(vault_node));
    nn->key        = key;
    nn->expires_ms = expires;
    march_incrc(value);
    nn->value      = value;
    nn->next       = vd->buckets[h];
    vd->buckets[h] = nn;
    vd->count++;
    pthread_mutex_unlock(&vd->mutex);
    return 1;
}

/* ── march_vault_incr ─────────────────────────────────────────────────── */
/* Atomic integer add: read-add-write under one lock, returning the new value.
 * A missing, expired, or non-integer entry is treated as 0. March ints are
 * immediate, low-bit tagged ((n<<1)|1), so no refcounting is needed for the
 * stored int; a previously-stored heap value is released if overwritten. Any
 * existing TTL is preserved. Returned as i64 (March Int ABI). */
int64_t march_vault_incr(void *handle, void *key_val, int64_t delta) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);
    vault_node *n = vd->buckets[h];
    while (n) {
        if (strcmp(n->key, key) == 0) {
            int live   = (n->expires_ms == 0 || now <= n->expires_ms);
            int is_int = (((int64_t)n->value) & 1) != 0;
            int64_t cur = (live && is_int) ? (((int64_t)n->value) >> 1) : 0;
            if (live && !is_int) march_decrc(n->value); /* replacing a heap value */
            int64_t nv = cur + delta;
            n->value = (void *)(((uint64_t)nv << 1) | 1u);
            if (!live) n->expires_ms = 0;
            pthread_mutex_unlock(&vd->mutex);
            free(key);
            return nv;
        }
        n = n->next;
    }
    /* absent — insert delta */
    int64_t nv = delta;
    vault_node *nn = malloc(sizeof(vault_node));
    nn->key        = key;
    nn->expires_ms = 0;
    nn->value      = (void *)(((uint64_t)nv << 1) | 1u);
    nn->next       = vd->buckets[h];
    vd->buckets[h] = nn;
    vd->count++;
    pthread_mutex_unlock(&vd->mutex);
    return nv;
}

/* ── march_vault_push_capped ──────────────────────────────────────────── */
/* Atomic bounded list push: append `value` to the March list at `key` (newest
 * at the tail) and keep only the last `max_n` elements, all under one lock.
 * A missing/expired/non-list entry starts from the empty list; max_n <= 0 keeps
 * everything. March list layout: Nil = [hdr], Cons = [hdr][head@16][tail@24],
 * tag@8 (0 = Nil, 1 = Cons). Returns Unit. */
void *march_vault_push_capped(void *handle, void *key_val, void *value, int64_t max_n) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);

    vault_node *match = NULL;
    for (vault_node *p = vd->buckets[h]; p; p = p->next) {
        if (strcmp(p->key, key) == 0) { match = p; break; }
    }
    int live = match && (match->expires_ms == 0 || now <= match->expires_ms);
    void *old_list = live ? match->value : NULL;

    /* Count current elements. */
    int64_t count = 0;
    for (void *c = old_list; c && *(int32_t *)((char *)c + 8) == 1;
         c = *(void **)((char *)c + 24)) count++;

    int64_t total = count + 1;
    int64_t keep  = (max_n > 0 && total > max_n) ? max_n : total;
    int64_t drop  = total - keep;

    /* Collect heads (old, oldest-first) then the appended value. */
    void **arr = malloc((size_t)total * sizeof(void *));
    int64_t idx = 0;
    for (void *c = old_list; c && *(int32_t *)((char *)c + 8) == 1;
         c = *(void **)((char *)c + 24)) {
        arr[idx++] = *(void **)((char *)c + 16);
    }
    arr[count] = value;

    /* Build the kept window [drop .. total-1], head = oldest kept, tail-first.
     * incrc each kept element so the new list owns a reference. */
    void *list = march_alloc(16); /* Nil (tag 0) */
    for (int64_t i = total - 1; i >= drop; i--) {
        march_incrc(arr[i]);
        void *cons = march_alloc(16 + 16);
        *(int32_t *)((char *)cons + 8) = 1; /* Cons */
        *(void **)((char *)cons + 16)  = arr[i];
        *(void **)((char *)cons + 24)  = list;
        list = cons;
    }
    free(arr);

    if (match) {
        /* Release the old value (the live list, or a stale expired one). Its
         * teardown decrc's each old head once: kept heads net zero (we incrc'd
         * them above), dropped heads are freed. */
        march_decrc(match->value);
        match->value = list;
        if (!live) match->expires_ms = 0;
        pthread_mutex_unlock(&vd->mutex);
        free(key);
    } else {
        vault_node *nn = malloc(sizeof(vault_node));
        nn->key        = key; /* ownership transferred */
        nn->expires_ms = 0;
        nn->value      = list;
        nn->next       = vd->buckets[h];
        vd->buckets[h] = nn;
        vd->count++;
        pthread_mutex_unlock(&vd->mutex);
    }
    return march_alloc(16); /* Unit */
}

/* ── march_vault_get ──────────────────────────────────────────────────── */

void *march_vault_get(void *handle, void *key_val) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);
    vault_node *n = vault_find(vd, key, now);
    void *result;
    if (n) {
        march_incrc(n->value);
        result = make_some(n->value);
    } else {
        result = make_none();
    }
    pthread_mutex_unlock(&vd->mutex);
    free(key);
    return result;
}

/* ── march_vault_drop ─────────────────────────────────────────────────── */

void *march_vault_drop(void *handle, void *key_val) {
    vault_data *vd = vault_get_data(handle);
    char *key = vault_key_cstr(key_val);
    uint32_t h = vault_hash(key);
    pthread_mutex_lock(&vd->mutex);
    vault_node **pp = &vd->buckets[h];
    while (*pp) {
        if (strcmp((*pp)->key, key) == 0) {
            vault_node *dead = *pp;
            *pp = dead->next;
            march_decrc(dead->value);
            free(dead->key);
            free(dead);
            vd->count--;
            break;
        }
        pp = &(*pp)->next;
    }
    pthread_mutex_unlock(&vd->mutex);
    free(key);
    return march_alloc(16);
}

/* ── march_vault_update ───────────────────────────────────────────────── */

/* Applies function f to the current value and stores the result. */
void *march_vault_update(void *handle, void *key_val, void *f) {
    /* march_vault_get returns a niche-encoded Option(ptr) — see make_some/
     * make_none above: None = NULL, Some(v) = v itself.  There is no boxed
     * Option wrapper to unpack (no tag word, no separate payload field).
     *
     * `cur` is in Vault's *uniform* slot representation: a heap pointer
     * passes straight through, but a scalar (Int/Bool) is tagged as
     * (n << 1) | 1 the same way any concrete value is boxed when it
     * crosses into a type-erased ptr slot (mirrors rec_field_norm_uniform
     * above for record fields).
     *
     * A closure's apply fn, by contrast, always takes its parameters in
     * their *native* (untagged) representation — only the return value is
     * uniformly boxed to ptr (see the "Closure apply wrappers use the
     * generic ptr ABI" comment in llvm_toplevel.ml's emit_fn). So a tagged
     * scalar must be untagged before it's handed to fn, while a heap
     * pointer passes through unchanged; the closure's return value is
     * already in the same uniform/tagged form Vault stores, so it needs
     * no further conversion before march_vault_set. */
    void *cur = march_vault_get(handle, key_val);
    if (cur != NULL) { /* Some(cur) */
        /* f is a closure: heap object [rc(8)][tag(4)][pad(4)][fn_ptr@16][captures@24...].
         * The apply fn's first parameter is the closure pointer itself (not a
         * separate "env" field) — it loads its own captures from that pointer.
         * Calling convention: fn_ptr(closure, arg). See call_closure_1 and
         * march_http_internal.h's closure_fn_t for the same convention. */
        typedef void *(*fn1_t)(void *, void *);
        fn1_t fn  = *(fn1_t *)((char *)f + 16);
        void *arg = ((intptr_t)cur & 1) ? (void *)(((intptr_t)cur) >> 1) : cur;
        void *new_val = fn(f, arg);
        march_vault_set(handle, key_val, new_val);
        march_decrc(new_val);
    }
    march_decrc(cur);
    return march_alloc(16); /* Unit */
}

/* ── march_vault_size ─────────────────────────────────────────────────── */

int64_t march_vault_size(void *handle) {
    vault_data *vd = vault_get_data(handle);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);
    /* Count live entries */
    int64_t count = 0;
    for (int i = 0; i < VAULT_BUCKETS; i++) {
        vault_node *n = vd->buckets[i];
        while (n) {
            if (n->expires_ms == 0 || now <= n->expires_ms) count++;
            n = n->next;
        }
    }
    pthread_mutex_unlock(&vd->mutex);
    return count;
}

/* ── march_vault_keys ─────────────────────────────────────────────────── */

void *march_vault_keys(void *handle) {
    vault_data *vd = vault_get_data(handle);
    int64_t now = vault_now_ms();
    pthread_mutex_lock(&vd->mutex);
    /* Build a March List of key strings */
    void *list = march_alloc(16); /* Nil */
    for (int i = VAULT_BUCKETS - 1; i >= 0; i--) {
        vault_node *n = vd->buckets[i];
        while (n) {
            if (n->expires_ms == 0 || now <= n->expires_ms) {
                void *ks = march_string_lit(n->key, (int64_t)strlen(n->key));
                /* Cons(ks, list): [rc=1][tag=1][pad=0][ks][list] */
                void *cons = march_alloc(16 + 16);
                *(int32_t *)((char *)cons + 8)  = 1; /* Cons */
                *(void **)((char *)cons + 16)   = ks;
                *(void **)((char *)cons + 24)   = list;
                list = cons;
            }
            n = n->next;
        }
    }
    pthread_mutex_unlock(&vd->mutex);
    return list;
}

/* ── Vault string-namespace helpers ──────────────────────────────────────
 * These accept a String namespace name instead of a vault table handle.
 * The vault is auto-created (or found) by name via march_vault_new, which is
 * idempotent — safe to call on every operation.  This supports the pattern:
 *   ptype VaultStorage = { ns : String }
 *   Vault.ns_set(self.ns, key, value)
 *   Vault.ns_get(self.ns, key)
 * without requiring the caller to explicitly hold a table handle. */

void *march_vault_ns_set(void *ns_val, void *key_val, void *value) {
    void *handle = march_vault_new(ns_val);
    void *result = march_vault_set(handle, key_val, value);
    march_decrc(handle);
    return result;
}

void *march_vault_ns_get(void *ns_val, void *key_val) {
    /* Use whereis to avoid creating a vault on every read — return None if
     * the namespace doesn't exist yet. */
    char *name = vault_key_cstr(ns_val);
    pthread_mutex_lock(&vault_registry_mutex);
    vault_reg_entry *e = vault_registry;
    while (e) {
        if (strcmp(e->name, name) == 0) {
            void *h = e->handle;
            march_incrc(h);
            pthread_mutex_unlock(&vault_registry_mutex);
            free(name);
            void *result = march_vault_get(h, key_val);
            march_decrc(h);
            return result;
        }
        e = e->next;
    }
    pthread_mutex_unlock(&vault_registry_mutex);
    free(name);
    /* Namespace doesn't exist — return None (boxed: tag=0) */
    void *none = march_alloc(16);
    *(int32_t *)((char *)none + 8) = 0;
    return none;
}

void *march_vault_ns_drop(void *ns_val, void *key_val) {
    char *name = vault_key_cstr(ns_val);
    pthread_mutex_lock(&vault_registry_mutex);
    vault_reg_entry *e = vault_registry;
    void *found = NULL;
    while (e) {
        if (strcmp(e->name, name) == 0) {
            found = e->handle;
            march_incrc(found);
            break;
        }
        e = e->next;
    }
    pthread_mutex_unlock(&vault_registry_mutex);
    free(name);
    if (!found) return march_alloc(16); /* Unit */
    void *result = march_vault_drop(found, key_val);
    march_decrc(found);
    return result;
}

/* ── System builtins ──────────────────────────────────────────────────── */

static int64_t march_start_ms = 0;
static pthread_once_t march_start_once = PTHREAD_ONCE_INIT;

static void init_start_time(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    march_start_ms = (int64_t)ts.tv_sec * 1000LL + (int64_t)(ts.tv_nsec / 1000000);
}

int64_t march_sys_uptime_ms(void) {
    pthread_once(&march_start_once, init_start_time);
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    int64_t now = (int64_t)ts.tv_sec * 1000LL + (int64_t)(ts.tv_nsec / 1000000);
    return now - march_start_ms;
}

int64_t march_sys_cpu_count(void) {
#ifdef __APPLE__
    int n = 0;
    size_t sz = sizeof(n);
    sysctlbyname("hw.logicalcpu", &n, &sz, NULL, 0);
    return n > 0 ? (int64_t)n : 1;
#else
    long n = sysconf(_SC_NPROCESSORS_ONLN);
    return n > 0 ? (int64_t)n : 1;
#endif
}

/* 1-minute load average × 1000 (integer millis); 0 if unavailable.
 * getloadavg() is available on both macOS and Linux (declared in <stdlib.h>). */
int64_t march_sys_cpu_load_milli(void) {
    double avg[3];
    if (getloadavg(avg, 1) < 1) return 0;
    if (avg[0] < 0.0) return 0;
    return (int64_t)(avg[0] * 1000.0);
}

/* Total physical memory in bytes; 0 if unavailable. */
int64_t march_sys_mem_total_bytes(void) {
#ifdef __APPLE__
    int64_t mem = 0;
    size_t sz = sizeof(mem);
    if (sysctlbyname("hw.memsize", &mem, &sz, NULL, 0) != 0) return 0;
    return mem;
#else
    struct sysinfo info;
    if (sysinfo(&info) != 0) return 0;
    return (int64_t)info.totalram * (int64_t)info.mem_unit;
#endif
}

/* Available (free + reclaimable) memory in bytes; 0 if unavailable. */
int64_t march_sys_mem_available_bytes(void) {
#ifdef __APPLE__
    mach_port_t host = mach_host_self();
    vm_size_t page_size = 0;
    if (host_page_size(host, &page_size) != KERN_SUCCESS) return 0;
    vm_statistics64_data_t vmstat;
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    if (host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vmstat, &count) != KERN_SUCCESS)
        return 0;
    uint64_t avail_pages = (uint64_t)vmstat.free_count
                         + (uint64_t)vmstat.inactive_count
                         + (uint64_t)vmstat.purgeable_count;
    return (int64_t)(avail_pages * (uint64_t)page_size);
#else
    /* Prefer MemAvailable from /proc/meminfo; fall back to sysinfo freeram. */
    FILE *f = fopen("/proc/meminfo", "r");
    if (f) {
        char line[256];
        while (fgets(line, sizeof(line), f)) {
            unsigned long kb;
            if (sscanf(line, "MemAvailable: %lu kB", &kb) == 1) {
                fclose(f);
                return (int64_t)kb * 1024;
            }
        }
        fclose(f);
    }
    struct sysinfo info;
    if (sysinfo(&info) != 0) return 0;
    return (int64_t)info.freeram * (int64_t)info.mem_unit;
#endif
}

int64_t march_sys_heap_bytes(void) {
    /* No heap introspection; return 0 */
    return 0;
}

int64_t march_sys_word_size(void) {
    return (int64_t)sizeof(void *);
}

int64_t march_sys_minor_gcs(void) { return 0; }
int64_t march_sys_major_gcs(void) { return 0; }

/* Actor count is maintained by the scheduler; stub returns 0 */
int64_t march_sys_actor_count(void) { return 0; }

/* ── march_get_version ────────────────────────────────────────────────── */

void *march_get_version(void) {
    static const char *ver = "march/dev";
    return march_string_lit(ver, (int64_t)strlen(ver));
}

/* ── Session-typed channel runtime ──────────────────────────────────────── *
 *
 * Binary channels: two endpoints share a pair of queues.  Endpoint A sends
 * into queue_ab and receives from queue_ba; endpoint B is the mirror.
 *
 * Each queue is a simple singly-linked list protected by a mutex (channels
 * are also used across actor green threads).
 *
 * Endpoint layout (March heap object, tag = 0, 3 fields):
 *   field 0 (i64): pair pointer (cast to intptr_t — opaque to March GC)
 *   field 1 (i64): role index (0 = A, 1 = B)
 *   field 2 (i64): closed flag (0 = open, 1 = closed)
 *
 * Chan.new returns a 2-tuple of endpoints.
 * Chan.send / Chan.recv / Chan.close return new endpoint objects (linear
 * consumption: old endpoint is freed by Perceus, new one is allocated).
 */

/* ── Queue node ────────────────────────────────────────────────── */

typedef struct march_chan_qnode {
    struct march_chan_qnode *next;
    void *value;   /* RC-owned March value */
} march_chan_qnode;

/* ── Shared channel pair ───────────────────────────────────────── */

typedef struct {
    pthread_mutex_t lock;
    /* queue A→B (A sends, B receives) */
    march_chan_qnode *ab_head;
    march_chan_qnode *ab_tail;
    /* queue B→A */
    march_chan_qnode *ba_head;
    march_chan_qnode *ba_tail;
    int64_t refcount;  /* 2 when both endpoints alive; freed at 0 */
} march_chan_pair;

static march_chan_pair *chan_pair_new(void) {
    march_chan_pair *p = (march_chan_pair *)calloc(1, sizeof(march_chan_pair));
    pthread_mutex_init(&p->lock, NULL);
    p->refcount = 2;
    return p;
}

static void chan_pair_release(march_chan_pair *p) {
    int64_t rc = __sync_sub_and_fetch(&p->refcount, 1);
    if (rc <= 0) {
        /* Free any remaining queued values. */
        for (march_chan_qnode *n = p->ab_head; n; ) {
            march_chan_qnode *next = n->next;
            march_decrc(n->value);
            free(n);
            n = next;
        }
        for (march_chan_qnode *n = p->ba_head; n; ) {
            march_chan_qnode *next = n->next;
            march_decrc(n->value);
            free(n);
            n = next;
        }
        pthread_mutex_destroy(&p->lock);
        free(p);
    }
}

static void chan_enqueue(march_chan_pair *p, int64_t role, void *val) {
    march_chan_qnode *node = (march_chan_qnode *)malloc(sizeof(march_chan_qnode));
    node->next = NULL;
    node->value = val;
    pthread_mutex_lock(&p->lock);
    if (role == 0) {
        /* A sends into ab queue */
        if (p->ab_tail) { p->ab_tail->next = node; p->ab_tail = node; }
        else            { p->ab_head = p->ab_tail = node; }
    } else {
        /* B sends into ba queue */
        if (p->ba_tail) { p->ba_tail->next = node; p->ba_tail = node; }
        else            { p->ba_head = p->ba_tail = node; }
    }
    pthread_mutex_unlock(&p->lock);
}

static void *chan_dequeue(march_chan_pair *p, int64_t role) {
    march_chan_qnode *node = NULL;
    pthread_mutex_lock(&p->lock);
    if (role == 0) {
        /* A receives from ba queue */
        node = p->ba_head;
        if (node) {
            p->ba_head = node->next;
            if (!p->ba_head) p->ba_tail = NULL;
        }
    } else {
        /* B receives from ab queue */
        node = p->ab_head;
        if (node) {
            p->ab_head = node->next;
            if (!p->ab_head) p->ab_tail = NULL;
        }
    }
    pthread_mutex_unlock(&p->lock);
    if (!node) {
        /* Protocol violation at runtime: recv on empty queue.
         * The type checker should have prevented this; crash hard. */
        fprintf(stderr, "march: Chan.recv on empty channel queue (role %lld)\n",
                (long long)role);
        abort();
    }
    void *val = node->value;
    free(node);
    return val;
}

/* ── Helpers to build / read endpoint heap objects ─────────────── */

static void *chan_make_endpoint(march_chan_pair *pair, int64_t role, int64_t closed) {
    /* 3-field heap object: (pair_ptr, role, closed) */
    void *ep = march_alloc(16 + 3 * 8);  /* hdr(16) + 3 fields */
    int64_t *fields = (int64_t *)((char *)ep + 16);
    fields[0] = (int64_t)(intptr_t)pair;
    fields[1] = role;
    fields[2] = closed;
    return ep;
}

#define EP_PAIR(ep)   ((march_chan_pair *)(intptr_t)(((int64_t *)((char *)(ep) + 16))[0]))
#define EP_ROLE(ep)   (((int64_t *)((char *)(ep) + 16))[1])
#define EP_CLOSED(ep) (((int64_t *)((char *)(ep) + 16))[2])

/* ── Public API ────────────────────────────────────────────────── */

/* Chan.new(proto_name_string) → (endpoint_a, endpoint_b) as 2-tuple */
void *march_chan_new(void *proto_name) {
    (void)proto_name;  /* protocol name is for diagnostics; unused at native runtime */
    march_chan_pair *pair = chan_pair_new();
    void *ep_a = chan_make_endpoint(pair, 0, 0);
    void *ep_b = chan_make_endpoint(pair, 1, 0);
    /* Build a 2-tuple: hdr(16) + 2 fields */
    void *tup = march_alloc(16 + 2 * 8);
    int64_t *tfields = (int64_t *)((char *)tup + 16);
    tfields[0] = (int64_t)(intptr_t)ep_a;
    tfields[1] = (int64_t)(intptr_t)ep_b;
    return tup;
}

/* Chan.send(endpoint, value) → new_endpoint
 * Enqueues value into the send queue; returns a fresh endpoint (linear). */
void *march_chan_send(void *ep, void *val) {
    march_chan_pair *pair = EP_PAIR(ep);
    int64_t role = EP_ROLE(ep);
    chan_enqueue(pair, role, val);
    /* Return a new endpoint that continues the session.
     * The pair refcount stays the same — old endpoint will be freed by Perceus,
     * but we bump the pair refcount to account for the new endpoint. */
    __sync_add_and_fetch(&pair->refcount, 1);
    void *new_ep = chan_make_endpoint(pair, role, 0);
    /* Release the old endpoint's share */
    chan_pair_release(pair);
    return new_ep;
}

/* Chan.recv(endpoint) → (value, new_endpoint) as 2-tuple */
void *march_chan_recv(void *ep) {
    march_chan_pair *pair = EP_PAIR(ep);
    int64_t role = EP_ROLE(ep);
    void *val = chan_dequeue(pair, role);
    __sync_add_and_fetch(&pair->refcount, 1);
    void *new_ep = chan_make_endpoint(pair, role, 0);
    chan_pair_release(pair);
    /* Build (value, new_endpoint) tuple */
    void *tup = march_alloc(16 + 2 * 8);
    int64_t *tfields = (int64_t *)((char *)tup + 16);
    tfields[0] = (int64_t)(intptr_t)val;
    tfields[1] = (int64_t)(intptr_t)new_ep;
    return tup;
}

/* Chan.close(endpoint) → Unit (i64 0) */
int64_t march_chan_close(void *ep) {
    march_chan_pair *pair = EP_PAIR(ep);
    chan_pair_release(pair);
    return 0;  /* Unit */
}

/* Chan.choose(endpoint, label_atom) → new_endpoint
 * Sends the label to the other side (same as send). */
void *march_chan_choose(void *ep, void *label) {
    return march_chan_send(ep, label);
}

/* Chan.offer(endpoint) → (label_atom, new_endpoint) as 2-tuple
 * Receives the label from the other side (same as recv). */
void *march_chan_offer(void *ep) {
    return march_chan_recv(ep);
}

/* ── Multi-party session types (MPST) ──────────────────────────────────── *
 *
 * MPST extends binary channels to N roles.  Each role has a directed queue
 * to every other role: role_i→role_j uses queue[i*N + j].
 *
 * Shared session structure holds N*N queues (only N*(N-1) used; diagonal unused).
 *
 * MPST endpoint layout (March heap object, tag = 0, 3 fields):
 *   field 0 (i64): session pointer (cast to intptr_t)
 *   field 1 (i64): role index (0..N-1)
 *   field 2 (i64): closed flag
 */

#define MPST_MAX_ROLES 16

typedef struct {
    pthread_mutex_t lock;
    int64_t n_roles;
    char *role_names[MPST_MAX_ROLES];   /* role index → name (malloc'd copy) */
    march_chan_qnode **queues;  /* n_roles * n_roles array of queue heads */
    march_chan_qnode **tails;   /* corresponding tails */
    int64_t refcount;          /* N when all endpoints alive */
} march_mpst_session;

static march_mpst_session *mpst_session_new(int64_t n_roles) {
    march_mpst_session *s = (march_mpst_session *)calloc(1, sizeof(march_mpst_session));
    pthread_mutex_init(&s->lock, NULL);
    s->n_roles = n_roles;
    int64_t n2 = n_roles * n_roles;
    s->queues = (march_chan_qnode **)calloc((size_t)n2, sizeof(march_chan_qnode *));
    s->tails  = (march_chan_qnode **)calloc((size_t)n2, sizeof(march_chan_qnode *));
    s->refcount = n_roles;
    return s;
}

/* Resolve a March string (march_string *) role name to an index.
 * If the name hasn't been seen, register it at the next index. */
static int64_t mpst_resolve_role(march_mpst_session *s, void *role_str) {
    march_string *ms = (march_string *)role_str;
    for (int64_t i = 0; i < s->n_roles; i++) {
        if (s->role_names[i] &&
            (int64_t)strlen(s->role_names[i]) == ms->len &&
            memcmp(s->role_names[i], ms->data, (size_t)ms->len) == 0) {
            return i;
        }
    }
    /* Name not found — this shouldn't happen for well-typed programs.
     * Search for first empty slot. */
    for (int64_t i = 0; i < s->n_roles; i++) {
        if (!s->role_names[i]) {
            s->role_names[i] = (char *)malloc((size_t)(ms->len + 1));
            memcpy(s->role_names[i], ms->data, (size_t)ms->len);
            s->role_names[i][ms->len] = '\0';
            return i;
        }
    }
    fprintf(stderr, "march: MPST role '%.*s' not found and no slots available\n",
            (int)ms->len, ms->data);
    abort();
}

static void mpst_session_release(march_mpst_session *s) {
    int64_t rc = __sync_sub_and_fetch(&s->refcount, 1);
    if (rc <= 0) {
        int64_t n2 = s->n_roles * s->n_roles;
        for (int64_t i = 0; i < n2; i++) {
            for (march_chan_qnode *n = s->queues[i]; n; ) {
                march_chan_qnode *next = n->next;
                march_decrc(n->value);
                free(n);
                n = next;
            }
        }
        for (int64_t i = 0; i < s->n_roles; i++) {
            free(s->role_names[i]);
        }
        free(s->queues);
        free(s->tails);
        pthread_mutex_destroy(&s->lock);
        free(s);
    }
}

static void mpst_enqueue(march_mpst_session *s, int64_t from, int64_t to, void *val) {
    int64_t idx = from * s->n_roles + to;
    march_chan_qnode *node = (march_chan_qnode *)malloc(sizeof(march_chan_qnode));
    node->next = NULL;
    node->value = val;
    pthread_mutex_lock(&s->lock);
    if (s->tails[idx]) { s->tails[idx]->next = node; s->tails[idx] = node; }
    else               { s->queues[idx] = s->tails[idx] = node; }
    pthread_mutex_unlock(&s->lock);
}

static void *mpst_dequeue(march_mpst_session *s, int64_t from, int64_t to) {
    int64_t idx = from * s->n_roles + to;
    march_chan_qnode *node = NULL;
    pthread_mutex_lock(&s->lock);
    node = s->queues[idx];
    if (node) {
        s->queues[idx] = node->next;
        if (!s->queues[idx]) s->tails[idx] = NULL;
    }
    pthread_mutex_unlock(&s->lock);
    if (!node) {
        fprintf(stderr, "march: MPST.recv on empty queue (from=%lld, to=%lld)\n",
                (long long)from, (long long)to);
        abort();
    }
    void *val = node->value;
    free(node);
    return val;
}

static void *mpst_make_endpoint(march_mpst_session *session, int64_t role, int64_t closed) {
    void *ep = march_alloc(16 + 3 * 8);
    int64_t *fields = (int64_t *)((char *)ep + 16);
    fields[0] = (int64_t)(intptr_t)session;
    fields[1] = role;
    fields[2] = closed;
    return ep;
}

#define MPST_SESSION(ep) ((march_mpst_session *)(intptr_t)(((int64_t *)((char *)(ep) + 16))[0]))
#define MPST_ROLE(ep)    (((int64_t *)((char *)(ep) + 16))[1])

/* Pre-register role names into session->role_names[i] in the given order.
 * [roles_csv] is a March string of comma-separated role names in the SAME
 * (role-name-sorted) order as the endpoint tuple positions, e.g.
 * "Client,Logger,Server".  This makes mpst_resolve_role(name) return the
 * fixed positional index that matches each endpoint's role index, instead of
 * the fragile first-encounter order.  A NULL / empty string leaves the table
 * all-NULL and falls back to lazy first-encounter registration. */
static void mpst_register_roles(march_mpst_session *s, void *roles_csv) {
    if (!roles_csv) return;
    march_string *ms = (march_string *)roles_csv;
    if (ms->len <= 0) return;
    const char *p = ms->data;
    const char *end = ms->data + ms->len;
    int64_t idx = 0;
    while (p < end && idx < s->n_roles) {
        const char *start = p;
        while (p < end && *p != ',') p++;
        int64_t len = (int64_t)(p - start);
        s->role_names[idx] = (char *)malloc((size_t)(len + 1));
        memcpy(s->role_names[idx], start, (size_t)len);
        s->role_names[idx][len] = '\0';
        idx++;
        if (p < end) p++;  /* skip the comma */
    }
}

/* MPST.new(proto_name, n_roles, roles_csv) → flat N-tuple of endpoints.
 * For N roles, returns a tuple (ep_0, ep_1, ..., ep_{N-1}) whose positions
 * match the role-name-sorted order of [roles_csv].  Endpoint i carries role
 * index i, and role_names[i] is pre-registered from [roles_csv] so that
 * name-based routing in send/recv lines up with the tuple positions. */
void *march_mpst_new(void *proto_name, int64_t n_roles, void *roles_csv) {
    (void)proto_name;
    march_mpst_session *session = mpst_session_new(n_roles);
    mpst_register_roles(session, roles_csv);
    /* Build a flat N-tuple: hdr(16) + n_roles fields (tag 0, like march_chan_new). */
    void *tup = march_alloc(16 + n_roles * 8);
    int64_t *fields = (int64_t *)((char *)tup + 16);
    for (int64_t i = 0; i < n_roles; i++)
        fields[i] = (int64_t)(intptr_t)mpst_make_endpoint(session, i, 0);
    return tup;
}

/* MPST.send(endpoint, target_role_name_string, value) → new_endpoint */
void *march_mpst_send(void *ep, void *target_role_str, void *val) {
    march_mpst_session *session = MPST_SESSION(ep);
    int64_t my_role = MPST_ROLE(ep);
    int64_t target_role = mpst_resolve_role(session, target_role_str);
    mpst_enqueue(session, my_role, target_role, val);
    __sync_add_and_fetch(&session->refcount, 1);
    void *new_ep = mpst_make_endpoint(session, my_role, 0);
    mpst_session_release(session);
    return new_ep;
}

/* MPST.recv(endpoint, source_role_name_string) → (value, new_endpoint) */
void *march_mpst_recv(void *ep, void *source_role_str) {
    march_mpst_session *session = MPST_SESSION(ep);
    int64_t my_role = MPST_ROLE(ep);
    int64_t source_role = mpst_resolve_role(session, source_role_str);
    void *val = mpst_dequeue(session, source_role, my_role);
    __sync_add_and_fetch(&session->refcount, 1);
    void *new_ep = mpst_make_endpoint(session, my_role, 0);
    mpst_session_release(session);
    void *tup = march_alloc(16 + 2 * 8);
    int64_t *tfields = (int64_t *)((char *)tup + 16);
    tfields[0] = (int64_t)(intptr_t)val;
    tfields[1] = (int64_t)(intptr_t)new_ep;
    return tup;
}

/* MPST.close(endpoint) → Unit */
int64_t march_mpst_close(void *ep) {
    march_mpst_session *session = MPST_SESSION(ep);
    mpst_session_release(session);
    return 0;
}

/* ── String.from_codepoint: encode Unicode codepoint as UTF-8 ────────── */

/* Encode a Unicode codepoint as UTF-8. Returns a March string (or None tag).
 * Validates: 0x0 ≤ cp ≤ 0x10FFFF and rejects surrogate pairs (0xD800-0xDFFF).
 * Returns: Some(utf8_string) or None (as a March option value). */
void *march_codepoint_to_utf8(int64_t cp) {
    /* Validate codepoint range */
    if (cp < 0 || cp > 0x10FFFF) {
        return march_alloc(16);  /* None: tag = 0, rc = 1 */
    }

    /* Reject surrogate pairs */
    if (cp >= 0xD800 && cp <= 0xDFFF) {
        return march_alloc(16);  /* None */
    }

    unsigned char buf[4];
    int len = 0;

    if (cp <= 0x7F) {
        /* 1-byte sequence: 0xxxxxxx */
        buf[0] = (unsigned char)cp;
        len = 1;
    } else if (cp <= 0x7FF) {
        /* 2-byte sequence: 110xxxxx 10xxxxxx */
        buf[0] = (unsigned char)(0xC0 | (cp >> 6));
        buf[1] = (unsigned char)(0x80 | (cp & 0x3F));
        len = 2;
    } else if (cp <= 0xFFFF) {
        /* 3-byte sequence: 1110xxxx 10xxxxxx 10xxxxxx */
        buf[0] = (unsigned char)(0xE0 | (cp >> 12));
        buf[1] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
        buf[2] = (unsigned char)(0x80 | (cp & 0x3F));
        len = 3;
    } else {
        /* 4-byte sequence: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx */
        buf[0] = (unsigned char)(0xF0 | (cp >> 18));
        buf[1] = (unsigned char)(0x80 | ((cp >> 12) & 0x3F));
        buf[2] = (unsigned char)(0x80 | ((cp >> 6) & 0x3F));
        buf[3] = (unsigned char)(0x80 | (cp & 0x3F));
        len = 4;
    }

    /* Create March string from UTF-8 bytes */
    march_string *s = march_string_alloc(len);
    memcpy(s->data, buf, (size_t)len);
    s->data[len] = '\0';

    /* Wrap in Some(...) constructor: tag = 1, rc = 1, payload = string pointer */
    void *opt = march_alloc(16 + 8);
    march_hdr *hdr = (march_hdr *)opt;
    hdr->tag = 1;  /* Some tag */
    int64_t *payload = (int64_t *)((char *)opt + 16);
    payload[0] = (int64_t)(intptr_t)s;
    return opt;
}

/* ── REPL JIT persistent variable slot table ──────────────────────────────
 *
 * Each REPL variable (let x = ..., fn f = ...) is assigned a slot index at
 * declaration time.  All slots are unified int64_t: scalars (Int/Bool/Float)
 * are stored as raw bits, heap pointers are stored as intptr_t casts.
 *
 * This replaces the old "emit_prev_global_bridges" mechanism that declared
 * REPL globals as LLVM external symbols and relied on RTLD_GLOBAL resolution
 * across .so fragment boundaries — a design that leaked OCaml tagged-integer
 * representations whenever the interpreter was involved.  With slots, all
 * values live in a single persistent C array visible to every JIT fragment
 * without any cross-.so symbol resolution.
 */
#define MARCH_REPL_NSLOTS 4096
static int64_t march_repl_slots[MARCH_REPL_NSLOTS];

int64_t march_repl_get(int64_t slot) {
    return march_repl_slots[(size_t)slot];
}

void march_repl_set(int64_t slot, int64_t val) {
    march_repl_slots[(size_t)slot] = val;
}

/* ── Record shape registry + record introspection builtins ───────────────
 *
 * Native records are heap cells with tag 0 and fields stored SORTED BY NAME
 * at offsets 16 + i*8 — but the cell itself carries no field names.  To make
 * the record introspection builtins (record_keys/values/entries/get/put/
 * has_key/from_list) work natively, the compiler stores a SHAPE ID in the
 * otherwise-unused header pad word (march_hdr.pad, offset 12; march_alloc
 * zeroes it, so legacy/C-built cells read as shape 0 = "no metadata").
 *
 * A shape is interned from a canonical descriptor string:
 *
 *     "name:k;name:k;...;"      (names sorted ascending, k = field kind)
 *
 * Field kinds describe the natural in-slot representation:
 *     'i'  Int/Bool/Unit/Atom — raw int64_t
 *     'f'  Float              — raw double bits
 *     'p'  heap pointer       — String/ADT/tuple/record/closure
 *     'g'  generic/unknown    — bits as received from a type-erased context
 *
 * Value conventions at the builtin boundaries (must match llvm_emit.ml):
 *   - OUT into ANY ptr-sized generic slot (List payload, Option Some payload,
 *     record_entries pair snd, dynamic field reads): the UNIFORM convention —
 *     'i' fields are low-bit tagged ((n<<1)|1) because compiled code reads
 *     generic ctor AND tuple slots as ptr and untags scalar views
 *     conditionally (ashr iff odd); 'f' raw double bits; 'p'/'g' bits as-is.
 *     Compiled tuple slots are uniform too (ETuple stores scalars through
 *     coerce i64→ptr = tag), so pair snd MUST be tagged, not natural.
 *   - IN (record_put value): UNIFORM repr with an explicit kind argument
 *     supplied by the call site (the EApp special case tags scalar i64s;
 *     natural repr would make an even Int >= 4096 indistinguishable from a
 *     heap pointer).  An even plausible-heap value under a scalar kind means
 *     the static type lied (type-erased heterogeneous flow) and the field
 *     kind is downgraded to 'g' so the bits round-trip unmodified.
 *   - IN (record_from_list pair values): UNIFORM repr (the pairs come from
 *     compiled tuple slots / record_entries) — 'i' values are conditionally
 *     untagged to natural before storing.
 *
 * RC contract: arguments are BORROWED (see borrow.ml extern_borrow_table);
 * results are fresh +1.  Any heap value aliased into a result gets incrc'd.
 */

void march_panic(void *s);   /* march_runtime.c */

typedef struct {
    int32_t   nfields;
    char    **names;      /* sorted ascending, NUL-terminated */
    int64_t  *name_lens;
    char     *kinds;      /* one of 'i','f','p','g' per field */
    char     *desc;       /* owned canonical descriptor string */
} march_record_shape;

static march_record_shape **rec_shape_table = NULL;   /* index = id - 1 */
static int32_t rec_shape_count = 0;
static int32_t rec_shape_cap   = 0;
static pthread_mutex_t rec_shape_mu = PTHREAD_MUTEX_INITIALIZER;

static void rec_panic(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    march_panic(s);
}

/* Parse a canonical descriptor into a shape struct (assumes valid input). */
static march_record_shape *rec_shape_parse(const char *desc) {
    march_record_shape *s = calloc(1, sizeof(march_record_shape));
    s->desc = strdup(desc);
    int32_t n = 0;
    for (const char *p = desc; *p; p++) if (*p == ';') n++;
    s->nfields   = n;
    s->names     = calloc(n > 0 ? n : 1, sizeof(char *));
    s->name_lens = calloc(n > 0 ? n : 1, sizeof(int64_t));
    s->kinds     = calloc(n > 0 ? n : 1, 1);
    const char *p = desc;
    for (int32_t i = 0; i < n; i++) {
        const char *colon = strchr(p, ':');
        size_t len = (size_t)(colon - p);
        s->names[i] = malloc(len + 1);
        memcpy(s->names[i], p, len);
        s->names[i][len] = '\0';
        s->name_lens[i] = (int64_t)len;
        s->kinds[i] = colon[1];
        p = colon + 3;            /* skip "k;" */
    }
    return s;
}

/* Intern a descriptor string, returning its shape id (>= 1). */
int32_t march_record_shape_intern(const char *desc) {
    pthread_mutex_lock(&rec_shape_mu);
    for (int32_t i = 0; i < rec_shape_count; i++) {
        if (strcmp(rec_shape_table[i]->desc, desc) == 0) {
            pthread_mutex_unlock(&rec_shape_mu);
            return i + 1;
        }
    }
    if (rec_shape_count == rec_shape_cap) {
        rec_shape_cap = rec_shape_cap ? rec_shape_cap * 2 : 32;
        rec_shape_table = realloc(rec_shape_table,
                                  (size_t)rec_shape_cap * sizeof(*rec_shape_table));
    }
    rec_shape_table[rec_shape_count] = rec_shape_parse(desc);
    int32_t id = ++rec_shape_count;
    pthread_mutex_unlock(&rec_shape_mu);
    return id;
}

/* Called by compiled code after every record allocation.  [cache] is a
 * per-shape module global that memoizes the interned id (benign race: the
 * intern is idempotent). */
void march_record_set_shape(void *rec, const char *desc, int32_t *cache) {
    int32_t id = *cache;
    if (id == 0) { id = march_record_shape_intern(desc); *cache = id; }
    ((march_hdr *)rec)->pad = id;
}

static march_record_shape *rec_shape_of(void *rec) {
    int32_t id = ((march_hdr *)rec)->pad;
    if (id <= 0 || id > rec_shape_count) return NULL;
    return rec_shape_table[id - 1];
}

static int64_t rec_field_raw(void *rec, int32_t i) {
    return *(int64_t *)((char *)rec + 16 + (size_t)i * 8);
}

static void rec_field_set(void *rec, int32_t i, int64_t bits) {
    *(int64_t *)((char *)rec + 16 + (size_t)i * 8) = bits;
}

/* Plausible-heap-pointer test, mirroring IS_HEAP_PTR in march_runtime.c:
 * even, above the first page, positive.  Used to detect statically-typed
 * scalar slots that actually carry a heap pointer (type-erased heterogeneous
 * flows whose static types lie about the runtime value). */
#define REC_PLAUSIBLE_HEAP(bits) \
    ((((uint64_t)(bits)) & 1u) == 0 && (uint64_t)(bits) >= 4096u && (bits) > 0)

/* Field value for ANY generic ptr-sized slot (List payload / Some payload /
 * record_entries pair snd / dynamic field read): the UNIFORM convention —
 * tag ints, raw float bits, incrc heap values. */
static int64_t rec_field_out_adt(void *rec, int32_t i, char kind) {
    int64_t raw = rec_field_raw(rec, i);
    switch (kind) {
    case 'i': return (raw << 1) | 1;
    case 'f': return raw;
    default:  march_incrc((void *)(intptr_t)raw);   /* guarded for 'g' */
              return raw;
    }
}

/* Slot-to-slot copy within record cells (record_put rebuilding a cell):
 * bits verbatim, +1 reference on aliased heap values. */
static int64_t rec_field_copy(void *rec, int32_t i, char kind) {
    int64_t raw = rec_field_raw(rec, i);
    if (kind == 'p' || kind == 'g') march_incrc((void *)(intptr_t)raw);
    return raw;
}

/* Normalize an incoming (bits, kind) pair to the natural slot value and the
 * honest field kind, then take any needed +1 reference.
 *
 *   'i'/'g'  UNIFORM bits (record_put call sites tag scalars, generic paths
 *        and record_from_list pair snd are uniform already): odd = tagged int
 *        (untag to natural, kind 'i'); even = heap pointer or erased raw bits
 *        flowing through a lying static type (store verbatim, kind 'g',
 *        guarded incrc).  Natural repr would be ambiguous here: an even int
 *        >= 4096 is bit-identical to a heap pointer.
 *   'f'  raw double bits.   'p'  heap pointer (+1 ref).
 */
static int64_t rec_field_norm_uniform(int64_t bits, char *kind) {
    if (bits & 1) { *kind = 'i'; return bits >> 1; }      /* tagged int */
    if (REC_PLAUSIBLE_HEAP(bits)) {
        if (*kind != 'p') *kind = 'g';
        march_incrc((void *)(intptr_t)bits);              /* guarded */
        return bits;
    }
    if (*kind != 'g') *kind = 'i';                        /* small even raw */
    return bits;
}

static int64_t rec_field_norm_in(int64_t bits, char *kind) {
    switch (*kind) {
    case 'i':
    case 'g':
        return rec_field_norm_uniform(bits, kind);
    case 'p':
        march_incrc((void *)(intptr_t)bits);
        return bits;
    default:   /* 'f' */
        return bits;
    }
}

static int32_t rec_find_field(march_record_shape *s, const char *name, int64_t len) {
    for (int32_t i = 0; i < s->nfields; i++) {
        if (s->name_lens[i] == len && memcmp(s->names[i], name, (size_t)len) == 0)
            return i;
    }
    return -1;
}

/* List/Option/tuple cell constructors (same layout as compiled allocs). */
static void *rec_nil(void) { return march_alloc(16); }            /* tag 0 */

static void *rec_cons(int64_t head_bits, void *tail) {
    void *c = march_alloc(16 + 16);
    ((march_hdr *)c)->tag = 1;
    *(int64_t *)((char *)c + 16) = head_bits;
    *(void **)((char *)c + 24)   = tail;
    return c;
}

static void *rec_pair(void *fst, int64_t snd_bits) {
    void *t = march_alloc(16 + 16);                                /* tag 0 */
    *(void **)((char *)t + 16)   = fst;
    *(int64_t *)((char *)t + 24) = snd_bits;
    return t;
}

/* rec_none/rec_some removed — replaced by rec_none_k/rec_some_k above. */

static march_record_shape *rec_shape_or_panic(void *rec, const char *who) {
    march_record_shape *s = rec_shape_of(rec);
    if (!s) {
        char buf[192];
        /* Identify WHAT the shapeless value actually is, so a suite-wide
           failure report is self-diagnosing: null, a tagged immediate (low
           bit set), or a heap cell whose ctor tag reveals the type it was
           actually built as (-1 = string). */
        if (!rec)
            snprintf(buf, sizeof buf,
                     "%s: value carries no record shape metadata (value is null)",
                     who);
        else if (((uintptr_t)rec & 1u) != 0)
            snprintf(buf, sizeof buf,
                     "%s: value carries no record shape metadata "
                     "(value is a tagged immediate: %lld)",
                     who, (long long)((intptr_t)rec >> 1));
        else
            snprintf(buf, sizeof buf,
                     "%s: value carries no record shape metadata "
                     "(heap cell tag=%d rc=%lld)",
                     who, ((march_hdr *)rec)->tag,
                     (long long)((march_hdr *)rec)->rc);
        rec_panic(buf);
    }
    return s;
}

/* record_keys(rec) -> List(String), sorted by field name. */
void *march_record_keys(void *rec) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_keys");
    void *list = rec_nil();
    for (int32_t i = s->nfields - 1; i >= 0; i--) {
        void *k = march_string_lit(s->names[i], s->name_lens[i]);
        list = rec_cons((int64_t)(intptr_t)k, list);
    }
    return list;
}

/* record_values(rec) -> List(value), sorted by field name. */
void *march_record_values(void *rec) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_values");
    void *list = rec_nil();
    for (int32_t i = s->nfields - 1; i >= 0; i--)
        list = rec_cons(rec_field_out_adt(rec, i, s->kinds[i]), list);
    return list;
}

/* record_entries(rec) -> List((String, value)), sorted by field name.
 * Pair snd uses the UNIFORM convention (tagged ints) — compiled tuple slots
 * are uniform: ETuple stores scalars through coerce i64→ptr (tag) and all
 * destructure paths untag scalar views conditionally. */
void *march_record_entries(void *rec) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_entries");
    void *list = rec_nil();
    for (int32_t i = s->nfields - 1; i >= 0; i--) {
        void *k = march_string_lit(s->names[i], s->name_lens[i]);
        void *pair = rec_pair(k, rec_field_out_adt(rec, i, s->kinds[i]));
        list = rec_cons((int64_t)(intptr_t)pair, list);
    }
    return list;
}

/* record_get(rec, key, expected_kind) -> Option(value).
 * expected_kind is the shape_kind_char of the payload type at the call site
 * (passed from llvm_emit.ml).  Used for the None case (field absent) so the
 * compiler-side dispatch (niche or boxed) matches the returned value. */
void *march_record_get(void *rec, void *key, int64_t expected_kind) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_get");
    march_string *ks = (march_string *)key;
    int32_t i = rec_find_field(s, ks->data, ks->len);
    if (i < 0) return rec_none_k((char)expected_kind);
    /* Representation must match the call-site decoder (expected_kind), which for
     * a concrete Option(Float) is BOXED — not the stored kind. */
    return rec_some_k(rec_field_out_adt(rec, i, s->kinds[i]), (char)expected_kind);
}

/* record_has_key(rec, key) -> Bool (i64 0/1). */
int64_t march_record_has_key(void *rec, void *key) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_has_key");
    march_string *ks = (march_string *)key;
    return rec_find_field(s, ks->data, ks->len) >= 0 ? 1 : 0;
}

/* Build a descriptor with field (name, kind) inserted in sorted order. */
static char *rec_desc_insert(march_record_shape *s, const char *name,
                             int64_t len, char kind, int32_t *out_pos) {
    size_t cap = strlen(s->desc) + (size_t)len + 8;
    char *desc = malloc(cap);
    size_t w = 0;
    int32_t pos = s->nfields;
    int inserted = 0;
    for (int32_t i = 0; i < s->nfields; i++) {
        size_t minlen = (size_t)(len < s->name_lens[i] ? len : s->name_lens[i]);
        int cmp = inserted ? 1 : memcmp(name, s->names[i], minlen);
        if (cmp == 0 && !inserted)
            cmp = (len < s->name_lens[i]) ? -1 : (len > s->name_lens[i] ? 1 : 0);
        if (!inserted && cmp < 0) {
            w += (size_t)snprintf(desc + w, cap - w, "%.*s:%c;", (int)len, name, kind);
            pos = i;
            inserted = 1;
        }
        w += (size_t)snprintf(desc + w, cap - w, "%s:%c;", s->names[i], s->kinds[i]);
    }
    if (!inserted)
        w += (size_t)snprintf(desc + w, cap - w, "%.*s:%c;", (int)len, name, kind);
    *out_pos = pos;
    return desc;
}

/* Build a descriptor identical to s but with field fi's kind replaced. */
static char *rec_desc_with_kind(march_record_shape *s, int32_t fi, char kind) {
    char *desc = malloc(strlen(s->desc) + 1);
    size_t w = 0;
    for (int32_t i = 0; i < s->nfields; i++) {
        char k = (i == fi) ? kind : s->kinds[i];
        w += (size_t)sprintf(desc + w, "%s:%c;", s->names[i], k);
    }
    return desc;
}

/* record_put(rec, key, value, kind) -> new record with the field set (or
 * added, interning an extended shape at runtime).  [value] arrives in UNIFORM
 * representation (scalars low-bit tagged); [kind] is the call site's static
 * kind char. */
void *march_record_put(void *rec, void *key, void *value, int64_t kind) {
    march_record_shape *s = rec_shape_or_panic(rec, "record_put");
    march_string *ks = (march_string *)key;
    char k = (char)kind;
    int64_t vbits = rec_field_norm_in((int64_t)(intptr_t)value, &k);
    int32_t fi = rec_find_field(s, ks->data, ks->len);
    if (fi >= 0) {
        /* Existing field: copy cell, overwrite one slot. */
        char fk = k;
        void *out = march_alloc(16 + (size_t)s->nfields * 8);
        for (int32_t i = 0; i < s->nfields; i++) {
            if (i == fi) rec_field_set(out, i, vbits);
            else         rec_field_set(out, i, rec_field_copy(rec, i, s->kinds[i]));
        }
        if (fk == s->kinds[fi]) {
            ((march_hdr *)out)->pad = ((march_hdr *)rec)->pad;
        } else {
            char *desc = rec_desc_with_kind(s, fi, fk);
            ((march_hdr *)out)->pad = march_record_shape_intern(desc);
            free(desc);
        }
        return out;
    }
    /* New field: intern the extended shape. */
    int32_t pos;
    char *desc = rec_desc_insert(s, ks->data, ks->len, k, &pos);
    int32_t id = march_record_shape_intern(desc);
    free(desc);
    void *out = march_alloc(16 + ((size_t)s->nfields + 1) * 8);
    for (int32_t i = 0; i < pos; i++)
        rec_field_set(out, i, rec_field_copy(rec, i, s->kinds[i]));
    rec_field_set(out, pos, vbits);
    for (int32_t i = pos; i < s->nfields; i++)
        rec_field_set(out, i + 1, rec_field_copy(rec, i, s->kinds[i]));
    ((march_hdr *)out)->pad = id;
    return out;
}

/* 3-arg variant for first-class / generic call paths (kind unknown). */
void *march_record_put3(void *rec, void *key, void *value) {
    return march_record_put(rec, key, value, (int64_t)'g');
}

/* record_from_list(list, kind) -> record.  [list] is List((String, value))
 * with pair snd in natural repr of [kind] ('g' when unknown).  First
 * occurrence of a duplicate key wins (matches interpreter assoc lookup). */
void *march_record_from_list_k(void *list, int64_t kind) {
    char k = (char)kind;
    /* Collect pairs. */
    int32_t n = 0;
    for (void *p = list; p && ((march_hdr *)p)->tag == 1;
         p = *(void **)((char *)p + 24)) n++;
    void   **keys = calloc(n > 0 ? n : 1, sizeof(void *));
    int64_t *vals = calloc(n > 0 ? n : 1, sizeof(int64_t));
    int32_t cnt = 0;
    for (void *p = list; p && ((march_hdr *)p)->tag == 1;
         p = *(void **)((char *)p + 24)) {
        void *pair = *(void **)((char *)p + 16);
        keys[cnt] = *(void **)((char *)pair + 16);
        vals[cnt] = *(int64_t *)((char *)pair + 24);
        cnt++;
    }
    /* Drop duplicate keys (keep first occurrence). */
    int32_t m = 0;
    for (int32_t i = 0; i < cnt; i++) {
        march_string *ki = (march_string *)keys[i];
        int dup = 0;
        for (int32_t j = 0; j < m; j++) {
            march_string *kj = (march_string *)keys[j];
            if (ki->len == kj->len &&
                memcmp(ki->data, kj->data, (size_t)ki->len) == 0) { dup = 1; break; }
        }
        if (!dup) { keys[m] = keys[i]; vals[m] = vals[i]; m++; }
    }
    /* Sort by key name (insertion sort — n is small). */
    for (int32_t i = 1; i < m; i++) {
        void *kp = keys[i]; int64_t vp = vals[i];
        march_string *ki = (march_string *)kp;
        int32_t j = i - 1;
        while (j >= 0) {
            march_string *kj = (march_string *)keys[j];
            size_t minlen = (size_t)(ki->len < kj->len ? ki->len : kj->len);
            int cmp = memcmp(ki->data, kj->data, minlen);
            if (cmp == 0) cmp = (ki->len < kj->len) ? -1 : (ki->len > kj->len ? 1 : 0);
            if (cmp >= 0) break;
            keys[j + 1] = keys[j]; vals[j + 1] = vals[j]; j--;
        }
        keys[j + 1] = kp; vals[j + 1] = vp;
    }
    /* Normalize values: pair snd arrives in UNIFORM repr (compiled tuple
     * slots tag scalars), so per-field kinds may differ from the static
     * hint — e.g. a tagged int untags to a natural 'i' slot, while a heap
     * pointer under an 'i' hint (lying static type) downgrades to 'g'. */
    char *fkinds = malloc((size_t)(m > 0 ? m : 1));
    for (int32_t i = 0; i < m; i++) {
        char fk = k;
        if (fk == 'f')      { /* raw double bits, store verbatim */ }
        else if (fk == 'p') { march_incrc((void *)(intptr_t)vals[i]); }
        else                { vals[i] = rec_field_norm_uniform(vals[i], &fk); }
        fkinds[i] = fk;
    }
    /* Build descriptor + record. */
    size_t cap = 16;
    for (int32_t i = 0; i < m; i++) cap += (size_t)((march_string *)keys[i])->len + 4;
    char *desc = malloc(cap);
    size_t w = 0;
    for (int32_t i = 0; i < m; i++) {
        march_string *ks = (march_string *)keys[i];
        w += (size_t)snprintf(desc + w, cap - w, "%.*s:%c;", (int)ks->len, ks->data, fkinds[i]);
    }
    desc[w] = '\0';
    int32_t id = march_record_shape_intern(desc);
    free(desc);
    void *out = march_alloc(16 + (size_t)m * 8);
    for (int32_t i = 0; i < m; i++)
        rec_field_set(out, i, vals[i]);
    ((march_hdr *)out)->pad = id;
    free(keys); free(vals); free(fkinds);
    return out;
}

void *march_record_from_list(void *list) {
    return march_record_from_list_k(list, (int64_t)'g');
}

/* Dynamic field read for statically-unknown record types.  Returns the value
 * in UNIFORM representation ('i' fields low-bit tagged, 'f' raw double bits,
 * heap pointers verbatim): consumers view the ptr result through their static
 * type, untagging scalar views conditionally (ashr iff odd).  No incrc here —
 * Perceus inserts any needed IncRC on the projection result itself, exactly
 * like a static EField load.  Shape 0 falls back to the legacy behavior (raw
 * slot-0 read) so non-record cells reaching this path behave as before. */
void *march_record_field_dyn(void *rec, const char *name, int64_t len) {
    march_record_shape *s = rec_shape_of(rec);
    if (!s) return *(void **)((char *)rec + 16);
    int32_t i = rec_find_field(s, name, len);
    if (i < 0) {
        char buf[160];
        snprintf(buf, sizeof buf, "record field access: no field \"%.*s\" in record",
                 (int)(len < 100 ? len : 100), name);
        rec_panic(buf);
    }
    int64_t raw = rec_field_raw(rec, i);
    if (s->kinds[i] == 'i') return (void *)(intptr_t)((raw << 1) | 1);
    return (void *)(intptr_t)raw;
}

/* get_actor_field(pid, field): a PARTIAL lookup, unlike march_record_field_dyn
 * above (a total EField read that panics on a missing name) — March code,
 * most often through a small generic helper (e.g. supervision_strategies
 * .march's child_int), reads a named actor state field without statically
 * knowing whether it exists, and expects Option(b): None if absent. Reuses
 * the SAME runtime shape registry march_record_field_dyn consults — a shape
 * id stamped into the actor struct header's pad word at spawn time (the
 * EAlloc actor-struct branch in llvm_emit.ml, guarded by
 * Tir_names.is_actor_struct_name) — so this works regardless of whether the
 * caller's static Pid(a) type is concrete or still an unresolved type
 * variable (the realistic case: nothing in get_actor_field's own signature
 * forces monomorphization on `a` through an indirecting helper function).
 * Returns a niche-tagged Option: NULL = None, (n<<1)|1 = Some(n) for an 'i'
 * (Int/Bool/Unit/Atom) field, the raw pointer verbatim for anything else —
 * matching march_record_field_dyn's found-value convention exactly. */
void *march_get_actor_field(void *pid, void *name) {
    march_string *ns = (march_string *)name;
    march_record_shape *s = rec_shape_of(pid);
    if (!s) return NULL;
    int32_t i = rec_find_field(s, ns->data, ns->len);
    if (i < 0) return NULL;
    int64_t raw = rec_field_raw(pid, i);
    if (s->kinds[i] == 'i') return (void *)(intptr_t)((raw << 1) | 1);
    return (void *)(intptr_t)raw;
}

/* Record update (`{ r with f: v, ... }`) for statically-unknown record types
 * (the EUpdate counterpart of march_record_field_dyn above): one allocation,
 * the base cell's fields copied, the named fields overwritten.  Varargs are
 * [n] quadruples of (const char *name, int64_t name_len, void *value, int64_t
 * kind); values arrive in UNIFORM representation (scalars low-bit tagged)
 * with the call site's static kind char, exactly like march_record_put.
 * PANICS if any update name is
 * missing from the base shape (mirroring march_record_field_dyn): unlike a
 * statically-known update, the typechecker cannot validate names against a
 * type-erased base, and silently extending the record (march_record_put's
 * new-key behavior) would fabricate fields the program never declared.
 * Update semantics on duplicate names: the LAST occurrence wins (matches the
 * interpreter's assoc-override order). */
void *march_record_update_dyn(void *rec, int64_t n, ...) {
    march_record_shape *s = rec_shape_or_panic(rec, "record update");
    const char **names = calloc(n > 0 ? (size_t)n : 1, sizeof(char *));
    int64_t *lens  = calloc(n > 0 ? (size_t)n : 1, sizeof(int64_t));
    void   **vals  = calloc(n > 0 ? (size_t)n : 1, sizeof(void *));
    char    *kins  = calloc(n > 0 ? (size_t)n : 1, 1);
    int32_t *idx   = calloc(n > 0 ? (size_t)n : 1, sizeof(int32_t));
    va_list ap;
    va_start(ap, n);
    for (int64_t j = 0; j < n; j++) {
        names[j] = va_arg(ap, const char *);
        lens[j]  = va_arg(ap, int64_t);
        vals[j]  = va_arg(ap, void *);
        kins[j]  = (char)va_arg(ap, int64_t);
    }
    va_end(ap);
    /* Resolve every name FIRST — fail loudly before touching refcounts. */
    for (int64_t j = 0; j < n; j++) {
        idx[j] = rec_find_field(s, names[j], lens[j]);
        if (idx[j] < 0) {
            char buf[160];
            snprintf(buf, sizeof buf, "record update: no field \"%.*s\" in record",
                     (int)(lens[j] < 100 ? lens[j] : 100), names[j]);
            rec_panic(buf);
        }
    }
    /* Normalize the winning update per field (walk in reverse so the LAST
     * duplicate wins and only the winner takes its +1 reference). */
    char    *is_upd    = calloc((size_t)s->nfields > 0 ? (size_t)s->nfields : 1, 1);
    int64_t *upd_bits  = calloc((size_t)s->nfields > 0 ? (size_t)s->nfields : 1,
                                sizeof(int64_t));
    char    *new_kinds = malloc((size_t)s->nfields > 0 ? (size_t)s->nfields : 1);
    memcpy(new_kinds, s->kinds, (size_t)s->nfields);
    for (int64_t j = n - 1; j >= 0; j--) {
        int32_t fi = idx[j];
        if (is_upd[fi]) continue;
        char k = kins[j];
        upd_bits[fi]  = rec_field_norm_in((int64_t)(intptr_t)vals[j], &k);
        new_kinds[fi] = k;
        is_upd[fi]    = 1;
    }
    /* Single allocation: copy untouched fields (+1 ref on heap children,
     * matching march_record_put), write the updated ones. */
    void *out = march_alloc(16 + (size_t)s->nfields * 8);
    for (int32_t i = 0; i < s->nfields; i++) {
        if (is_upd[i]) rec_field_set(out, i, upd_bits[i]);
        else           rec_field_set(out, i, rec_field_copy(rec, i, s->kinds[i]));
    }
    /* Shape: unchanged kinds reuse the base's id; otherwise intern the
     * kind-adjusted descriptor (same policy as march_record_put). */
    if (memcmp(new_kinds, s->kinds, (size_t)s->nfields) == 0) {
        ((march_hdr *)out)->pad = ((march_hdr *)rec)->pad;
    } else {
        char *desc = malloc(strlen(s->desc) + 1);
        size_t w = 0;
        for (int32_t i = 0; i < s->nfields; i++)
            w += (size_t)sprintf(desc + w, "%s:%c;", s->names[i], new_kinds[i]);
        ((march_hdr *)out)->pad = march_record_shape_intern(desc);
        free(desc);
    }
    free(names); free(lens); free(vals); free(kins); free(idx);
    free(is_upd); free(upd_bits); free(new_kinds);
    return out;
}

/* ── ~H sigil: html_auto_escape ──────────────────────────────────────────────
 * The ~H template sigil lowers each ${expr} interpolation to html_auto_escape(v).
 * Auto-escaping rules (mirror the interpreter in lib/eval/eval.ml):
 *   - immediate int (low-bit tagged) → decimal text (no escaping)
 *   - String (tag == MARCH_STRING_TAG) → HTML-escape & < > " '
 *   - IOList constructor (tag >= 0)     → flatten verbatim (already HTML)
 * Field layout: tag is int32 at offset +8; constructor fields at +16, +24.
 * IOList variant tags: 0=Empty, 1=Str(String) @+16, 2=Segments(List) @+16.
 * List tags: 0=Nil, 1=Cons(head @+16, tail @+24). */

static int64_t mh_iolist_size(void *iolist) {
    if (!iolist) return 0;
    int32_t tag = *(int32_t *)((char *)iolist + 8);
    if (tag == 1) {
        march_string *str = (march_string *)*(void **)((char *)iolist + 16);
        return str ? str->len : 0;
    } else if (tag == 2) {
        void *list = *(void **)((char *)iolist + 16);
        int64_t total = 0;
        while (list) {
            if (*(int32_t *)((char *)list + 8) == 0) break; /* Nil */
            void *head = *(void **)((char *)list + 16);
            list = *(void **)((char *)list + 24);
            total += mh_iolist_size(head);
        }
        return total;
    }
    return 0;
}

static int64_t mh_iolist_copy(void *iolist, char *buf, int64_t off) {
    if (!iolist) return off;
    int32_t tag = *(int32_t *)((char *)iolist + 8);
    if (tag == 1) {
        march_string *str = (march_string *)*(void **)((char *)iolist + 16);
        if (str) { for (int64_t i = 0; i < str->len; i++) buf[off++] = str->data[i]; }
        return off;
    } else if (tag == 2) {
        void *list = *(void **)((char *)iolist + 16);
        while (list) {
            if (*(int32_t *)((char *)list + 8) == 0) break; /* Nil */
            void *head = *(void **)((char *)list + 16);
            list = *(void **)((char *)list + 24);
            off = mh_iolist_copy(head, buf, off);
        }
        return off;
    }
    return off;
}

void *march_html_auto_escape(void *v) {
    /* Immediate (tagged int / nullary constructor): low bit set. */
    if (((uintptr_t)v & 1u) != 0) {
        int64_t n = (intptr_t)v >> 1;
        char b[32];
        int len = snprintf(b, sizeof(b), "%lld", (long long)n);
        return march_string_lit(b, (int64_t)len);
    }
    if (!v) return march_string_lit("", 0);
    int32_t tag = ((march_hdr *)v)->tag;
    if (tag == MARCH_STRING_TAG) {
        march_string *s = (march_string *)v;
        int64_t n = s->len;
        char *out = (char *)malloc((size_t)(n * 6 + 1));
        int64_t o = 0;
        for (int64_t i = 0; i < n; i++) {
            char c = s->data[i];
            if (c == '&') { memcpy(out + o, "&amp;", 5); o += 5; }
            else if (c == '<') { memcpy(out + o, "&lt;", 4); o += 4; }
            else if (c == '>') { memcpy(out + o, "&gt;", 4); o += 4; }
            else if (c == '"') { memcpy(out + o, "&quot;", 6); o += 6; }
            else if (c == '\'') { memcpy(out + o, "&#39;", 5); o += 5; }
            else { out[o++] = c; }
        }
        void *r = march_string_lit(out, o);
        free(out);
        return r;
    }
    /* Constructor with tag >= 0: treat as IOList and flatten verbatim. */
    int64_t sz = mh_iolist_size(v);
    char *buf = (char *)malloc((size_t)(sz + 1));
    mh_iolist_copy(v, buf, 0);
    void *r = march_string_lit(buf, sz);
    free(buf);
    return r;
}
