/* Does a Vault WRITE to an unrelated key serialise against another thread's
 * write?  This harness answers that with a number, and exists because item 2
 * of specs/todos/2026-08-12-vault-toward-ets-semantics.md said plainly: do not
 * partition the per-table write lock speculatively, measure a workload that
 * serialises on it first.  It is the writer twin of
 * test_vault_distinct_keys_scale.c (which measures the striped READ lock item
 * 1 shipped), with the same shape: distinct keys per thread, median-of-N,
 * core-adaptive thread count, and the same `vault-scale` alias rather than
 * `runtest` -- a parallel-scaling number is a benchmark, sensitive to core
 * availability, and this repo's dev boxes routinely run other sessions' work
 * concurrently (see "bench load contamination" in the project's notes).
 *
 * MEASURED, this repo's 14-core dev box, T=4, same harness both sides
 * (specs/progress/2026-09-20-vault-write-partitioning.md):
 *   - one exclusive lock per table (before):  11.8x - 13.1x  (165-183ms vs 14ms)
 *   - lock sharded by bucket (after):          2.5x -  3.2x  (37-45ms vs 14ms)
 * Both sides move with host load -- a later sample on a box busy with other
 * suites put the sharded runtime at 4.2x -- so the pair above was taken back
 * to back on the same box, and any re-measurement should be too.
 *
 * Full serialisation would be 4.0x, so the before-figure was THREE TIMES
 * worse than serialising: each vault_wr_lock also stores the writer flag and
 * drains all VAULT_RD_STRIPES reader counters, so four writers bounced those
 * cache lines against each other on top of queueing on the one mutex.
 *
 * WRITES is far smaller than the reader test's READS: a write allocates, takes
 * a lock, and mutates the table, so it is much more expensive per op --
 * 200,000 per thread already puts a solo run well clear of the millisecond
 * quantization that forced the reader test up to 1,000,000.
 *
 * Each thread rewrites ITS OWN pre-inserted keys, so the table's bucket count
 * and total size stay fixed for the whole run: this measures the lock, not
 * table growth or rehashing.  Two details are what make the number mean
 * "lock", both copied from the reader test's discipline:
 *
 *  - Each thread stores its OWN value object.  Sharing one value across
 *    threads makes every write RMW that one object's refcount field
 *    (march_incrc on the new value, march_decrc on the displaced one), and
 *    that contention -- not the table lock -- then dominates: on the SHARDED
 *    runtime, a shared value measured 6.7x-8.2x where per-thread values
 *    measure 2.5x-3.2x.  It is the same confound test_vault_concurrency.c
 *    documents for same-key reads.
 *  - Each thread cycles over KEYS_PER_THREAD keys rather than one.  A single
 *    key per thread lands in a single bucket, hence a single shard, so
 *    whether two threads collide would be a coin flip that moves the result
 *    more than the lock does.
 *
 * The residual ~2.5x-3.2x is NOT shard collision: 16, 32 and 64 shards all
 * measure the same within noise.  It is the per-write costs that are shared
 * whatever the lock does -- malloc/free of the key's C-string copy and the
 * Unit return allocation, both of which take the allocator's own locks.
 * Reducing those is a separate piece of work; this item was about the lock.
 *
 * The assertion stays loose (it fails only if the result is WORSE than plain
 * serialisation) because the printed ratio is the deliverable and a tight
 * bound on a parallel-scaling number is exactly what made the reader test
 * flake for four rounds.  A regression back to one lock per table fails it:
 * that measured 11.8x-13.1x against a bound of T * 1.5 = 6.0x. */
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

extern void *march_vault_new(void *name);
extern void *march_vault_set(void *t, void *k, void *v);
extern void *march_alloc(int64_t);
extern void *march_string_lit(const char *utf8, int64_t len);

#define WRITES 200000
#define KEYS_PER_THREAD 64
#define MAX_THREADS 4
#define NSAMPLES 5

static int g_nthreads; /* T = min(MAX_THREADS, ncores), set in main() */

static void *g_table;
static void *g_keys[MAX_THREADS][KEYS_PER_THREAD];
static void *g_vals[MAX_THREADS];

static int64_t now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void *writer(void *arg) {
    int idx = *(int *)arg;
    void *val = g_vals[idx];
    for (int i = 0; i < WRITES; i++)
        (void)march_vault_set(g_table, g_keys[idx][i % KEYS_PER_THREAD], val);
    return NULL;
}

