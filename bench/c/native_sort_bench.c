/* native_sort_bench.c — standalone measurement for the NativeArray.sort_int spec
 * (specs/todos/2026-09-16-native-array-sort-ipnsort.md). Not part of the runtime;
 * build with: cc -O2 -fno-strict-aliasing -fwrapv -o /tmp/nsb bench/c/native_sort_bench.c && /tmp/nsb [quick]
 *
 * Four i64 sorts over eight input patterns at three sizes, compiled with the
 * same flags the March runtime uses (cc -O2 -fno-strict-aliasing -fwrapv).
 *
 *   qsort     libc, comparator through a function pointer (the "do nothing" option)
 *   intro     naive introsort: median-of-3, branchy Hoare, insertion <=16, heapsort fallback
 *   ipn       ipnsort-style: full-run scan, pseudo-median-of-9, branchless Lomuto,
 *             equal-partition on repeated pivot, network+insertion small-sort, heapsort fallback
 *   radix     LSD radix, 8 passes of 8 bits, O(n) scratch (the other real contender for bare i64)
 *
 * Every timed run is checked against qsort's output (memcmp), so a wrong sort
 * fails loudly instead of winning the benchmark.
 */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>
#include <time.h>
#include <math.h>

typedef int64_t i64;

/* ---------- rng ---------- */
static uint64_t rng_state = 0x9E3779B97F4A7C15ULL;
static uint64_t rng(void) {
    uint64_t x = rng_state;
    x ^= x << 13; x ^= x >> 7; x ^= x << 17;
    rng_state = x;
    return x;
}

/* ---------- qsort ---------- */
static int cmp_i64(const void *a, const void *b) {
    i64 x = *(const i64 *)a, y = *(const i64 *)b;
    return (x > y) - (x < y);
}
static void sort_qsort(i64 *v, size_t n) { qsort(v, n, sizeof(i64), cmp_i64); }

/* ---------- shared pieces ---------- */
static inline void swap64(i64 *a, i64 *b) { i64 t = *a; *a = *b; *b = t; }

static void heapsort_i64(i64 *v, size_t n) {
    /* sift-down heapsort; only reached on adversarial recursion depth */
    for (size_t start = n / 2; start-- > 0;) {
        size_t root = start;
        for (;;) {
            size_t child = 2 * root + 1;
            if (child >= n) break;
            if (child + 1 < n && v[child] < v[child + 1]) child++;
            if (v[root] >= v[child]) break;
            swap64(&v[root], &v[child]);
            root = child;
        }
    }
    for (size_t end = n; end-- > 1;) {
        swap64(&v[0], &v[end]);
        size_t root = 0;
        for (;;) {
            size_t child = 2 * root + 1;
            if (child >= end) break;
            if (child + 1 < end && v[child] < v[child + 1]) child++;
            if (v[root] >= v[child]) break;
            swap64(&v[root], &v[child]);
            root = child;
        }
    }
}

static void insertion_i64(i64 *v, size_t n) {
    for (size_t i = 1; i < n; i++) {
        i64 x = v[i];
        size_t j = i;
        while (j > 0 && v[j - 1] > x) { v[j] = v[j - 1]; j--; }
        v[j] = x;
    }
}

static inline size_t log2_floor(size_t n) {
    size_t r = 0;
    while (n >>= 1) r++;
    return r;
}

/* ---------- naive introsort ---------- */
static void intro_rec(i64 *v, size_t n, int limit) {
    while (n > 16) {
        if (limit == 0) { heapsort_i64(v, n); return; }
        limit--;
        /* median of 3 into v[n/2] */
        size_t m = n / 2;
        if (v[m] < v[0]) swap64(&v[m], &v[0]);
        if (v[n - 1] < v[0]) swap64(&v[n - 1], &v[0]);
        if (v[n - 1] < v[m]) swap64(&v[n - 1], &v[m]);
        i64 pivot = v[m];
        /* branchy Hoare */
        size_t i = 0, j = n - 1;
        for (;;) {
            while (v[i] < pivot) i++;
            while (v[j] > pivot) j--;
            if (i >= j) break;
            swap64(&v[i], &v[j]);
            i++; j--;
        }
        size_t cut = j + 1;
        intro_rec(v, cut, limit);
        v += cut; n -= cut;
    }
    insertion_i64(v, n);
}
static void sort_intro(i64 *v, size_t n) {
    if (n < 2) return;
    intro_rec(v, n, (int)(2 * log2_floor(n)));
}

