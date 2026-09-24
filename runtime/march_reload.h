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

/* The reload server's topology hook (distributed-deploys build steps 8 and
 * 10).  Called after a signed TOPOLOGY push has been verified and written
 * to [path] (the service's persisted state directory, topology.toml), and
 * once at start, before march_reload_server_start returns, when a pushed
 * topology was persisted and its signature and digest still verify.
 *
 * A NO-OP for now: build step 8 (nodes that open their own offers from a
 * pushed topology, D16) fills it in with the node's topology re-read.  It
 * runs on the reload server thread (or, at start, on the thread calling
 * march_reload_server_start); it must not block. */
void march_hcr_on_topology(const char *path);

/* Validate a dlopen'd patch's embedded target/ABI/prefix markers. */
int march_hcr_patch_identity_ok(void *handle, char *reason, size_t reason_len);

#endif /* MARCH_RELOAD_H */
