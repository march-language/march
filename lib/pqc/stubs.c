/* lib/pqc/stubs.c — OCaml FFI wrappers over runtime/pqc.c (compiled into this
 * library as pqc_impl.c). Mirrors runtime/march_pqc.c's length checks; a
 * failure is [None] (verify: false), never an exception. */
#include "pqc.h"
#include <stdlib.h>
#include <string.h>
#include <caml/mlvalues.h>
#include <caml/memory.h>
#include <caml/alloc.h>
#include <caml/fail.h>

static value pqc_some_string(const uint8_t *data, size_t len)
{
    CAMLparam0();
    CAMLlocal2(s, some);
    s = caml_alloc_initialized_string(len, (const char *)data);
    some = caml_alloc_some(s);
    CAMLreturn(some);
}

CAMLprim value caml_pqc_mlkem768_keypair(value seed)
{
    CAMLparam1(seed);
    if (caml_string_length(seed) != PQC_MLKEM768_KEYPAIR_SEEDBYTES) CAMLreturn(Val_none);
    uint8_t pk[PQC_MLKEM768_PUBLICKEYBYTES], sk[PQC_MLKEM768_SECRETKEYBYTES];
    if (pqc_mlkem768_keypair_derand(pk, sk, (const uint8_t *)String_val(seed)) != 0)
        CAMLreturn(Val_none);
    value r = pqc_some_string(sk, sizeof sk);
    memset(sk, 0, sizeof sk);
    CAMLreturn(r);
}

CAMLprim value caml_pqc_mlkem768_encaps(value pk, value coins)
{
    CAMLparam2(pk, coins);
    if (caml_string_length(pk) != PQC_MLKEM768_PUBLICKEYBYTES
        || caml_string_length(coins) != PQC_MLKEM768_ENC_COINBYTES)
        CAMLreturn(Val_none);
    uint8_t out[PQC_MLKEM768_CIPHERTEXTBYTES + PQC_MLKEM768_SSBYTES];
    if (pqc_mlkem768_enc_derand(out, out + PQC_MLKEM768_CIPHERTEXTBYTES,
                                (const uint8_t *)String_val(pk),
                                (const uint8_t *)String_val(coins)) != 0)
        CAMLreturn(Val_none);
    value r = pqc_some_string(out, sizeof out);
    memset(out, 0, sizeof out);
    CAMLreturn(r);
}

CAMLprim value caml_pqc_mlkem768_decaps(value sk, value ct)
{
    CAMLparam2(sk, ct);
    if (caml_string_length(sk) != PQC_MLKEM768_SECRETKEYBYTES
        || caml_string_length(ct) != PQC_MLKEM768_CIPHERTEXTBYTES)
        CAMLreturn(Val_none);
    uint8_t ss[PQC_MLKEM768_SSBYTES];
    if (pqc_mlkem768_dec(ss, (const uint8_t *)String_val(ct),
                         (const uint8_t *)String_val(sk)) != 0)
        CAMLreturn(Val_none);
    value r = pqc_some_string(ss, sizeof ss);
    memset(ss, 0, sizeof ss);
    CAMLreturn(r);
}

CAMLprim value caml_pqc_mldsa65_keypair(value seed)
{
    CAMLparam1(seed);
    CAMLlocal1(r);
    if (caml_string_length(seed) != PQC_MLDSA65_SEEDBYTES) CAMLreturn(Val_none);
    uint8_t *kp = malloc(PQC_MLDSA65_SECRETKEYBYTES + PQC_MLDSA65_PUBLICKEYBYTES);
    if (!kp) caml_raise_out_of_memory();
    if (pqc_mldsa65_keypair_internal(kp + PQC_MLDSA65_SECRETKEYBYTES, kp,
                                     (const uint8_t *)String_val(seed)) != 0)
        r = Val_none;
    else
        r = pqc_some_string(kp, PQC_MLDSA65_SECRETKEYBYTES + PQC_MLDSA65_PUBLICKEYBYTES);
    memset(kp, 0, PQC_MLDSA65_SECRETKEYBYTES);
    free(kp);
    CAMLreturn(r);
}

CAMLprim value caml_pqc_mldsa65_sign(value sk, value msg, value rnd)
{
    CAMLparam3(sk, msg, rnd);
    if (caml_string_length(sk) != PQC_MLDSA65_SECRETKEYBYTES
        || caml_string_length(rnd) != PQC_MLDSA65_RNDBYTES)
        CAMLreturn(Val_none);
    uint8_t sig[PQC_MLDSA65_SIGBYTES];
    if (pqc_mldsa65_sign(sig, (const uint8_t *)String_val(msg), caml_string_length(msg),
                         (const uint8_t *)String_val(rnd),
                         (const uint8_t *)String_val(sk)) != 0)
        CAMLreturn(Val_none);
    CAMLreturn(pqc_some_string(sig, sizeof sig));
}

CAMLprim value caml_pqc_mldsa65_verify(value pk, value msg, value sig)
{
    CAMLparam3(pk, msg, sig);
    if (caml_string_length(pk) != PQC_MLDSA65_PUBLICKEYBYTES
        || caml_string_length(sig) != PQC_MLDSA65_SIGBYTES)
        CAMLreturn(Val_false);
    int ok = pqc_mldsa65_verify((const uint8_t *)String_val(sig),
                                (const uint8_t *)String_val(msg), caml_string_length(msg),
                                (const uint8_t *)String_val(pk)) == 0;
    CAMLreturn(Val_bool(ok));
}
