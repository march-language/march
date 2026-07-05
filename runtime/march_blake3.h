/* march_blake3.h — BLAKE3 hex-digest helper for the C runtime.
 *
 * The compiler computes `cap_root` (Phase5C-A) as a BLAKE3 hex digest via
 * March_cas.Blake3 (lib/cas/blake3_stubs.c, wrapping libblake3). The reload
 * server (march_reload.c, Phase5C-C.3) must recompute `cap_root` from the
 * `caps:` it receives over the wire and compare it against the signed value
 * — that only works if the runtime hashes with the *same* algorithm. This
 * header exposes a pure-C helper over the same libblake3 API and the same
 * hex encoding as blake3_stubs.c, so march_blake3_hex(x) == (the hex string
 * produced by) March_cas.Blake3.hash_string(x) for identical input bytes. */
#ifndef MARCH_BLAKE3_H
#define MARCH_BLAKE3_H

#include <stddef.h>

/* Writes the 64-char lowercase hex BLAKE3 digest of buf[0..len) into out,
 * followed by a NUL terminator (out must have room for 65 bytes). */
void march_blake3_hex(const unsigned char *buf, size_t len, char out[65]);

#endif /* MARCH_BLAKE3_H */
