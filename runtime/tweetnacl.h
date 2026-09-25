/* tweetnacl.h — ed25519 signing/verification (public domain, TweetNaCl-derived).
 * Only the ed25519 subset. SHA-512 is included inline in tweetnacl.c.
 *
 * API:
 *   crypto_sign_keypair(pk, sk)             — generate keypair from random seed
 *   crypto_sign(sm, smlen, m, mlen, sk)     — sign message (prepends 64-byte sig)
 *   crypto_sign_open(m, mlen, sm, smlen, pk) — verify; returns 0 on success, -1 on failure
 *   crypto_sign_ed25519_open(...)           — alias for crypto_sign_open
 *   crypto_sign_seed_keypair(pk, sk, seed)  — keypair from a 32-byte seed (RFC 8032)
 *   crypto_scalarmult(q, n, p)              — X25519 (RFC 7748)
 *   crypto_scalarmult_base(q, n)            — X25519 with the base point 9
 */
#ifndef TWEETNACL_H
#define TWEETNACL_H

#include <stdint.h>
#include <stddef.h>

/* Key and signature sizes */
#define CRYPTO_SIGN_PUBLICKEYBYTES  32
#define CRYPTO_SIGN_SECRETKEYBYTES  64   /* 32-byte seed || 32-byte public key */
#define CRYPTO_SIGN_BYTES           64

/* Generate an ed25519 keypair.
 * pk: 32-byte public key output
 * sk: 64-byte secret key output (seed || public key)
 * Returns 0 on success. */
int crypto_sign_keypair(unsigned char *pk, unsigned char *sk);

/* The keypair for a given 32-byte seed (sk = seed || pk). Returns 0. */
int crypto_sign_seed_keypair(unsigned char *pk, unsigned char *sk,
                             const unsigned char *seed);

/* Sign message m[mlen] with sk, writing signed message to sm.
 * sm must have room for mlen + 64 bytes.
 * *smlen is set to mlen + 64.
 * Returns 0 on success. */
int crypto_sign(unsigned char *sm, unsigned long long *smlen,
                const unsigned char *m, unsigned long long mlen,
                const unsigned char *sk);

/* Verify signed message sm[smlen] with public key pk.
 * On success, writes message to m and *mlen; returns 0.
 * On failure, returns -1 (m and mlen are undefined). */
int crypto_sign_open(unsigned char *m, unsigned long long *mlen,
                     const unsigned char *sm, unsigned long long smlen,
                     const unsigned char *pk);

/* X25519: q = n * p on Curve25519 (32-byte little-endian u-coordinates;
 * the scalar is clamped as RFC 7748 specifies). Returns 0. */
int crypto_scalarmult(unsigned char *q, const unsigned char *n,
                      const unsigned char *p);
int crypto_scalarmult_base(unsigned char *q, const unsigned char *n);

/* Alias used by march_reload.c */
#define crypto_sign_ed25519_open crypto_sign_open

#endif /* TWEETNACL_H */
