/* Correctness hammer: 3 reader threads looping march_vault_get() against 1
 * writer thread looping march_vault_set()/march_vault_drop() over the SAME
 * small key set, at the same time. This is the lock's only novel path —
 * no test before this one ever ran a writer's drain against concurrent
 * readers — and it is what would catch a future breakage of the exclusion
 * protocol (see the EXCLUSION MEMORY ORDERING comment on vault_rwlock_t /
 * vault_rd_lock in runtime/march_extras.c).
 *
 * NO TIMING ASSERTION — this belongs in `runtest`, unlike
 * test_vault_distinct_keys_scale.c's `vault-scale` alias, precisely because
 * it makes no wall-clock claim and so cannot be sensitive to host load. The
 * oracles are the runtime's own safety checks, which are free:
 *   - march_vault_drop unlinks and frees a node's key and, once its
 *     refcount reaches zero, its value. If a reader's march_incrc(n->value)
 *     ever raced a concurrent drop's march_decrc/free of that same value —
 *     i.e. if the lock's exclusion ever failed to keep a reader and a
 *     writer out of the table at the same time — the result is a
 *     use-after-free: a torn read, a wrong value, or a crash (SIGSEGV) from
 *     dereferencing freed memory copied from a `free`d bucket.
 *   - Every march_incrc/march_decrc pair is exactly matched here (readers
 *     decrc what they get; the writer decrc's its own extra reference right
 *     after each march_vault_set, so march_vault_drop's later decrc is what
 *     actually frees the value — exercising the real free path repeatedly,
 *     not a leak that never reaches zero). A locking bug that lets two
 *     operations touch the same node concurrently without the required
 *     exclusion tends to show up as a double-decrement: march_runtime.c's
 *     march_decrc aborts the process with "RC underflow" (see ~line 349)
 *     rather than silently corrupting state, so a race here is expected to
 *     crash loudly, not produce a subtly wrong final count.
 * Assert clean completion (all threads join, no crash) and a sane final
 * state (table size bounded by the key set, march_vault_keys() doesn't
 * crash building its result list). */
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

extern void *march_vault_new(void *name);
extern void *march_vault_set(void *t, void *k, void *v);
extern void *march_vault_get(void *t, void *k);
extern void *march_vault_drop(void *t, void *k);
extern int64_t march_vault_size(void *t);
extern void *march_vault_keys(void *t);
extern void *march_alloc(int64_t);
extern void *march_string_lit(const char *utf8, int64_t len);
extern void  march_decrc(void *p);

#define N_KEYS 4
#define N_READERS 3
#define READS_PER_THREAD 300000
#define WRITE_ITERS 200000

static void *g_table;
static void *g_keys[N_KEYS];

static void *reader_fn(void *arg) {
    (void)arg;
    for (int i = 0; i < READS_PER_THREAD; i++) {
        void *key = g_keys[i % N_KEYS];
        /* march_vault_get returns a niche-encoded Option(ptr): None = NULL,
         * Some(v) = v itself, already incrc'd under the read lock. */
        void *v = march_vault_get(g_table, key);
        if (v) march_decrc(v);
    }
    return NULL;
}

static void *writer_fn(void *arg) {
    (void)arg;
    for (int i = 0; i < WRITE_ITERS; i++) {
        int k = i % N_KEYS;
        if ((i / N_KEYS) % 2 == 0) {
            /* march_vault_set takes its own reference (incrc); release our
             * local one immediately so the entry's refcount reaches exactly
             * 1 (Vault's own hold) — meaning the later drop() below actually
             * frees it, rather than leaving a permanently-leaked extra ref
             * that never exercises the free path. */
            void *val = march_string_lit("w", 1);
            march_vault_set(g_table, g_keys[k], val);
            march_decrc(val);
        } else {
            march_vault_drop(g_table, g_keys[k]);
        }
    }
    return NULL;
}

int main(void) {
    g_table = march_vault_new(march_string_lit("hammer", 6));

    char buf[16];
    for (int k = 0; k < N_KEYS; k++) {
        int len = snprintf(buf, sizeof buf, "hk%d", k);
        g_keys[k] = march_string_lit(buf, (int64_t)len);
        void *val = march_string_lit("initial", 7);
        march_vault_set(g_table, g_keys[k], val);
        march_decrc(val);
    }

    pthread_t readers[N_READERS];
    pthread_t writer;
    for (int i = 0; i < N_READERS; i++)
        pthread_create(&readers[i], NULL, reader_fn, NULL);
    pthread_create(&writer, NULL, writer_fn, NULL);

    for (int i = 0; i < N_READERS; i++) pthread_join(readers[i], NULL);
    pthread_join(writer, NULL);

    /* Sane final state: size is bounded by the key set (each key is either
     * present or dropped, never duplicated, never negative), and building
     * the keys list doesn't crash walking whatever nodes remain. */
    int64_t final_size = march_vault_size(g_table);
    fprintf(stderr, "test_vault_hammer: final_size=%lld (of %d keys)\n",
            (long long)final_size, N_KEYS);
    assert(final_size >= 0 && final_size <= N_KEYS);

    void *keys_list = march_vault_keys(g_table);
    (void)keys_list; /* just needs to not crash building the list */

    printf("test_vault_hammer: all passed\n");
    return 0;
}
