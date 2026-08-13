/* This is what Task 1's striped reader-count lock (vault_rwlock_t in
 * runtime/march_extras.c) actually governs: four threads reading DISTINCT
 * keys (and therefore distinct values — no shared refcount) from the same
 * table should scale close to 1x, because each reader hashes to its own
 * cache-line-isolated stripe and no two readers RMW the same word.
 *
 * Contrast with test_vault_concurrency.c, which has all four threads read
 * the SAME key and is dominated by march_incrc contention on that key's one
 * shared value — a real cost, but not a table-lock cost, and not what this
 * test measures. This test's tight bound is only possible because that
 * confound is removed: each thread's value object is distinct, so no
 * refcount field is shared across threads.
 *
 * THIS TEST RUNS ON ITS OWN `vault-scale` ALIAS, NOT `runtest` — see the
 * comment in test/dune for why (it's a parallel-scaling benchmark, sensitive
 * to core availability, and this repo's dev boxes routinely run several
 * other sessions' compiles/benchmarks concurrently). Run it deliberately
 * with `dune build @vault-scale`, ideally on an otherwise-quiet box. A
 * failure here on a loaded box is expected and is not, by itself, evidence
 * of a regression — re-run on a quiet one before concluding anything.
 *
 * READS=1,000,000 (not 200,000): at 200K, solo runs at ~9ms — close enough
 * to the 1ms wall-clock quantization that the four/solo ratio flaked ~25%
 * of the time (observed 1.7x-3.6x across 20 runs at the 3x bound, same
 * quantization problem test_vault_concurrency.c hit at 200K). 1M reads
 * tightened it, but even then a single (solo, four-thread) sample pair
 * flaked 2/40 runs across two 20-run batches, both times at just over 3x and
 * both coinciding with `uptime` load averages of ~19-20 on this 14-core box.
 * Root cause was a load spike landing on a single sample, not the lock; see
 * ROUND 3 below.
 *
 * ROUND 3 — median-of-N, not a single sample: both phases now run N=5 times
 * and the assertion compares MEDIANS. A median is immune to any one run (in
 * either phase) landing during a load spike, without loosening the bound —
 * loosening would hide a real regression exactly as easily as it hides a
 * load spike. This closed most of the gap: 20/20 same-key runs, but the
 * distinct-key test still hit 1/20 (four-median 133ms vs. solo-median 43ms
 * — 3.09x), with all five four-thread samples that run elevated TOGETHER
 * (125-142ms) against a rock-flat solo (42-44ms). A within-run median can't
 * fix a whole-run contention window — that's core availability during the
 * parallel phase, not tail latency in the lock. Confirmed by cross-run
 * pattern: the very next run also spiked (134ms, 2.98x, just passed), i.e.
 * two runs seconds apart both elevated — consistent with a real host
 * contention window, not per-run randomness in the lock itself.
 *
 * ROUND 4 — moved to its own alias instead of chasing the bound further: a
 * parallel-scaling assertion is a benchmark, not a unit test (same
 * reasoning as this repo's `types-check`/`grammar-check`/
 * `stdlib-march-properties` own-alias precedents in test/dune), so it no
 * longer needs to be green under arbitrary host load on every PR.
 *
 * Measured figures, this repo's 14-core dev box, box under concurrent load
 * from other sessions throughout (see "bench load contamination" in project
 * memory) — kept here so the next reader doesn't have to re-derive them:
 *   - original exclusive pthread_mutex_t:                ~9.5x
 *   - pthread_rwlock_t (rejected — Darwin pathology, see march_extras.c): ~18x
 *   - single hand-rolled atomic reader count (round 1):    5.6x-7.0x
 *   - striped reader counters, SAME key (test_vault_concurrency.c):
 *     5.7x-6.5x — refcount-bound, not lock-bound, see that file
 *   - striped reader counters, DISTINCT keys (this test): median ~2.0x,
 *     with a 63-134ms four-thread wall-time spread across 20 runs under
 *     host load (solo held flat at 42-45ms) — this is what the striped
 *     lock actually buys over a single counter. A single shared counter
 *     cannot reach this regardless of implementation quality: every reader
 *     RMWs the same cache line, which is exactly the bottleneck striping
 *     removes. */
#include <assert.h>
#include <pthread.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

extern void *march_vault_new(void *name);
extern void *march_vault_set(void *t, void *k, void *v);
extern void *march_vault_get(void *t, void *k);
extern void *march_alloc(int64_t);
extern void *march_string_lit(const char *utf8, int64_t len);

#define READS 1000000
#define NTHREADS 4
#define NSAMPLES 5

static void *g_table;
static void *g_keys[NTHREADS];

static int64_t now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void *reader(void *arg) {
    int idx = *(int *)arg;
    for (int i = 0; i < READS; i++) (void)march_vault_get(g_table, g_keys[idx]);
    return NULL;
}

static int idxs[NTHREADS];

static int64_t run_solo(void) {
    int64_t t0 = now_ms();
    reader(&idxs[0]);
    return now_ms() - t0;
}

static int64_t run_four_threads(void) {
    pthread_t th[NTHREADS];
    int64_t t0 = now_ms();
    for (int i = 0; i < NTHREADS; i++) pthread_create(&th[i], NULL, reader, &idxs[i]);
    for (int i = 0; i < NTHREADS; i++) pthread_join(th[i], NULL);
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
    g_table = march_vault_new(march_string_lit("bench-distinct", 14));
    char buf[16];
    for (int i = 0; i < NTHREADS; i++) {
        int len = snprintf(buf, sizeof buf, "k%d", i);
        g_keys[i] = march_string_lit(buf, (int64_t)len);
        march_vault_set(g_table, g_keys[i], march_string_lit("v", 1));
        idxs[i] = i;
    }

    int64_t solo_samples[NSAMPLES], four_samples[NSAMPLES];
    for (int i = 0; i < NSAMPLES; i++) solo_samples[i] = run_solo();
    for (int i = 0; i < NSAMPLES; i++) four_samples[i] = run_four_threads();

    /* median_of() sorts in place; keep unsorted copies for the failure
     * diagnostic printout below. */
    int64_t solo_sorted[NSAMPLES], four_sorted[NSAMPLES];
    for (int i = 0; i < NSAMPLES; i++) solo_sorted[i] = solo_samples[i];
    for (int i = 0; i < NSAMPLES; i++) four_sorted[i] = four_samples[i];
    int64_t solo_med = median_of(solo_sorted, NSAMPLES);
    int64_t four_med = median_of(four_sorted, NSAMPLES);

    fprintf(stderr, "solo_median=%lldms four_median=%lldms\n",
            (long long)solo_med, (long long)four_med);
    /* Guard against a zero-length solo run on a very fast box. */
    if (solo_med < 5) { printf("test_vault_distinct_keys_scale: skipped (too fast to time)\n"); return 0; }

    int ok = (four_med < solo_med * 3);
    if (!ok) {
        fprintf(stderr, "test_vault_distinct_keys_scale: FAILED — four_median (%lldms) "
                "not < solo_median (%lldms) * 3\n",
                (long long)four_med, (long long)solo_med);
        print_samples("solo", solo_samples, NSAMPLES);
        print_samples("four-threads", four_samples, NSAMPLES);
    }
    assert(ok);
    printf("test_vault_distinct_keys_scale: all passed\n");
    return 0;
}