/* ---------- ipnsort-style ---------- */
#define IPN_SMALL 32

/* branchless compare-exchange */
#define CSWAP(a, b) do { i64 _x = v[a], _y = v[b]; bool _lt = _y < _x; v[a] = _lt ? _y : _x; v[b] = _lt ? _x : _y; } while (0)

/* optimal 19-comparator network for 8 elements */
static inline void net8(i64 *v) {
    CSWAP(0,2); CSWAP(1,3); CSWAP(4,6); CSWAP(5,7);
    CSWAP(0,4); CSWAP(1,5); CSWAP(2,6); CSWAP(3,7);
    CSWAP(0,1); CSWAP(2,3); CSWAP(4,5); CSWAP(6,7);
    CSWAP(2,4); CSWAP(3,5);
    CSWAP(1,4); CSWAP(3,6);
    CSWAP(1,2); CSWAP(3,4); CSWAP(5,6);
}

static void ipn_small(i64 *v, size_t n) {
    /* network-sort each aligned block of 8, then one insertion pass which is
     * now near-linear because every element is within its block already */
    size_t i = 0;
    for (; i + 8 <= n; i += 8) net8(v + i);
    insertion_i64(v, n);
}

static inline size_t median3_idx(const i64 *v, size_t a, size_t b, size_t c) {
    bool ab = v[a] < v[b], ac = v[a] < v[c], bc = v[b] < v[c];
    /* branchless-ish median selection */
    if (ab == bc) return b;
    if (ab == ac) return c;
    return a;
}

static size_t choose_pivot(const i64 *v, size_t n) {
    size_t s = n / 8;
    if (n >= 64) {
        size_t a = median3_idx(v, 0 * s, 1 * s, 2 * s);
        size_t b = median3_idx(v, 3 * s, 4 * s, 5 * s);
        size_t c = median3_idx(v, 6 * s, 7 * s, n - 1);
        return median3_idx(v, a, b, c);
    }
    return median3_idx(v, 0, n / 2, n - 1);
}

/* branchless Lomuto: unconditional swap, conditional advance.
 * Elements satisfying the predicate end up in v[0..ret). */
static size_t part_lt(i64 *v, size_t n, i64 pivot) {
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        i64 x = v[i];
        i64 y = v[j];
        v[i] = y; v[j] = x;
        j += (x < pivot);
    }
    return j;
}
static size_t part_le(i64 *v, size_t n, i64 pivot) {
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        i64 x = v[i];
        i64 y = v[j];
        v[i] = y; v[j] = x;
        j += (x <= pivot);
    }
    return j;
}

static void ipn_rec(i64 *v, size_t n, const i64 *ancestor, int limit) {
    for (;;) {
        if (n <= IPN_SMALL) { ipn_small(v, n); return; }
        if (limit == 0) { heapsort_i64(v, n); return; }
        limit--;

        size_t pi = choose_pivot(v, n);
        i64 pivot = v[pi];

        /* everything in v is >= *ancestor; a pivot that is not > ancestor is
         * therefore == ancestor, and so is everything <= it: skip them all */
        if (ancestor && !(*ancestor < pivot)) {
            size_t eq = part_le(v, n, pivot);
            v += eq; n -= eq; ancestor = NULL;
            continue;
        }

        swap64(&v[0], &v[pi]);
        size_t lt = part_lt(v + 1, n - 1, pivot);
        swap64(&v[0], &v[lt]);          /* pivot now at v[lt] */

        /* pattern-defeating step (pdqsort): a badly unbalanced partition means
         * the pivot samples hit a pattern (e.g. a periodic input whose period
         * divides the sample stride). Swap a few elements near the sample
         * points with xorshift-chosen positions so the next pivot is not
         * chosen from the same phase. Costs nothing on balanced partitions. */
        {
            size_t rn = n - 1 - lt;
            if (lt < n / 8 || rn < n / 8) {
                i64 *l = v; size_t ln = lt;
                if (ln >= 8) {
                    size_t q = ln / 4;
                    swap64(&l[0], &l[rng() % ln]); swap64(&l[q], &l[rng() % ln]);
                    swap64(&l[2 * q], &l[rng() % ln]); swap64(&l[ln - 1], &l[rng() % ln]);
                }
                i64 *r = v + lt + 1;
                if (rn >= 8) {
                    size_t q = rn / 4;
                    swap64(&r[0], &r[rng() % rn]); swap64(&r[q], &r[rng() % rn]);
                    swap64(&r[2 * q], &r[rng() % rn]); swap64(&r[rn - 1], &r[rng() % rn]);
                }
            }
        }

        ipn_rec(v, lt, ancestor, limit);
        /* loop on the right side, pivot is its ancestor */
        v[lt] = pivot;                   /* keep pivot storage stable for the pointer */
        ancestor = &v[lt];
        v += lt + 1; n -= lt + 1;
    }
}

