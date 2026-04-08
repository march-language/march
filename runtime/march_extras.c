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
#include <pthread.h>
#include <time.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/types.h>

#ifdef __APPLE__
#  include <sys/sysctl.h>
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

/* Create a Cons(int, tail) list node.  Transfers ownership of tail. */
static void *int_cons(int64_t n, void *tail) {
    void *node = march_alloc(16 + 16);   /* hdr(16) + i64(8) + ptr(8) */
    *(int32_t *)((char *)node + 8)  = 1; /* tag = 1 = Cons */
    *(int64_t *)((char *)node + 16) = n;
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
        buf[i++] = (uint8_t)(*(int64_t *)((char *)p + 16) & 0xFF);
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
    *(int32_t *)((char *)r + 8) = 1;   /* tag = 1 = Ok */
    *(void **)((char *)r + 16) = val;
    return r;
}

static void *make_err_str(const char *msg) {
    void *s = march_string_lit(msg, (int64_t)strlen(msg));
    void *r = march_alloc(16 + 8);
    /* tag = 0 = Err */
    *(void **)((char *)r + 16) = s;
    return r;
}

/* ── Option helpers ───────────────────────────────────────────────────── */

static void *make_some(void *val) {
    void *r = march_alloc(16 + 8);
    *(int32_t *)((char *)r + 8) = 1;   /* tag = 1 = Some */
    *(void **)((char *)r + 16) = val;
    return r;
}

static void *make_none(void) {
    return march_alloc(16); /* tag = 0 = None */
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

/* Takes String (base64), returns Option(Bytes). */
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
        if (v == -1) { free(out); return make_none(); } /* invalid char */
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
    return make_some(bval);
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
    /* f is a March closure; we need to call it.
     * Closures in March are heap objects: [rc][tag][pad][fn_ptr][env_ptr...]
     * fn_ptr is at offset 16, env at offset 24.
     * Calling convention: fn_ptr(env, arg) */
    void *cur = march_vault_get(handle, key_val);
    /* Check if Some(v) */
    int32_t tag = *(int32_t *)((char *)cur + 8);
    if (tag == 1) { /* Some */
        void *v   = *(void **)((char *)cur + 16);
        /* Call f(v): f is a closure [rc][tag][pad][fn_ptr][env_ptr] */
        typedef void *(*fn1_t)(void *, void *);
        fn1_t fn  = *(fn1_t *)((char *)f + 16);
        void *env = *(void **)((char *)f + 24);
        void *new_val = fn(env, v);
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
    /* Namespace doesn't exist — return None */
    void *none = march_alloc(16);
    *(int32_t *)((char *)none + 8) = 0; /* tag = 0 = None */
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
