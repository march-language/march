/* march_remote_registry.h — function-by-identity registry for distributed
 * remote calls (Distributed OTP L4).
 *
 * Maps a remote target's CAS identity (its impl_hash string) to its compiler-
 * emitted marshalling stub, so an inbound `Node.call` carrying a RemoteRef can
 * locate and invoke the local native copy. The compiler emits one
 * `march_remote_register` call per enrolled target at @main startup; enrolling
 * a target also pins its entry point against dead-code elimination.
 *
 * A stub has the uniform marshalling ABI: it takes the MessagePack-encoded
 * argument tuple and returns the MessagePack-encoded result (decode args ->
 * invoke the typed body -> encode result). The bytes are a length-prefixed
 * buffer; the exact buffer type is the stub ABI's concern, so the registry
 * stores the entry point as an opaque `void *`.
 *
 * Distinct from march_dispatch (HCR): that table is NAME_ID-indexed and
 * versioned for hot reload; this one is identity-keyed (impl_hash) for
 * cross-node dispatch. A node may hold both — the same function can be a
 * hot-reload boundary and an enrolled remote target.
 */
#ifndef MARCH_REMOTE_REGISTRY_H
#define MARCH_REMOTE_REGISTRY_H

#include <stddef.h>

/* Allocate the global registry (idempotent: re-init clears any prior table). */
void march_remote_init(void);
void march_remote_shutdown(void);

/* Enroll [stub] as the target with CAS identity [impl_hash], recording its
 * [sig_hash] for the admission check. The strings are copied. Idempotent on
 * identity: re-registering the same impl_hash replaces the prior entry.
 * Returns 0 on success, -1 on allocation failure or NULL impl_hash/stub. */
int march_remote_register(const char *impl_hash, const char *sig_hash,
                          void *stub);

/* The marshalling stub enrolled under [impl_hash], or NULL if none. */
void *march_remote_lookup(const char *impl_hash);

/* The sig_hash recorded for [impl_hash], or NULL if not enrolled — lets the
 * responder run the CAS admission check (signature match) before invoking. */
const char *march_remote_sig_hash(const char *impl_hash);

/* Whether a target is enrolled under [impl_hash]. */
int march_remote_has(const char *impl_hash);

/* Number of enrolled targets (introspection / tests). */
size_t march_remote_count(void);

#endif /* MARCH_REMOTE_REGISTRY_H */