static void sort_ipn(i64 *v, size_t n) {
    if (n < 2) return;
    if (n <= IPN_SMALL) { ipn_small(v, n); return; }
    /* top-level full-run scan */
    size_t i = 1;
    if (v[1] < v[0]) {
        while (i < n && v[i] < v[i - 1]) i++;
        if (i == n) {
            for (size_t a = 0, b = n - 1; a < b; a++, b--) swap64(&v[a], &v[b]);
            return;
        }
    } else {
        while (i < n && !(v[i] < v[i - 1])) i++;
        if (i == n) return;
    }
    ipn_rec(v, n, NULL, (int)(2 * log2_floor(n)));
}

/* ---------- LSD radix, 8 x 8-bit passes ---------- */
static void sort_radix(i64 *v, size_t n) {
    if (n < 2) return;
    uint64_t *a = (uint64_t *)v;
    uint64_t *b = malloc(n * sizeof(uint64_t));
    size_t cnt[256];
    for (int pass = 0; pass < 8; pass++) {
        int shift = pass * 8;
        memset(cnt, 0, sizeof cnt);
        for (size_t i = 0; i < n; i++) {
            uint64_t k = a[i] ^ 0x8000000000000000ULL;   /* signed -> unsigned order */
            cnt[(k >> shift) & 0xFF]++;
        }
        /* skip a pass where every key shares the byte */
        bool trivial = false;
        for (int d = 0; d < 256; d++) if (cnt[d] == n) { trivial = true; break; }
        if (trivial) continue;
        size_t sum = 0;
        for (int d = 0; d < 256; d++) { size_t c = cnt[d]; cnt[d] = sum; sum += c; }
        for (size_t i = 0; i < n; i++) {
            uint64_t k = a[i] ^ 0x8000000000000000ULL;
            b[cnt[(k >> shift) & 0xFF]++] = a[i];
        }
        uint64_t *t = a; a = b; b = t;
    }
    if (a != (uint64_t *)v) memcpy(v, a, n * sizeof(uint64_t));
    free(a == (uint64_t *)v ? b : a);
}

/* ---------- patterns ---------- */
typedef void (*gen_fn)(i64 *, size_t);
static void gen_random(i64 *v, size_t n)   { for (size_t i = 0; i < n; i++) v[i] = (i64)rng(); }
static void gen_sorted(i64 *v, size_t n)   { for (size_t i = 0; i < n; i++) v[i] = (i64)i; }
static void gen_reversed(i64 *v, size_t n) { for (size_t i = 0; i < n; i++) v[i] = (i64)(n - i); }
static void gen_nearly(i64 *v, size_t n) {
    gen_sorted(v, n);
    if (n == 0) return;
    size_t k = n / 100 + 1;
    for (size_t i = 0; i < k; i++) swap64(&v[rng() % n], &v[rng() % n]);
}
static void gen_dist10(i64 *v, size_t n)   { for (size_t i = 0; i < n; i++) v[i] = (i64)(rng() % 10); }
static void gen_sawtooth(i64 *v, size_t n) { for (size_t i = 0; i < n; i++) v[i] = (i64)(i % 1000); }
static void gen_organ(i64 *v, size_t n) {
    size_t h = n / 2;
    for (size_t i = 0; i < n; i++) v[i] = (i64)(i < h ? i : n - i);
}
static void gen_equal(i64 *v, size_t n)    { for (size_t i = 0; i < n; i++) v[i] = 42; }

/* ---------- driver ---------- */
typedef void (*sort_fn)(i64 *, size_t);
static const struct { const char *name; sort_fn f; } SORTS[] = {
    {"qsort", sort_qsort}, {"intro", sort_intro}, {"ipn", sort_ipn}, {"radix", sort_radix},
};
static const struct { const char *name; gen_fn g; } PATTERNS[] = {
    {"random", gen_random}, {"sorted", gen_sorted}, {"reversed", gen_reversed},
    {"nearly", gen_nearly}, {"dist10", gen_dist10}, {"sawtooth", gen_sawtooth},
    {"organ", gen_organ}, {"equal", gen_equal},
};
#define NS (sizeof SORTS / sizeof SORTS[0])
#define NP (sizeof PATTERNS / sizeof PATTERNS[0])

