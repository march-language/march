/* lib/ed25519/stubs.c — OCaml FFI wrappers around TweetNaCl ed25519.
 *
 * tweetnacl_impl.c (a copy of runtime/tweetnacl.c) is compiled as a separate
 * object in the same dune library.  This file only provides the OCaml stubs.
 */
#include "tweetnacl.h"
#include <stdlib.h>
#include <string.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

/* Ed25519.keygen () : bytes * bytes  — (pk 32 bytes, sk 64 bytes) */
CAMLprim value caml_ed25519_keygen(value unit)
{
    CAMLparam1(unit);
    CAMLlocal3(pk_val, sk_val, pair);

    pk_val = caml_alloc_string(CRYPTO_SIGN_PUBLICKEYBYTES);
    sk_val = caml_alloc_string(CRYPTO_SIGN_SECRETKEYBYTES);

    unsigned char *pk = (unsigned char *)Bytes_val(pk_val);
    unsigned char *sk = (unsigned char *)Bytes_val(sk_val);

    if (crypto_sign_keypair(pk, sk) != 0)
        caml_failwith("ed25519: keygen failed");

    pair = caml_alloc_tuple(2);
    Store_field(pair, 0, pk_val);
    Store_field(pair, 1, sk_val);

    CAMLreturn(pair);
}

/* Ed25519.sign msg sk : bytes  — 64-byte detached signature */
CAMLprim value caml_ed25519_sign(value msg_val, value sk_val)
{
    CAMLparam2(msg_val, sk_val);
    CAMLlocal1(sig_val);

    if (caml_string_length(sk_val) != CRYPTO_SIGN_SECRETKEYBYTES)
        caml_failwith("ed25519: secret key must be 64 bytes");

    const unsigned char *m  = (const unsigned char *)Bytes_val(msg_val);
    unsigned long long  mlen = (unsigned long long)caml_string_length(msg_val);
    const unsigned char *sk  = (const unsigned char *)Bytes_val(sk_val);

    /* crypto_sign produces sig || msg in sm; we only keep the 64-byte sig. */
    unsigned long long smlen = 0;
    unsigned char *sm = (unsigned char *)malloc(mlen + CRYPTO_SIGN_BYTES);
    if (!sm) caml_failwith("ed25519: out of memory");

    if (crypto_sign(sm, &smlen, m, mlen, sk) != 0) {
        free(sm);
        caml_failwith("ed25519: sign failed");
    }

    sig_val = caml_alloc_string(CRYPTO_SIGN_BYTES);
    memcpy(Bytes_val(sig_val), sm, CRYPTO_SIGN_BYTES);
    free(sm);

    CAMLreturn(sig_val);
}

/* Ed25519.verify msg sig pk : bool  — verify a detached signature */
CAMLprim value caml_ed25519_verify(value msg_val, value sig_val, value pk_val)
{
    CAMLparam3(msg_val, sig_val, pk_val);

    if (caml_string_length(sig_val) != CRYPTO_SIGN_BYTES)
        CAMLreturn(Val_bool(0));
    if (caml_string_length(pk_val) != CRYPTO_SIGN_PUBLICKEYBYTES)
        CAMLreturn(Val_bool(0));

    const unsigned char *m   = (const unsigned char *)Bytes_val(msg_val);
    unsigned long long  mlen = (unsigned long long)caml_string_length(msg_val);
    const unsigned char *sig = (const unsigned char *)Bytes_val(sig_val);
    const unsigned char *pk  = (const unsigned char *)Bytes_val(pk_val);

    /* Rebuild sm = sig || msg for crypto_sign_open */
    unsigned long long smlen = mlen + CRYPTO_SIGN_BYTES;
    unsigned char *sm = (unsigned char *)malloc(smlen);
    if (!sm) caml_failwith("ed25519: out of memory");
    memcpy(sm, sig, CRYPTO_SIGN_BYTES);
    memcpy(sm + CRYPTO_SIGN_BYTES, m, mlen);

    unsigned char *m_out = (unsigned char *)malloc(smlen);
    if (!m_out) { free(sm); caml_failwith("ed25519: out of memory"); }
    unsigned long long m_out_len = 0;

    int ok = (crypto_sign_open(m_out, &m_out_len, sm, smlen, pk) == 0);
    free(sm);
    free(m_out);

    CAMLreturn(Val_bool(ok));
}
