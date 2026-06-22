/* march_remote_registry.c — function-by-identity registry (Distributed OTP L4).
 * See march_remote_registry.h for the contract.
 *
 * A chained hash table keyed by the impl_hash string. Registration happens at
 * @main startup (single-threaded); lookups happen while handling inbound calls
 * (potentially on multiple scheduler threads), so every operation is guarded by
 * one mutex. The table is read-mostly and small (one entry per enrolled target),
 * so a single lock is ample; a reader/writer lock is a later optimization.
 */
#include "march_remote_registry.h"

#include <stdlib.h>
#include <string.h>
#include <pthread.h>

typedef struct remote_entry {
    char                 *impl_hash;   /* owned copy (table key) */
    char                 *sig_hash;    /* owned copy */
    void                 *stub;        /* marshalling stub entry point */
    struct remote_entry  *next;        /* chain within a bucket */
} remote_entry;

#ifndef MARCH_REMOTE_BUCKETS
#define MARCH_REMOTE_BUCKETS 64        /* power of two; mask = BUCKETS - 1 */
#endif

static remote_entry    *g_buckets[MARCH_REMOTE_BUCKETS];
static size_t           g_count;
static pthread_mutex_t  g_lock = PTHREAD_MUTEX_INITIALIZER;

/* FNV-1a over the NUL-terminated key. */
static size_t hash_key(const char *s) {
    size_t h = (size_t)1469598103934665603ULL;
    for (; *s; s++) {
        h ^= (size_t)(unsigned char)*s;
        h *= (size_t)1099511628211ULL;
    }
    return h & (MARCH_REMOTE_BUCKETS - 1);
}

static char *dup_str(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

/* Caller holds g_lock. Find the entry for [impl_hash] in its bucket, or NULL. */
static remote_entry *find_locked(const char *impl_hash, size_t bucket) {
    remote_entry *e = g_buckets[bucket];
    while (e) {
        if (strcmp(e->impl_hash, impl_hash) == 0) return e;
        e = e->next;
    }
    return NULL;
}

static void free_entry(remote_entry *e) {
    free(e->impl_hash);
    free(e->sig_hash);
    free(e);
}

void march_remote_init(void) {
    pthread_mutex_lock(&g_lock);
    for (size_t i = 0; i < MARCH_REMOTE_BUCKETS; i++) {
        remote_entry *e = g_buckets[i];
        while (e) {
            remote_entry *next = e->next;
            free_entry(e);
            e = next;
        }
        g_buckets[i] = NULL;
    }
    g_count = 0;
    pthread_mutex_unlock(&g_lock);
}

void march_remote_shutdown(void) {
    march_remote_init();   /* same teardown; leaves an empty, reusable table */
}

int march_remote_register(const char *impl_hash, const char *sig_hash,
                          void *stub) {
    if (!impl_hash || !stub) return -1;
    pthread_mutex_lock(&g_lock);
    size_t bucket = hash_key(impl_hash);
    remote_entry *e = find_locked(impl_hash, bucket);
    if (e) {
        /* Idempotent on identity: replace the stub + sig_hash in place. */
        char *new_sig = dup_str(sig_hash);
        if (sig_hash && !new_sig) { pthread_mutex_unlock(&g_lock); return -1; }
        free(e->sig_hash);
        e->sig_hash = new_sig;
        e->stub = stub;
        pthread_mutex_unlock(&g_lock);
        return 0;
    }
    e = (remote_entry *)calloc(1, sizeof(remote_entry));
    if (!e) { pthread_mutex_unlock(&g_lock); return -1; }
    e->impl_hash = dup_str(impl_hash);
    e->sig_hash  = dup_str(sig_hash);
    if (!e->impl_hash || (sig_hash && !e->sig_hash)) {
        free_entry(e);
        pthread_mutex_unlock(&g_lock);
        return -1;
    }
    e->stub = stub;
    e->next = g_buckets[bucket];
    g_buckets[bucket] = e;
    g_count++;
    pthread_mutex_unlock(&g_lock);
    return 0;
}

void *march_remote_lookup(const char *impl_hash) {
    if (!impl_hash) return NULL;
    pthread_mutex_lock(&g_lock);
    remote_entry *e = find_locked(impl_hash, hash_key(impl_hash));
    void *stub = e ? e->stub : NULL;
    pthread_mutex_unlock(&g_lock);
    return stub;
}

const char *march_remote_sig_hash(const char *impl_hash) {
    if (!impl_hash) return NULL;
    pthread_mutex_lock(&g_lock);
    remote_entry *e = find_locked(impl_hash, hash_key(impl_hash));
    const char *sig = e ? e->sig_hash : NULL;
    pthread_mutex_unlock(&g_lock);
    return sig;
}

int march_remote_has(const char *impl_hash) {
    return march_remote_lookup(impl_hash) != NULL;
}

size_t march_remote_count(void) {
    pthread_mutex_lock(&g_lock);
    size_t n = g_count;
    pthread_mutex_unlock(&g_lock);
    return n;
}
