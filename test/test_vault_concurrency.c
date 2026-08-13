/* Many readers of ONE key. This test guards against a catastrophic
 * regression (e.g. back to an exclusive lock) — it does NOT measure lock
 * quality, and its ratio must not be read as "how well does Vault's table
 * lock scale." See test_vault_distinct_keys_scale.c for that.
 *
 * Why the same key can't approach 1x no matter how good the table lock is:
 * every march_vault_get call does march_incrc(n->value) on the *returned
 * value's own refcount field*. When every reader thread fetches the same
 * key, they all bump the SAME value's refcount — an atomic RMW on one
 * shared cache line, contended across cores independent of whatever guards
 * the table. Table-lock quality and refcount-bump contention are two
 * different costs; this test's shape conflates them, which is exactly why
 * its bound is loose and test_vault_distinct_keys_scale.c exists to isolate
 * the one this task is actually about.
 *
 * Measured on this repo's 14-core dev box (READS=1,000,000/thread; box runs
 * other CPU-bound sessions concurrently, so treat absolute numbers as noisy
 * — see "bench load contamination" in project memory):
 *   - original exclusive pthread_mutex_t:            ~9.5x
 *   - pthread_rwlock_t (rejected, see march_extras.c): ~18x  (Darwin pathology)
 *   - single hand-rolled atomic reader count:          5.6x-7.0x
 *   - striped reader counters (shipped):               5.7x-6.5x  <- this test
 *   - striped, but each thread reads a DISTINCT key:    2.75x-3.11x (see the
 *     other test — this is what the striped lock actually buys)
 *   - diagnostic only, never shipped: same key with the march_incrc call
 *     temporarily removed from march_vault_get to isolate the refcount cost:
 *     ~1.5x-2.0x
 * The striped-lock same-key number (5.7x-6.5x) barely moved from the
 * single-counter number (5.6x-7.0x) *because the table lock was never the
 * bottleneck in this shape* — the distinct-key numbers above are the actual
 * before/after for the table lock itself.
 *
 * 9x is roughly the ORIGINAL mutex's ratio: the bar here is "never worse
 * than where we started," not "scales well" — that claim belongs to
 * test_vault_distinct_keys_scale.c. */
#include <assert.h>
#include <pthread.h>
#include <stdio.h>
#include <stdint.h>
#include <time.h>

extern void *march_vault_new(void *name);
extern void *march_vault_set(void *t, void *k, void *v);
extern void *march_vault_get(void *t, void *k);
extern void *march_alloc(int64_t);
extern void *march_string_lit(const char *utf8, int64_t len);

#define READS 1000000

static void *g_table;
static void *g_key;

static int64_t now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void *reader(void *arg) {
    (void)arg;
    for (int i = 0; i < READS; i++) (void)march_vault_get(g_table, g_key);
    return NULL;
}

int main(void) {
    g_table = march_vault_new(march_string_lit("bench", 5));
    g_key   = march_string_lit("k", 1);
    march_vault_set(g_table, g_key, march_string_lit("v", 1));

    int64_t t0 = now_ms();
    reader(NULL);
    int64_t solo = now_ms() - t0;

    pthread_t th[4];
    t0 = now_ms();
    for (int i = 0; i < 4; i++) pthread_create(&th[i], NULL, reader, NULL);
    for (int i = 0; i < 4; i++) pthread_join(th[i], NULL);
    int64_t four = now_ms() - t0;

    fprintf(stderr, "solo=%lldms four-threads=%lldms\n",
            (long long)solo, (long long)four);
    /* Guard against a zero-length solo run on a very fast box. */
    if (solo < 5) { printf("test_vault_concurrency: skipped (too fast to time)\n"); return 0; }
    assert(four < solo * 9);
    printf("test_vault_concurrency: all passed\n");
    return 0;
}