static int idxs[MAX_THREADS];

static int64_t run_solo(void) {
    int64_t t0 = now_ms();
    writer(&idxs[0]);
    return now_ms() - t0;
}

static int64_t run_parallel_threads(void) {
    pthread_t th[MAX_THREADS];
    int64_t t0 = now_ms();
    for (int i = 0; i < g_nthreads; i++) pthread_create(&th[i], NULL, writer, &idxs[i]);
    for (int i = 0; i < g_nthreads; i++) pthread_join(th[i], NULL);
    return now_ms() - t0;
}

static int cmp_i64(const void *a, const void *b) {
    int64_t x = *(const int64_t *)a, y = *(const int64_t *)b;
    return (x > y) - (x < y);
}

static int64_t median_of(int64_t *samples, int n) {
    qsort(samples, (size_t)n, sizeof(int64_t), cmp_i64);
    return samples[n / 2];
}

static void print_samples(const char *label, int64_t *samples, int n) {
    fprintf(stderr, "%s samples (ms):", label);
    for (int i = 0; i < n; i++) fprintf(stderr, " %lld", (long long)samples[i]);
    fprintf(stderr, "\n");
}

int main(void) {
    long ncores = sysconf(_SC_NPROCESSORS_ONLN);
    if (ncores < 2) {
        printf("test_vault_write_scale: skipped (ncores=%ld < 2 — a "
               "parallel-scaling measurement is meaningless on one core)\n",
               ncores);
        return 0;
    }
    g_nthreads = (int)(ncores < MAX_THREADS ? ncores : MAX_THREADS);

    g_table = march_vault_new(march_string_lit("bench-write", 11));
    char buf[32];
    for (int i = 0; i < g_nthreads; i++) {
        int vlen = snprintf(buf, sizeof buf, "v%d", i);
        g_vals[i] = march_string_lit(buf, (int64_t)vlen);
        for (int k = 0; k < KEYS_PER_THREAD; k++) {
            int len = snprintf(buf, sizeof buf, "w%d-%d", i, k);
            g_keys[i][k] = march_string_lit(buf, (int64_t)len);
            march_vault_set(g_table, g_keys[i][k], g_vals[i]);
        }
        idxs[i] = i;
    }

    int64_t solo_samples[NSAMPLES], par_samples[NSAMPLES];
    for (int i = 0; i < NSAMPLES; i++) solo_samples[i] = run_solo();
    for (int i = 0; i < NSAMPLES; i++) par_samples[i] = run_parallel_threads();

    /* median_of() sorts in place; keep unsorted copies for the printout. */
    int64_t solo_sorted[NSAMPLES], par_sorted[NSAMPLES];
    for (int i = 0; i < NSAMPLES; i++) solo_sorted[i] = solo_samples[i];
    for (int i = 0; i < NSAMPLES; i++) par_sorted[i] = par_samples[i];
    int64_t solo_med = median_of(solo_sorted, NSAMPLES);
    int64_t par_med = median_of(par_sorted, NSAMPLES);

    print_samples("solo    ", solo_samples, NSAMPLES);
    print_samples("parallel", par_samples, NSAMPLES);
    fprintf(stderr,
            "ncores=%ld T=%d writes/thread=%d keys/thread=%d solo_median=%lldms "
            "parallel_median=%lldms ratio=%.2f (1.0 = perfect scaling, "
            "%.1f = full serialisation)\n",
            ncores, g_nthreads, WRITES, KEYS_PER_THREAD, (long long)solo_med,
            (long long)par_med,
            solo_med > 0 ? (double)par_med / (double)solo_med : 0.0,
            (double)g_nthreads);

    if (solo_med < 5) {
        printf("test_vault_write_scale: skipped (too fast to time)\n");
        return 0;
    }
    /* Loose by design: only a result WORSE than plain serialisation fails.
       The number above is the deliverable. */
    double bound = (double)solo_med * (double)g_nthreads * 1.5;
    if ((double)par_med >= bound) {
        fprintf(stderr,
                "FAIL: %d threads writing distinct keys took %lldms vs %lldms "
                "solo — worse than serialisation (bound %.0fms)\n",
                g_nthreads, (long long)par_med, (long long)solo_med, bound);
        return 1;
    }
    printf("test_vault_write_scale: ok (ratio %.2f over %d threads)\n",
           solo_med > 0 ? (double)par_med / (double)solo_med : 0.0, g_nthreads);
    return 0;
}
