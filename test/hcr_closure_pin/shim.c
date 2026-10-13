/* In-process hot deploy for the hcr_closure_pin fixture (linked into the
 * base and every patch with --ffi-c).  hcrpin_deploy(k) does what the reload
 * server's ACTIVATE verb does for one deploy (runtime/march_reload.c,
 * activate_items), minus the socket, signing, CAS and audit log: dlopen
 * $HCRPIN_PATCH_<k>, dlsym every slot named in $HCRPIN_NAMES, run the
 * image's __march_init, then march_hcr_activate them as ONE deploy.  Each
 * slot gets its own dlopen reference, as the server's (one dlopen per item).
 *
 * It installs no close hook: whatever the runtime does with a reclaimed
 * version's handle is what is under test.  Adapted from the Phase 0 spike's
 * specs/spikes/2026-10-13-hcr-phase0/swap_shim.c. */
#include "march_ffi.h"
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    uint32_t    slot;
    void       *fn;
    const char *impl_hash;
    const char *sig_hash;
    uint8_t     kind;
    void     *(*migrate_fn)(void *);
    void     *(*migrate_msg_fn)(void *, void *);
    int         state_changed;
    int         msgs_changed;
    void       *handle;
    int         ring_idx;
} march_hcr_unit;
typedef struct { uint32_t epoch; int64_t pins; int64_t deadline_ms; int table_full; } march_hcr_wait;
int      march_hcr_activate(march_hcr_unit *units, int n, uint32_t requested_epoch,
                            int64_t soft_ms, int64_t hard_ms, march_hcr_wait *wait);
int      march_dispatch_name_to_id(const char *name, uint32_t *out_id);
uint32_t march_epoch_next(uint32_t requested);

#define MAXN 8

int64_t hcrpin_deploy(int64_t k) {
    char var[64];
    snprintf(var, sizeof var, "HCRPIN_PATCH_%lld", (long long)k);
    const char *path = getenv(var);
    const char *names_env = getenv("HCRPIN_NAMES");
    if (!names_env || !*names_env) names_env = "Handler.mk";
    if (!path) { fprintf(stderr, "hcrpin: %s unset\n", var); return -1; }
    char buf[512];
    snprintf(buf, sizeof buf, "%s", names_env);
    char *names[MAXN]; int n = 0;
    for (char *t = strtok(buf, ","); t && n < MAXN; t = strtok(NULL, ",")) names[n++] = t;
    march_hcr_unit u[MAXN];
    memset(u, 0, sizeof u);
    static char hashes[64][32]; static int nh = 0;
    for (int i = 0; i < n; i++) {
        void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
        if (!h) { fprintf(stderr, "hcrpin: dlopen %s: %s\n", path, dlerror()); return -2; }
        if (!march_dispatch_name_to_id(names[i], &u[i].slot)) {
            fprintf(stderr, "hcrpin: no slot %s\n", names[i]); return -3;
        }
        u[i].fn = dlsym(h, names[i]);
        if (!u[i].fn) { fprintf(stderr, "hcrpin: dlsym %s\n", names[i]); return -4; }
        snprintf(hashes[nh % 64], 32, "hcrpin-%lld-%d", (long long)k, i);
        u[i].impl_hash = hashes[nh++ % 64];
        u[i].kind = 0;        /* MARCH_NATIVE */
        u[i].handle = h;      /* owned by the dispatch table from here on */
        u[i].ring_idx = -1;
    }
    void (*init_fn)(uint32_t) = NULL;
    void *raw = dlsym(u[0].handle, "__march_init");
    if (raw) memcpy(&init_fn, &raw, sizeof init_fn);
    if (init_fn) init_fn(march_epoch_next(0));
    march_hcr_wait w;
    int e = march_hcr_activate(u, n, 0, 0, 0, &w);
    if (e <= 0) fprintf(stderr, "hcrpin: deploy %lld -> %d (wait epoch %u pins %lld)\n",
                        (long long)k, e, w.epoch, (long long)w.pins);
    return e;
}

/* How many patch handles the runtime has let go of and kept mapped
 * (march_dispatch_retained_images), or -1 on a runtime without it. */
int64_t hcrpin_retained(void) {
    void *sym = dlsym(RTLD_DEFAULT, "march_dispatch_retained_images");
    if (!sym) return -1;
    uint64_t (*f)(void) = NULL;
    memcpy(&f, &sym, sizeof f);
    return (int64_t)f();
}
