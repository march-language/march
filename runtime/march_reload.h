/* march_reload.h — HCR Phase 3 reload server.
 *
 * A background pthread listens on a Unix-domain socket for ACTIVATE commands.
 * Only active when MARCH_HOT_RELOAD_SOCKET env var is set.
 * Linux-only in Phase 3 (macOS deferred). */
#ifndef MARCH_RELOAD_H
#define MARCH_RELOAD_H

#include <stddef.h>

/* Start the reload server on [socket_path].  No-op if path is NULL or empty.
 * Must be called after march_dispatch_init() has been called. */
void march_reload_server_start(const char *socket_path);

/* Validate a dlopen'd patch's embedded target/ABI/prefix markers. */
int march_hcr_patch_identity_ok(void *handle, char *reason, size_t reason_len);

#endif /* MARCH_RELOAD_H */
