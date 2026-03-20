/* OCaml C stubs for BLAKE3 hashing via libblake3. */

#include <caml/mlvalues.h>
#include <caml/alloc.h>
#include <caml/memory.h>
#include <caml/fail.h>
#include <blake3.h>
#include <string.h>

/* hash_bytes : bytes -> string
   Returns a 64-char lowercase hex string (32-byte BLAKE3 digest). */
CAMLprim value march_blake3_hash(value input)
{
    CAMLparam1(input);
    CAMLlocal1(result);

    const char *data   = Bytes_val(input);
    size_t      len    = caml_string_length(input);
    uint8_t     out[BLAKE3_OUT_LEN];

    blake3_hasher hasher;
    blake3_hasher_init(&hasher);
    blake3_hasher_update(&hasher, data, len);
    blake3_hasher_finalize(&hasher, out, BLAKE3_OUT_LEN);

    /* Encode as 64-char hex string */
    static const char hex[] = "0123456789abcdef";
    result = caml_alloc_string(BLAKE3_OUT_LEN * 2);
    char *dst = Bytes_val(result);
    for (int i = 0; i < BLAKE3_OUT_LEN; i++) {
        dst[i * 2]     = hex[(out[i] >> 4) & 0xf];
        dst[i * 2 + 1] = hex[out[i] & 0xf];
    }

    CAMLreturn(result);
}