static double now_ms(void) {
    struct timespec ts; clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1e3 + ts.tv_nsec / 1e6;
}

/* 0-1 principle: a comparator network sorts ALL inputs iff it sorts every 0/1
 * input, so 2^8 = 256 cases decide net8 exhaustively. The random and patterned
 * inputs below are only suggestive for a fixed network -- a wrong comparator
 * can survive them -- which is why this runs separately and first. */
static int verify_net8(void) {
    int bad = 0;
    for (int mask = 0; mask < 256; mask++) {
        i64 v[8];
        for (int i = 0; i < 8; i++) v[i] = (mask >> i) & 1;
        net8(v);
        for (int i = 1; i < 8; i++)
            if (v[i - 1] > v[i]) { printf("net8 FAIL mask=%d\n", mask); bad++; break; }
    }
    return bad;
}

/* correctness sweep: every sort vs qsort, sizes 0..300 exhaustive-ish plus 100k */
static int verify(void) {
    int bad = verify_net8();
    size_t sizes[] = {0, 1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 100, 255, 256, 1000, 100000};
    for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
        size_t n = sizes[si];
        i64 *src = malloc((n + 1) * sizeof(i64)), *ref = malloc((n + 1) * sizeof(i64)), *w = malloc((n + 1) * sizeof(i64));
        for (size_t p = 0; p < NP; p++) {
            for (int rep = 0; rep < 3; rep++) {
                PATTERNS[p].g(src, n);
                memcpy(ref, src, n * sizeof(i64)); sort_qsort(ref, n);
                for (size_t s = 1; s < NS; s++) {
                    memcpy(w, src, n * sizeof(i64));
                    if (getenv("TRACE")) { fprintf(stderr, "verify %s %s n=%zu\n", SORTS[s].name, PATTERNS[p].name, n); }
                    SORTS[s].f(w, n);
                    if (memcmp(w, ref, n * sizeof(i64)) != 0) {
                        printf("MISMATCH sort=%s pattern=%s n=%zu\n", SORTS[s].name, PATTERNS[p].name, n);
                        bad++;
                    }
                }
            }
        }
        free(src); free(ref); free(w);
    }
    /* adversarial: median-of-3 killer-ish (organ pipe already there); random with few distinct at powers of 2 */
    return bad;
}

int main(int argc, char **argv) {
    int bad = verify();
    printf("verify: %s (%d mismatches, incl. net8 0-1 principle over all 256 inputs)\n\n",
           bad ? "FAIL" : "ok", bad);
    if (bad) return 1;

    size_t sizes[] = {1000, 100000, 5000000};
    int reps[]     = {2000, 30, 3};
    if (argc > 1 && strcmp(argv[1], "quick") == 0) { reps[0] = 200; reps[1] = 5; reps[2] = 1; }

    for (size_t si = 0; si < 3; si++) {
        size_t n = sizes[si];
        i64 *src = malloc(n * sizeof(i64)), *w = malloc(n * sizeof(i64));
        printf("n=%zu  (min of %d reps, ms)\n", n, reps[si]);
        printf("%-10s", "pattern");
        for (size_t s = 0; s < NS; s++) printf("%10s", SORTS[s].name);
        printf("   ipn/qsort  ipn/radix\n");
        for (size_t p = 0; p < NP; p++) {
            PATTERNS[p].g(src, n);
            double best[NS];
            for (size_t s = 0; s < NS; s++) {
                best[s] = 1e18;
                for (int r = 0; r < reps[si]; r++) {
                    memcpy(w, src, n * sizeof(i64));
                    double t0 = now_ms();
                    SORTS[s].f(w, n);
                    double t = now_ms() - t0;
                    if (t < best[s]) best[s] = t;
                }
            }
            printf("%-10s", PATTERNS[p].name);
            for (size_t s = 0; s < NS; s++) printf("%10.3f", best[s]);
            printf("   %8.2fx  %8.2fx\n", best[0] / best[2], best[3] / best[2]);
        }
        printf("\n");
        free(src); free(w);
    }
    return 0;
}
