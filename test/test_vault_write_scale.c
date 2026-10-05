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
 * WHAT IS ASSERTED (2026-10-04): a STRUCTURAL property, not wall time.  The
 * old assertion failed only when the parallel median exceeded 1.5x plain
 * serialisation (T * 1.5 * solo), and it still flaked: on ubuntu-24.04's
 * 4-vCPU hosted runners the CORRECT sharded runtime measures 2.6x-5.5x
 * (median ~3.5x over 80 CI runs) against a 4.0x serialisation line, so the
 * hosted hardware barely scales this workload at all and a loaded runner
 * pushed one run to 6.2x.  Worse, under heavy host load a single global lock
 * and the sharded runtime are indistinguishable by wall time -- when threads
 * do not overlap on CPU there is nothing for a lock to serialise.  No
 * wall-time bound separates the two reliably on that hardware.
 *
 * What the test exists to catch is "distinct keys serialise on one lock".
 * That is a property of WHICH locks a write takes, and it can be counted:
 * vault_lock_probe.h is force-included into this runner's runtime build and
 * routes every pthread_mutex_lock through vault_probe_mutex_lock below, which
 * tallies acquisitions per mutex address for each thread's probed writes.
 * The run FAILS if one mutex is acquired on at least half of EVERY thread's
 * writes (a table-wide or global lock is 100%; the 16 bucket shards give each
 * mutex about 1/16 of a thread's 64 keys), or if the probe saw fewer
 * acquisitions than writes (the write path stopped taking a pthread mutex, so
 * the probe can no longer see its lock: update the probe, don't pass
 * silently).  Key hashing is deterministic, so the verdict is too, whatever
 * the host's load or core count.  The timing ratio is still measured and
 * printed -- it is the number the partitioning work was judged by -- but it
 * no longer decides pass/fail. */
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
#define PROBE_WRITES 20000 /* per thread; the probed run only counts locks */
#define KEYS_PER_THREAD 64
#define MAX_THREADS 4
#define NSAMPLES 5
#define PROBE_SLOTS 64 /* distinct mutexes one thread can tally */

static int g_nthreads; /* timing T = min(MAX_THREADS, ncores), set in main() */

static void *g_table;
static void *g_keys[MAX_THREADS][KEYS_PER_THREAD];
static void *g_vals[MAX_THREADS];

/* ── The lock probe (see vault_lock_probe.h) ─────────────────────────────── */

/* This file is compiled with vault_lock_probe.h force-included too, so
 * <pthread.h> above declared the probe, not the real function: drop the
 * macro and declare the real one by hand. */
#undef pthread_mutex_lock
extern int pthread_mutex_lock(pthread_mutex_t *m);

typedef struct {
    pthread_mutex_t *addr[PROBE_SLOTS];
    int64_t          count[PROBE_SLOTS];
    int              nslots;
    int64_t          overflow; /* acquisitions of mutexes past PROBE_SLOTS */
} probe_tally;

static probe_tally g_tally[MAX_THREADS];
/* Set only by a probed writer thread, so runtime-internal locking anywhere
 * else (the main thread's setup, other threads) is never counted. */
static _Thread_local probe_tally *tl_tally;

int vault_probe_mutex_lock(pthread_mutex_t *m) {
    probe_tally *t = tl_tally;
    if (t) {
        int i = 0;
        while (i < t->nslots && t->addr[i] != m) i++;
        if (i < t->nslots) t->count[i]++;
        else if (i < PROBE_SLOTS) { t->addr[i] = m; t->count[i] = 1; t->nslots++; }
        else t->overflow++;
    }
    return pthread_mutex_lock(m);
}

static void *probed_writer(void *arg) {
    int idx = *(int *)arg;
    void *val = g_vals[idx];
    tl_tally = &g_tally[idx];
    for (int i = 0; i < PROBE_WRITES; i++)
        (void)march_vault_set(g_table, g_keys[idx][i % KEYS_PER_THREAD], val);
    tl_tally = NULL;
    return NULL;
}

static int64_t tally_of(const probe_tally *t, pthread_mutex_t *m) {
    for (int i = 0; i < t->nslots; i++)
        if (t->addr[i] == m) return t->count[i];
    return 0;
}

/* ── Timing (printed, not asserted) ──────────────────────────────────────── */

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

static void report_timing(long ncores) {
    if (ncores < 2) {
        fprintf(stderr, "timing: skipped (ncores=%ld < 2 — a parallel-scaling "
                        "number is meaningless on one core)\n", ncores);
        return;
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
            "%.1f = full serialisation; informational, not asserted)\n",
            ncores, g_nthreads, WRITES, KEYS_PER_THREAD, (long long)solo_med,
            (long long)par_med,
            solo_med > 0 ? (double)par_med / (double)solo_med : 0.0,
            (double)g_nthreads);
}

int main(void) {
    long ncores = sysconf(_SC_NPROCESSORS_ONLN);
    g_nthreads = (int)(ncores < MAX_THREADS ? (ncores < 1 ? 1 : ncores) : MAX_THREADS);

    g_table = march_vault_new(march_string_lit("bench-write", 11));
    char buf[32];
    for (int i = 0; i < MAX_THREADS; i++) {
        int vlen = snprintf(buf, sizeof buf, "v%d", i);
        g_vals[i] = march_string_lit(buf, (int64_t)vlen);
        for (int k = 0; k < KEYS_PER_THREAD; k++) {
            int len = snprintf(buf, sizeof buf, "w%d-%d", i, k);
            g_keys[i][k] = march_string_lit(buf, (int64_t)len);
            march_vault_set(g_table, g_keys[i][k], g_vals[i]);
        }
        idxs[i] = i;
    }

    report_timing(ncores);

    /* The structural check always runs MAX_THREADS writers: it counts locks,
     * so it needs neither spare cores nor a quiet host. */
    pthread_t th[MAX_THREADS];
    for (int i = 0; i < MAX_THREADS; i++) pthread_create(&th[i], NULL, probed_writer, &idxs[i]);
    for (int i = 0; i < MAX_THREADS; i++) pthread_join(th[i], NULL);

    int fail = 0;
    for (int i = 0; i < MAX_THREADS; i++) {
        int64_t total = g_tally[i].overflow;
        for (int s = 0; s < g_tally[i].nslots; s++) total += g_tally[i].count[s];
        if (total < PROBE_WRITES) {
            fprintf(stderr,
                    "FAIL: thread %d made %d writes but the probe saw only %lld "
                    "pthread_mutex_lock calls — the write path no longer takes "
                    "a pthread mutex, so this test cannot see its lock; update "
                    "test/vault_lock_probe.h\n",
                    i, PROBE_WRITES, (long long)total);
            fail = 1;
        }
    }

    /* For every mutex thread 0 took: its smallest share of any one thread's
     * writes.  A lock shared by all distinct-key writes scores ~1.0. */
    double worst = 0.0;
    int nmutex = g_tally[0].nslots;
    for (int s = 0; s < g_tally[0].nslots; s++) {
        pthread_mutex_t *m = g_tally[0].addr[s];
        double min_share = 1e9;
        for (int i = 0; i < MAX_THREADS; i++) {
            double share = (double)tally_of(&g_tally[i], m) / (double)PROBE_WRITES;
            if (share < min_share) min_share = share;
        }
        if (min_share > worst) worst = min_share;
        if (min_share >= 0.5) {
            fprintf(stderr,
                    "FAIL: one mutex (%p) is acquired on >= %.0f%% of EVERY "
                    "thread's writes, though each of the %d threads writes "
                    "only its own %d keys — distinct-key writes serialise on "
                    "it\n",
                    (void *)m, min_share * 100.0, MAX_THREADS, KEYS_PER_THREAD);
            fail = 1;
        }
    }
    fprintf(stderr,
            "lock probe: %d threads x %d writes, thread 0 took %d distinct "
            "mutexes; the most-shared one covers %.1f%% of every thread's "
            "writes (fails at 50%%)\n",
            MAX_THREADS, PROBE_WRITES, nmutex, worst * 100.0);
    if (fail) return 1;
    printf("test_vault_write_scale: ok (no lock shared by every thread's "
           "distinct-key writes; most-shared %.1f%%)\n", worst * 100.0);
    return 0;
}
