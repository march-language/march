/* HCR Phase 0 spike -- THROWAWAY, not wired into the product or CI.
 *
 * In-process hot swap driver: does what the reload server's ACTIVATE verb
 * (runtime/march_reload.c, activate_items) does, minus the socket, signing,
 * CAS and audit log, so a single March program can swap one of its own
 * boundary functions mid-run and keep using values across the swap.
 *
 *   hcr0_swap(k)  dlopens $HCR0_PATCH_<k>, calls its __march_init, and
 *                 activates every slot named in $HCR0_NAMES (comma list) as
 *                 ONE deploy via march_hcr_activate.  Returns the deploy's
 *                 epoch (> 0), or a negative error code.
 *   hcr0_versions(name_k) number of live ring versions of slot k in HCR0_NAMES.
 */
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
int      march_dispatch_live(uint32_t name_id, uint32_t version);

#define MAXN 8

static int split_names(char *buf, char **names) {
    int n = 0;
    for (char *t = strtok(buf, ","); t && n < MAXN; t = strtok(NULL, ",")) names[n++] = t;
    return n;
}

void march_dispatch_set_close_hook(void (*hook)(void *handle));
static int g_unloads = 0;
static void count_close(void *h) { g_unloads++; dlclose(h); }
static void keep_loaded(void *h) { (void)h; g_unloads++; }

int64_t hcr0_swap(int64_t k) {
    static int hooked = 0;
    if (!hooked) {
        hooked = 1;
        /* HCR0_NO_UNLOAD=1: a reclaimed version's .so stays mapped (the A/B
         * control for the code-unload experiment). */
        const char *nu = getenv("HCR0_NO_UNLOAD");
        march_dispatch_set_close_hook(nu && *nu == '1' ? keep_loaded : count_close);
    }
    char var[64];
    snprintf(var, sizeof var, "HCR0_PATCH_%lld", (long long)k);
    const char *path = getenv(var);
    const char *names_env = getenv("HCR0_NAMES");
    if (!path || !names_env) return -1;   /* no k-th patch: nothing to do */
    void *h = dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    if (!h) { fprintf(stderr, "hcr0: dlopen %s: %s\n", path, dlerror()); return -2; }
    char buf[512]; snprintf(buf, sizeof buf, "%s", names_env);
    char *names[MAXN]; int n = split_names(buf, names);
    march_hcr_unit u[MAXN]; memset(u, 0, sizeof u);
    static char hashes[64][32]; static int nh = 0;
    for (int i = 0; i < n; i++) {
        if (!march_dispatch_name_to_id(names[i], &u[i].slot)) {
            fprintf(stderr, "hcr0: no slot %s\n", names[i]); return -3;
        }
        u[i].fn = dlsym(h, names[i]);
        if (!u[i].fn) { fprintf(stderr, "hcr0: dlsym %s\n", names[i]); return -4; }
        snprintf(hashes[nh % 64], 32, "spike-%lld-%d", (long long)k, i);
        u[i].impl_hash = hashes[nh++ % 64];
        u[i].kind = 0; /* MARCH_NATIVE */
        u[i].handle = h;   /* the dispatch table now owns (and may dlclose) it */
        u[i].ring_idx = -1;
    }
    void (*init_fn)(uint32_t) = NULL;
    void *raw = dlsym(h, "__march_init");
    if (raw) memcpy(&init_fn, &raw, sizeof init_fn);
    if (init_fn) init_fn(march_epoch_next(0));
    /* Extra dlopen refs so the table's dlclose of a reclaimed version only
     * drops the last ref once every slot that shares the handle let go. */
    for (int i = 1; i < n; i++) dlopen(path, RTLD_NOW | RTLD_GLOBAL);
    march_hcr_wait w;
    int e = march_hcr_activate(u, n, 0, 0, 0, &w);
    fprintf(stderr, "hcr0: swap %lld (%s) -> epoch %d; reclaimed (dlclose) handles so far: %d\n",
            (long long)k, path, e, g_unloads);
    if (e <= 0) fprintf(stderr, "hcr0: activate -> %d (wait epoch %u pins %lld)\n",
                        e, w.epoch, (long long)w.pins);
    return e;
}

int64_t hcr0_versions(int64_t k) {
    const char *names_env = getenv("HCR0_NAMES");
    if (!names_env) return -1;
    char buf[512]; snprintf(buf, sizeof buf, "%s", names_env);
    char *names[MAXN]; int n = split_names(buf, names);
    if (k < 0 || k >= n) return -1;
    uint32_t id; if (!march_dispatch_name_to_id(names[k], &id)) return -1;
    int live = 0;
    for (uint32_t v = 0; v < 3; v++) live += march_dispatch_live(id, v);
    return live;
}
