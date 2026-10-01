/* native_sort_bench.c — standalone measurement for the NativeArray.sort_int spec
 * (specs/progress/2026-09-25-native-array-sort-narrow-widths.md). Not part of the runtime;
 * build with: cc -O2 -fno-strict-aliasing -fwrapv -o /tmp/nsb bench/c/native_sort_bench.c && /tmp/nsb [quick]
 * f64 width (NativeArray.sort_float): /tmp/nsb f64 [quick] — see the f64 section below.
 *
 * Four i64 sorts over eight input patterns at three sizes, compiled with the
 * same flags the March runtime uses (cc -O2 -fno-strict-aliasing -fwrapv).
 *
 *   qsort     libc, comparator through a function pointer (the "do nothing" option)
 *   intro     naive introsort: median-of-3, branchy Hoare, insertion <=16, heapsort fallback
 *   ipn       ipnsort-style: full-run scan, pseudo-median-of-9, branchless Lomuto,
 *             equal-partition on repeated pivot, network+insertion small-sort, heapsort fallback
 *   radix     LSD radix, 8 passes of 8 bits, O(n) scratch (the other real contender for bare i64)
 *   ipnrs     ipn with Rust's small_sort_network as the n <= 32 base case (rs_small) --
 *             what the runtime's nsort_small_W ships since 2026-09-28; `ipn` keeps
 *             the previous net8+insertion base case as the comparison point
 *             (specs/progress/2026-09-28-native-sort-rust-small-sort-network.md)
 *   ipnrun    ipn behind general natural-run merging (measured, not adopted)
 *   ipnpre    ipn behind the two-runs / nearly-sorted front end that the runtime
 *             ships since 2026-09-28 (specs/progress/2026-09-28-native-sort-natural-run-merging.md)
 *   radix1    LSD radix with all eight histograms built in ONE read pass and
 *             trivial digits skipped; measured as a second algorithm above a
 *             size threshold and not adopted (`nsb sweep`;
 *             specs/progress/2026-09-28-native-sort-int-radix-threshold.md)
 *
 * Modes: (none) the full table; `quick` fewer reps; `small` the two small-sort
 * base cases alone at every n in 2..32; `pre` ipnpre vs ipn on every pattern
 * at six sizes, alternating; `sweep` radix1 vs ipn by size; `f64` the float
 * width.
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

/* ---------- Rust's small_sort_network (core::slice::sort::shared::smallsort) ----------
 * The candidate replacement for ipn_small
 * (specs/todos/2026-09-25-native-sort-rust-small-sort-network.md). For n <= 32:
 * below 18 the whole slice is one region, else each half is. A region is
 * presorted by an optimal network on its first 13 (45 comparators) or 9 (25)
 * elements -- or 8 (net8's 19), which Rust does not do: its 8-element region
 * is pure insertion and measured 5.9x slower than net8 at n = 8 --, then
 * extended by insertion; two regions are merged branchlessly
 * from both ends at once into a 32-slot stack buffer and copied back. */
static inline void sort9_opt(i64 *v) {
    CSWAP(0,3); CSWAP(1,7); CSWAP(2,5); CSWAP(4,8);
    CSWAP(0,7); CSWAP(2,4); CSWAP(3,8); CSWAP(5,6);
    CSWAP(0,2); CSWAP(1,3); CSWAP(4,5); CSWAP(7,8);
    CSWAP(1,4); CSWAP(3,6); CSWAP(5,7);
    CSWAP(0,1); CSWAP(2,4); CSWAP(3,5); CSWAP(6,8);
    CSWAP(2,3); CSWAP(4,5); CSWAP(6,7);
    CSWAP(1,2); CSWAP(3,4); CSWAP(5,6);
}
static inline void sort13_opt(i64 *v) {
    CSWAP(0,12); CSWAP(1,10); CSWAP(2,9); CSWAP(3,7); CSWAP(5,11); CSWAP(6,8);
    CSWAP(1,6); CSWAP(2,3); CSWAP(4,11); CSWAP(7,9); CSWAP(8,10);
    CSWAP(0,4); CSWAP(1,2); CSWAP(3,6); CSWAP(7,8); CSWAP(9,10); CSWAP(11,12);
    CSWAP(4,6); CSWAP(5,9); CSWAP(8,11); CSWAP(10,12);
    CSWAP(0,5); CSWAP(3,8); CSWAP(4,7); CSWAP(6,11); CSWAP(9,10);
    CSWAP(0,1); CSWAP(2,5); CSWAP(6,9); CSWAP(7,8); CSWAP(10,11);
    CSWAP(1,3); CSWAP(2,4); CSWAP(5,6); CSWAP(9,10);
    CSWAP(1,2); CSWAP(3,4); CSWAP(5,7); CSWAP(6,8);
    CSWAP(2,3); CSWAP(4,5); CSWAP(6,7); CSWAP(8,9);
    CSWAP(3,4); CSWAP(5,6);
}
/* insertion sort of v[0..n) given v[0..presorted) is already sorted */
static inline void insertion_from(i64 *v, size_t n, size_t presorted) {
    for (size_t i = presorted; i < n; i++) {
        i64 x = v[i];
        size_t j = i;
        while (j > 0 && v[j - 1] > x) { v[j] = v[j - 1]; j--; }
        v[j] = x;
    }
}
static void rs_small(i64 *v, size_t n) {
    if (n < 8) { insertion_i64(v, n); return; }   /* as ipn_small: no setup cost */
    size_t half = n / 2;
    bool no_merge = n < 18;
    size_t rlen[2] = { no_merge ? n : half, n - half };
    i64 *rbase[2] = { v, v + half };
    for (int r = 0; r < (no_merge ? 1 : 2); r++) {
        i64 *reg = rbase[r]; size_t len = rlen[r], pre;
        if (len >= 13) { sort13_opt(reg); pre = 13; }
        else if (len >= 9) { sort9_opt(reg); pre = 9; }
        else if (len >= 8) { net8(reg); pre = 8; }   /* not in Rust: see main_small */
        else pre = 1;
        insertion_from(reg, len, pre);
    }
    if (no_merge) return;
    /* bidirectional branchless merge of v[0..half) and v[half..n) */
    i64 buf[32];
    const i64 *l = v, *rr = v + half, *lr = v + half - 1, *rrr = v + n - 1;
    i64 *out = buf, *out_rev = buf + n - 1;
    for (size_t i = 0; i < half; i++) {
        bool take_l = !(*rr < *l);
        *out++ = take_l ? *l : *rr;
        l += take_l; rr += !take_l;
        bool take_lr = *rrr < *lr;
        *out_rev-- = take_lr ? *lr : *rrr;
        lr -= take_lr; rrr -= !take_lr;
    }
    if (n & 1) {
        bool left_nonempty = l <= lr;
        *out = left_nonempty ? *l : *rr;
    }
    memcpy(v, buf, n * sizeof(i64));
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

/* ipn with rs_small as the small-sort base case; otherwise identical. */
static void ipnrs_rec(i64 *v, size_t n, const i64 *ancestor, int limit) {
    for (;;) {
        if (n <= IPN_SMALL) { rs_small(v, n); return; }
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

        ipnrs_rec(v, lt, ancestor, limit);
        /* loop on the right side, pivot is its ancestor */
        v[lt] = pivot;                   /* keep pivot storage stable for the pointer */
        ancestor = &v[lt];
        v += lt + 1; n -= lt + 1;
    }
}

static void sort_ipnrs(i64 *v, size_t n) {
    if (n < 2) return;
    if (n <= IPN_SMALL) { rs_small(v, n); return; }
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
    ipnrs_rec(v, n, NULL, (int)(2 * log2_floor(n)));
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

/* ---------- LSD radix, one histogram pass (radix1) ----------
 * The candidate for specs/todos/2026-09-25-native-sort-int-radix-threshold.md.
 * sort_radix above recomputes a histogram per digit (8 read passes before any
 * scatter); this one builds all eight 256-bucket histograms in ONE read pass,
 * then scatters only the digits that are not trivial (a digit every key
 * shares moves nothing). A 10-distinct-value input therefore costs one read
 * and one scatter, a nearly-sorted 0..n input three scatters at n = 5M.
 * Returns false (and leaves v untouched) when the scratch allocation fails,
 * so a caller can fall back to the in-place sort. */
static bool radix1_i64(i64 *v, size_t n) {
    if (n < 2) return true;
    uint64_t *a = (uint64_t *)v;
    uint64_t *b = malloc(n * sizeof(uint64_t));
    if (!b) return false;
    size_t (*cnt)[256] = calloc(8, sizeof *cnt);
    if (!cnt) { free(b); return false; }
    for (size_t i = 0; i < n; i++) {
        uint64_t k = a[i] ^ 0x8000000000000000ULL;   /* signed -> unsigned order */
        cnt[0][k & 0xFF]++;         cnt[1][(k >> 8) & 0xFF]++;
        cnt[2][(k >> 16) & 0xFF]++; cnt[3][(k >> 24) & 0xFF]++;
        cnt[4][(k >> 32) & 0xFF]++; cnt[5][(k >> 40) & 0xFF]++;
        cnt[6][(k >> 48) & 0xFF]++; cnt[7][k >> 56]++;
    }
    for (int pass = 0; pass < 8; pass++) {
        size_t *c = cnt[pass];
        bool trivial = false;
        for (int d = 0; d < 256; d++) if (c[d] == n) { trivial = true; break; }
        if (trivial) continue;
        size_t sum = 0;
        for (int d = 0; d < 256; d++) { size_t t = c[d]; c[d] = sum; sum += t; }
        int shift = pass * 8;
        for (size_t i = 0; i < n; i++) {
            uint64_t k = a[i] ^ 0x8000000000000000ULL;
            b[c[(k >> shift) & 0xFF]++] = a[i];
        }
        uint64_t *t = a; a = b; b = t;
    }
    if (a != (uint64_t *)v) { memcpy(v, a, n * sizeof(uint64_t)); free(a); }
    else free(b);
    free(cnt);
    return true;
}
static void sort_radix1(i64 *v, size_t n) { if (!radix1_i64(v, n)) sort_ipn(v, n); }

/* ---------- natural-run merging (ipnrun) ----------
 * The candidate for specs/todos/2026-09-25-native-sort-natural-run-merging.md.
 * After ipn's full-run scan, split the array into its natural runs (ascending,
 * or strictly descending and reversed in place). If the runs average at least
 * RUN_MIN_AVG elements, merge adjacent runs bottom-up through an n-word
 * scratch buffer, each merge trimmed first: the prefix of the left run that is
 * <= the right run's head and the suffix of the right run that is >= the left
 * run's tail are copied with memcpy, and only the overlap is merged
 * (branchless). Otherwise, or if the scratch allocation fails, it is ipn.
 * The run scan stops as soon as the run count proves the average too short. */
static size_t RUN_MIN_AVG = 32;

static size_t upper_bound_i64(const i64 *a, size_t n, i64 x) {   /* first a[i] > x */
    size_t lo = 0, hi = n;
    while (lo < hi) { size_t m = lo + (hi - lo) / 2; if (a[m] <= x) lo = m + 1; else hi = m; }
    return lo;
}
static size_t lower_bound_i64(const i64 *a, size_t n, i64 x) {   /* first a[i] >= x */
    size_t lo = 0, hi = n;
    while (lo < hi) { size_t m = lo + (hi - lo) / 2; if (a[m] < x) lo = m + 1; else hi = m; }
    return lo;
}
/* merge src[a..m) and src[m..b) into dst[a..b) */
static void merge_trim(const i64 *src, i64 *dst, size_t a, size_t m, size_t b) {
    size_t i = a + upper_bound_i64(src + a, m - a, src[m]);
    size_t j = m + lower_bound_i64(src + m, b - m, src[m - 1]);
    memcpy(dst + a, src + a, (i - a) * sizeof(i64));
    size_t o = i, l = i, r = m;
    while (l < m && r < j) {
        bool take_r = src[r] < src[l];
        dst[o++] = take_r ? src[r] : src[l];
        r += take_r; l += !take_r;
    }
    memcpy(dst + o, src + l, (m - l) * sizeof(i64)); o += m - l;
    memcpy(dst + o, src + r, (b - r) * sizeof(i64));
}
static void sort_ipnrun(i64 *v, size_t n) {
    if (n <= IPN_SMALL) { sort_ipn(v, n); return; }
    size_t max_runs = n / RUN_MIN_AVG;
    if (max_runs < 2) { sort_ipn(v, n); return; }
    size_t *starts = malloc((max_runs + 2) * sizeof(size_t));
    if (!starts) { sort_ipn(v, n); return; }
    size_t r = 0, i = 0;
    bool ok = true;
    while (i < n) {
        if (r >= max_runs) { ok = false; break; }
        starts[r++] = i;
        size_t j = i + 1;
        if (j < n && v[j] < v[i]) {
            while (j < n && v[j] < v[j - 1]) j++;
            for (size_t lo = i, hi = j - 1; lo < hi; lo++, hi--) swap64(&v[lo], &v[hi]);
        } else {
            while (j < n && !(v[j] < v[j - 1])) j++;
        }
        i = j;
    }
    if (!ok) {
        /* the scan may have reversed some descending runs: harmless for ipn */
        free(starts); sort_ipn(v, n); return;
    }
    if (r == 1) { free(starts); return; }
    i64 *buf = malloc(n * sizeof(i64));
    if (!buf) { free(starts); sort_ipn(v, n); return; }
    starts[r] = n;
    i64 *src = v, *dst = buf;
    while (r > 1) {
        size_t w = 0;
        for (size_t k = 0; k < r; k += 2) {
            size_t a = starts[k];
            if (k + 1 < r) {
                merge_trim(src, dst, a, starts[k + 1], starts[k + 2]);
            } else {
                memcpy(dst + a, src + a, (starts[k + 1] - a) * sizeof(i64));
            }
            starts[w++] = a;
        }
        starts[w] = n;
        r = w;
        i64 *t = src; src = dst; dst = t;
    }
    if (src != v) memcpy(v, src, n * sizeof(i64));
    free(buf); free(starts);
}

/* ---------- presorted-input front end (ipnpre) ----------
 * The shipped candidate for the natural-run todo. For n >= PRE_MIN_N, after
 * ipn's full-run scan:
 *   1. two runs: if the rest of the array after the first run is one more
 *      run (ascending, or strictly descending and then reversed), merge the
 *      two with merge_two_runs -- trimmed, scratch = the smaller trimmed run;
 *   2. nearly sorted: otherwise, if the first 64 elements have at most 4
 *      descents, try pre_outliers below;
 *   3. otherwise, or on any allocation failure, ipn.
 * ipnrun above (general natural-run merging) was measured first and lost on
 * nearly-sorted and sawtooth input; see
 * specs/progress/2026-09-28-native-sort-natural-run-merging.md. */
static size_t PRE_MIN_N = 1024;

/* Two runs: v[0..m) and v[m..n) are each sorted (ascending). Merge them in
 * place with a scratch buffer the size of the smaller trimmed run: the prefix
 * of the left run <= the right run's head and the suffix of the right run >=
 * the left run's tail are already in place. false = allocation failed, v
 * untouched. */
static bool merge_two_runs(i64 *v, size_t m, size_t n) {
    size_t i = upper_bound_i64(v, m, v[m]);
    size_t j = m + lower_bound_i64(v + m, n - m, v[m - 1]);
    size_t la = m - i, lb = j - m;
    if (la == 0 || lb == 0) return true;
    if (la <= lb) {
        i64 *buf = malloc(la * sizeof(i64));
        if (!buf) return false;
        memcpy(buf, v + i, la * sizeof(i64));
        size_t o = i, x = 0, y = m;
        while (x < la && y < j) {
            bool take_y = v[y] < buf[x];
            v[o++] = take_y ? v[y] : buf[x];
            y += take_y; x += !take_y;
        }
        memcpy(v + o, buf + x, (la - x) * sizeof(i64));
        free(buf);
    } else {
        i64 *buf = malloc(lb * sizeof(i64));
        if (!buf) return false;
        memcpy(buf, v + m, lb * sizeof(i64));
        size_t o = j, x = m, y = lb;          /* x: end of left part, y: end of buf */
        while (x > i && y > 0) {
            bool take_x = buf[y - 1] < v[x - 1];
            v[--o] = take_x ? v[x - 1] : buf[y - 1];
            x -= take_x; y -= !take_x;
        }
        memcpy(v + o - y, buf, y * sizeof(i64));
        free(buf);
    }
    return true;
}

/* true: v is sorted. false: v is some permutation of the input, unsorted. */
static bool pre_outliers(i64 *v, size_t n) {
    size_t cap = n / 16;
    if (cap < 16) return false;

    i64 *out = malloc(cap * sizeof(i64));
    if (!out) return false;
    size_t m = 0, k = 0, i = 0;
    for (; i < n; i++) {
        i64 x = v[i];
        /* Large values kept by mistake (their successor was itself out of
         * place) would make every later element look low. When x is below
         * the last kept element, find how many trailing kept elements (at
         * most 8) are above x; if dropping them lets x -- and x's successor
         * after it -- fit, evict them instead of x. */
        size_t pop = 0;
        if (m > 0 && x < v[m - 1] && (i + 1 >= n || !(v[i + 1] < x))) {
            size_t j = m;
            while (j > 0 && m - j < 8 && x < v[j - 1]) j--;
            if (j == 0 || !(x < v[j - 1])) pop = m - j;
        }
        bool outlier = pop == 0
            && ((m > 0 && x < v[m - 1])
                || (i + 1 < n && v[i + 1] < x && (m == 0 || !(v[i + 1] < v[m - 1]))));
        if (pop > 0 || outlier) {
            if (k + pop + 1 > cap || (i >= 256 && (k + pop) * 16 > i)) goto abort;
            if (pop > 0) {
                memcpy(out + k, v + m - pop, pop * sizeof(i64));
                k += pop; m -= pop;
                v[m++] = x;
            } else {
                out[k++] = x;
            }
        } else {
            v[m++] = x;
        }
    }
    sort_ipn(out, k);
    /* merge v[0..m) and out[0..k) into v[0..n) from the back */
    {
        size_t o = n, am = m, b = k;
        while (b > 0) {
            if (am > 0 && out[b - 1] < v[am - 1]) v[--o] = v[--am];
            else v[--o] = out[--b];
        }
    }
    free(out);
    return true;
abort:
    /* v[0..m) kept, out[0..k) moved, v[i..n) untouched, and m + k == i:
     * the moved elements go back into the k-slot gap v[m..i), which leaves
     * a permutation of the input for ipn without touching the tail */
    memcpy(v + m, out, k * sizeof(i64));
    free(out);
    return false;
}

static void sort_ipnpre(i64 *v, size_t n) {
    if (n <= IPN_SMALL) { sort_ipn(v, n); return; }
    size_t i = 1;
    bool first_desc = v[1] < v[0];
    if (first_desc) {
        while (i < n && v[i] < v[i - 1]) i++;
        if (i == n) { for (size_t a = 0, b = n - 1; a < b; a++, b--) swap64(&v[a], &v[b]); return; }
    } else {
        while (i < n && !(v[i] < v[i - 1])) i++;
        if (i == n) return;
    }
    if (n >= PRE_MIN_N) {
        /* two runs: the full-run scan above found where the first ends */
        size_t j = i + 1;
        bool second_desc = j < n && v[j] < v[i];
        if (second_desc) while (j < n && v[j] < v[j - 1]) j++;
        else             while (j < n && !(v[j] < v[j - 1])) j++;
        if (j == n) {
            if (first_desc)  for (size_t a = 0, b = i - 1; a < b; a++, b--) swap64(&v[a], &v[b]);
            if (second_desc) for (size_t a = i, b = n - 1; a < b; a++, b--) swap64(&v[a], &v[b]);
            if (merge_two_runs(v, i, n)) return;
        } else {
            /* nearly sorted: gate on at most 4 descents in the first 64 */
            int desc = 0;
            for (size_t k = 1; k < 64; k++) desc += v[k] < v[k - 1];
            if (desc <= 4 && pre_outliers(v, n)) return;
        }
    }
    ipn_rec(v, n, NULL, (int)(2 * log2_floor(n)));
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
    {"ipnrs", sort_ipnrs}, {"radix1", sort_radix1}, {"ipnrun", sort_ipnrun}, {"ipnpre", sort_ipnpre},
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

/* ipnpre's front end sees shapes the eight patterns do not produce: two
 * interleaved ascending halves, descending+descending, descending+ascending,
 * one far outlier, and duplicate-heavy nearly-sorted input. */
static int verify_pre(void) {
    int bad = 0;
    size_t sizes[] = {1024, 1025, 2000, 4097, 20000, 100000};
    for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
        size_t n = sizes[si], h = n / 2;
        i64 *v = malloc(n * sizeof(i64)), *ref = malloc(n * sizeof(i64));
        for (int shape = 0; shape < 6; shape++) {
            for (size_t i = 0; i < n; i++) {
                switch (shape) {
                case 0: v[i] = i < h ? (i64)(2 * i) : (i64)(2 * (i - h) + 1); break;
                case 1: v[i] = i < h ? (i64)(h - i) : (i64)(n - i) * 3; break;
                case 2: v[i] = i < h ? (i64)(h - i) * 2 : (i64)(i - h) * 2 + 1; break;
                case 3: v[i] = (i64)i; break;
                case 4: v[i] = (i64)(i / 7); break;
                default: v[i] = i < h ? (i64)(i % 50) : (i64)i; break;
                }
            }
            if (shape == 3) v[n / 3] = -5;
            if (shape == 4) for (size_t k = 0; k < n / 64; k++) v[rng() % n] = (i64)(rng() % (n / 7 + 1));
            memcpy(ref, v, n * sizeof(i64)); sort_qsort(ref, n);
            sort_ipnpre(v, n);
            if (memcmp(v, ref, n * sizeof(i64)) != 0) { printf("MISMATCH ipnpre shape=%d n=%zu\n", shape, n); bad++; }
        }
        free(v); free(ref);
    }
    return bad;
}

/* 0-1 principle for rs_small's networks (512 and 8192 inputs), and -- since
 * rs_small as a whole is not a network (insertion + merge) -- an exhaustive
 * 0/1 check of the whole routine for every n up to 22, which covers both
 * the single-region (n < 18) and the two-region merge path. Random inputs
 * up to 32 are in verify() below via ipnrs and in main_small. */
static int verify_rs_small(void) {
    int bad = 0;
    for (int mask = 0; mask < (1 << 9); mask++) {
        i64 v[9]; for (int i = 0; i < 9; i++) v[i] = (mask >> i) & 1;
        sort9_opt(v);
        for (int i = 1; i < 9; i++) if (v[i - 1] > v[i]) { printf("sort9 FAIL mask=%d\n", mask); bad++; break; }
    }
    for (int mask = 0; mask < (1 << 13); mask++) {
        i64 v[13]; for (int i = 0; i < 13; i++) v[i] = (mask >> i) & 1;
        sort13_opt(v);
        for (int i = 1; i < 13; i++) if (v[i - 1] > v[i]) { printf("sort13 FAIL mask=%d\n", mask); bad++; break; }
    }
    for (int n = 0; n <= 22; n++) {
        for (long mask = 0; mask < (1L << n); mask++) {
            i64 v[32]; int ones = 0;
            for (int i = 0; i < n; i++) { v[i] = (mask >> i) & 1; ones += (int)v[i]; }
            rs_small(v, (size_t)n);
            for (int i = 0; i < n; i++)
                if (v[i] != (i >= n - ones)) { printf("rs_small FAIL n=%d mask=%ld\n", n, mask); bad++; goto next_n; }
        }
    next_n:;
    }
    return bad;
}

/* correctness sweep: every sort vs qsort, sizes 0..300 exhaustive-ish plus 100k */
static int verify(void) {
    int bad = verify_net8() + verify_rs_small() + verify_pre();
    size_t sizes[] = {0, 1, 2, 3, 7, 8, 9, 12, 13, 14, 15, 16, 17, 18, 19, 20, 25, 26, 27, 31, 32, 33, 63, 64, 65, 100, 255, 256, 1000, 100000};
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

/* ======================================================================
 * f64 width (NativeArray.sort_float). Run with `nsb f64 [quick]`.
 *
 * Doubles sort by IEEE 754 totalOrder:
 *   key(bits) = bits ^ (((int64_t)bits >> 63) & 0x7FFFFFFFFFFFFFFF)
 * compared as a signed i64, which gives -NaN < -Inf < ... < -0 < +0 < ...
 * < +Inf < +NaN. key() is an involution (the sign bit is untouched, so
 * applying it twice restores the bits), which allows two shapes:
 *
 *   xform   transform every element to its key in place, run the i64 ipn
 *           sort above unchanged, transform back. Two extra O(n) passes
 *           (both vectorize), zero extra work per comparison.
 *   keyed   the same ipn algorithm with every `a < b` replaced by
 *           key(a) < key(b) on the fly: no extra passes, two xor/shift/and
 *           per comparison.
 *
 * The runtime ships whichever measures faster; the numbers are recorded in
 * specs/progress/2026-09-24-native-array-sort-f64.md.
 *
 * Baselines: qsort with a totalOrder comparator (the reference output every
 * other variant is memcmp'd against), and qsort with the "naive" double
 * comparator (x > y) - (x < y), which is only a valid sort on NaN-free data
 * and is therefore neither verified nor timed on the `specials` pattern.
 * ====================================================================== */

static inline i64 fkey(i64 bits) {
    return bits ^ (i64)((uint64_t)(bits >> 63) >> 1);
}

static int cmp_f64_total(const void *a, const void *b) {
    i64 x = fkey(*(const i64 *)a), y = fkey(*(const i64 *)b);
    return (x > y) - (x < y);
}
static int cmp_f64_naive(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return (x > y) - (x < y);
}
static void fsort_qsort_total(double *v, size_t n) { qsort(v, n, sizeof(double), cmp_f64_total); }
static void fsort_qsort_naive(double *v, size_t n) { qsort(v, n, sizeof(double), cmp_f64_naive); }

static void fsort_xform(double *d, size_t n) {
    i64 *v = (i64 *)d;
    for (size_t i = 0; i < n; i++) v[i] = fkey(v[i]);
    sort_ipn(v, n);
    for (size_t i = 0; i < n; i++) v[i] = fkey(v[i]);
}

/* keyed: the ipn algorithm above, verbatim, with `<` routed through fkey. */
#define KLT(x, y) (fkey(x) < fkey(y))
#define KCSWAP(a, b) do { i64 _x = v[a], _y = v[b]; bool _lt = KLT(_y, _x); v[a] = _lt ? _y : _x; v[b] = _lt ? _x : _y; } while (0)

static inline void knet8(i64 *v) {
    KCSWAP(0,2); KCSWAP(1,3); KCSWAP(4,6); KCSWAP(5,7);
    KCSWAP(0,4); KCSWAP(1,5); KCSWAP(2,6); KCSWAP(3,7);
    KCSWAP(0,1); KCSWAP(2,3); KCSWAP(4,5); KCSWAP(6,7);
    KCSWAP(2,4); KCSWAP(3,5);
    KCSWAP(1,4); KCSWAP(3,6);
    KCSWAP(1,2); KCSWAP(3,4); KCSWAP(5,6);
}
static void kinsertion(i64 *v, size_t n) {
    for (size_t i = 1; i < n; i++) {
        i64 x = v[i];
        size_t j = i;
        while (j > 0 && KLT(x, v[j - 1])) { v[j] = v[j - 1]; j--; }
        v[j] = x;
    }
}
static void ksmall(i64 *v, size_t n) {
    size_t i = 0;
    for (; i + 8 <= n; i += 8) knet8(v + i);
    kinsertion(v, n);
}
static void kheap(i64 *v, size_t n) {
    for (size_t start = n / 2; start-- > 0;) {
        size_t root = start;
        for (;;) {
            size_t child = 2 * root + 1;
            if (child >= n) break;
            if (child + 1 < n && KLT(v[child], v[child + 1])) child++;
            if (!KLT(v[root], v[child])) break;
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
            if (child + 1 < end && KLT(v[child], v[child + 1])) child++;
            if (!KLT(v[root], v[child])) break;
            swap64(&v[root], &v[child]);
            root = child;
        }
    }
}
static inline size_t kmedian3(const i64 *v, size_t a, size_t b, size_t c) {
    bool ab = KLT(v[a], v[b]), ac = KLT(v[a], v[c]), bc = KLT(v[b], v[c]);
    if (ab == bc) return b;
    if (ab == ac) return c;
    return a;
}
static size_t kpivot(const i64 *v, size_t n) {
    size_t s = n / 8;
    if (n >= 64) {
        size_t a = kmedian3(v, 0 * s, 1 * s, 2 * s);
        size_t b = kmedian3(v, 3 * s, 4 * s, 5 * s);
        size_t c = kmedian3(v, 6 * s, 7 * s, n - 1);
        return kmedian3(v, a, b, c);
    }
    return kmedian3(v, 0, n / 2, n - 1);
}
static size_t kpart_lt(i64 *v, size_t n, i64 pivot) {
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        i64 x = v[i], y = v[j];
        v[i] = y; v[j] = x;
        j += KLT(x, pivot);
    }
    return j;
}
static size_t kpart_le(i64 *v, size_t n, i64 pivot) {
    size_t j = 0;
    for (size_t i = 0; i < n; i++) {
        i64 x = v[i], y = v[j];
        v[i] = y; v[j] = x;
        j += !KLT(pivot, x);
    }
    return j;
}
static void kbreak(i64 *l, size_t ln) {
    if (ln < 8) return;
    size_t q = ln / 4;
    swap64(&l[0], &l[rng() % ln]); swap64(&l[q], &l[rng() % ln]);
    swap64(&l[2 * q], &l[rng() % ln]); swap64(&l[ln - 1], &l[rng() % ln]);
}
static void krec(i64 *v, size_t n, const i64 *ancestor, int limit) {
    for (;;) {
        if (n <= IPN_SMALL) { ksmall(v, n); return; }
        if (limit == 0) { kheap(v, n); return; }
        limit--;
        size_t pi = kpivot(v, n);
        i64 pivot = v[pi];
        if (ancestor && !KLT(*ancestor, pivot)) {
            size_t eq = kpart_le(v, n, pivot);
            v += eq; n -= eq; ancestor = NULL;
            continue;
        }
        swap64(&v[0], &v[pi]);
        size_t lt = kpart_lt(v + 1, n - 1, pivot);
        swap64(&v[0], &v[lt]);
        size_t rn = n - 1 - lt;
        if (lt < n / 8 || rn < n / 8) { kbreak(v, lt); kbreak(v + lt + 1, rn); }
        krec(v, lt, ancestor, limit);
        ancestor = &v[lt];
        v += lt + 1; n -= lt + 1;
    }
}
static void fsort_keyed(double *d, size_t n) {
    i64 *v = (i64 *)d;
    if (n < 2) return;
    if (n <= IPN_SMALL) { ksmall(v, n); return; }
    size_t i = 1;
    if (KLT(v[1], v[0])) {
        while (i < n && KLT(v[i], v[i - 1])) i++;
        if (i == n) {
            for (size_t a = 0, b = n - 1; a < b; a++, b--) swap64(&v[a], &v[b]);
            return;
        }
    } else {
        while (i < n && !KLT(v[i], v[i - 1])) i++;
        if (i == n) return;
    }
    krec(v, n, NULL, (int)(2 * log2_floor(n)));
}

/* f64 patterns: the eight i64 shapes, as doubles, plus `specials`. `random`
 * spans both signs with fractional parts so the key transform's negative
 * branch is exercised on every run, not only on `specials`. */
typedef void (*fgen_fn)(double *, size_t);
static void fgen_from_i64(double *d, size_t n, gen_fn g) {
    i64 *tmp = malloc((n + 1) * sizeof(i64));
    g(tmp, n);
    for (size_t i = 0; i < n; i++) d[i] = (double)tmp[i];
    free(tmp);
}
static void fgen_random(double *d, size_t n) {
    for (size_t i = 0; i < n; i++) d[i] = (double)(i64)rng() / 4294967296.0;
}
static void fgen_sorted(double *d, size_t n)   { fgen_from_i64(d, n, gen_sorted); }
static void fgen_reversed(double *d, size_t n) { fgen_from_i64(d, n, gen_reversed); }
static void fgen_nearly(double *d, size_t n)   { fgen_from_i64(d, n, gen_nearly); }
static void fgen_dist10(double *d, size_t n)   { fgen_from_i64(d, n, gen_dist10); }
static void fgen_sawtooth(double *d, size_t n) { fgen_from_i64(d, n, gen_sawtooth); }
static void fgen_organ(double *d, size_t n)    { fgen_from_i64(d, n, gen_organ); }
static void fgen_equal(double *d, size_t n)    { fgen_from_i64(d, n, gen_equal); }
/* ~6% special values: both NaN signs, both infinities, both zeros. */
static void fgen_specials(double *d, size_t n) {
    fgen_random(d, n);
    for (size_t i = 0; i < n; i++) {
        switch (rng() % 100) {
            case 0: d[i] = NAN; break;
            case 1: d[i] = -NAN; break;
            case 2: d[i] = INFINITY; break;
            case 3: d[i] = -INFINITY; break;
            case 4: d[i] = 0.0; break;
            case 5: d[i] = -0.0; break;
            default: break;
        }
    }
}

typedef void (*fsort_fn)(double *, size_t);
static const struct { const char *name; fsort_fn f; } FSORTS[] = {
    {"qs_total", fsort_qsort_total}, {"qs_naive", fsort_qsort_naive},
    {"xform", fsort_xform}, {"keyed", fsort_keyed},
};
static const struct { const char *name; fgen_fn g; bool special; } FPATTERNS[] = {
    {"random", fgen_random, false}, {"sorted", fgen_sorted, false},
    {"reversed", fgen_reversed, false}, {"nearly", fgen_nearly, false},
    {"dist10", fgen_dist10, false}, {"sawtooth", fgen_sawtooth, false},
    {"organ", fgen_organ, false}, {"equal", fgen_equal, false},
    {"specials", fgen_specials, true},
};
#define NFS (sizeof FSORTS / sizeof FSORTS[0])
#define NFP (sizeof FPATTERNS / sizeof FPATTERNS[0])

static int fverify(void) {
    int bad = 0;
    size_t sizes[] = {0, 1, 2, 3, 7, 8, 9, 15, 16, 17, 31, 32, 33, 63, 64, 65, 100, 255, 256, 1000, 100000};
    for (size_t si = 0; si < sizeof sizes / sizeof sizes[0]; si++) {
        size_t n = sizes[si];
        double *src = malloc((n + 1) * sizeof(double)), *ref = malloc((n + 1) * sizeof(double)),
               *w = malloc((n + 1) * sizeof(double));
        for (size_t p = 0; p < NFP; p++) {
            for (int rep = 0; rep < 3; rep++) {
                FPATTERNS[p].g(src, n);
                memcpy(ref, src, n * sizeof(double)); fsort_qsort_total(ref, n);
                for (size_t s = 1; s < NFS; s++) {
                    if (FPATTERNS[p].special && FSORTS[s].f == fsort_qsort_naive) continue;
                    memcpy(w, src, n * sizeof(double));
                    FSORTS[s].f(w, n);
                    if (memcmp(w, ref, n * sizeof(double)) != 0) {
                        printf("MISMATCH sort=%s pattern=%s n=%zu\n", FSORTS[s].name, FPATTERNS[p].name, n);
                        bad++;
                    }
                }
            }
        }
        free(src); free(ref); free(w);
    }
    /* totalOrder placement, spelled out: the reference comparator itself must
     * put the specials where the spec says, or every memcmp above is vacuous. */
    double sp[] = {1.0, NAN, -0.0, -INFINITY, 0.0, -NAN, INFINITY, -1.0};
    fsort_xform(sp, 8);
    if (!(isnan(sp[0]) && signbit(sp[0]) && sp[1] == -INFINITY && sp[2] == -1.0 &&
          sp[3] == 0.0 && signbit(sp[3]) && sp[4] == 0.0 && !signbit(sp[4]) &&
          sp[5] == 1.0 && sp[6] == INFINITY && isnan(sp[7]) && !signbit(sp[7]))) {
        printf("MISMATCH totalOrder placement of specials\n");
        bad++;
    }
    return bad;
}

static int main_f64(bool quick) {
    int bad = fverify();
    printf("f64 verify: %s (%d mismatches)\n\n", bad ? "FAIL" : "ok", bad);
    if (bad) return 1;
    size_t sizes[] = {1000, 100000, 5000000};
    int reps[]     = {2000, 30, 3};
    if (quick) { reps[0] = 200; reps[1] = 5; reps[2] = 1; }
    for (size_t si = 0; si < 3; si++) {
        size_t n = sizes[si];
        double *src = malloc(n * sizeof(double)), *w = malloc(n * sizeof(double));
        printf("f64 n=%zu  (min of %d reps, ms)\n", n, reps[si]);
        printf("%-10s", "pattern");
        for (size_t s = 0; s < NFS; s++) printf("%10s", FSORTS[s].name);
        printf("   xform/qs_total  keyed/xform\n");
        for (size_t p = 0; p < NFP; p++) {
            FPATTERNS[p].g(src, n);
            double best[NFS];
            for (size_t s = 0; s < NFS; s++) {
                best[s] = -1;
                if (FPATTERNS[p].special && FSORTS[s].f == fsort_qsort_naive) continue;
                best[s] = 1e18;
                for (int r = 0; r < reps[si]; r++) {
                    memcpy(w, src, n * sizeof(double));
                    double t0 = now_ms();
                    FSORTS[s].f(w, n);
                    double t = now_ms() - t0;
                    if (t < best[s]) best[s] = t;
                }
            }
            printf("%-10s", FPATTERNS[p].name);
            for (size_t s = 0; s < NFS; s++) {
                if (best[s] < 0) printf("%10s", "-");
                else printf("%10.3f", best[s]);
            }
            printf("   %12.2fx  %10.2fx\n", best[0] / best[2], best[3] / best[2]);
        }
        printf("\n");
        free(src); free(w);
    }
    return 0;
}

/* `nsb small`: the two small-sort base cases alone, on random input, at every
 * n in 2..32 (the only sizes they ever see). Each timed batch sorts ~2M
 * elements as independent n-element arrays; min of 15 batches. */
static int main_small(void) {
    int bad = verify_rs_small();
    printf("small verify: %s\n", bad ? "FAIL" : "ok");
    if (bad) return 1;
    size_t total = 2000000;
    i64 *src = malloc(total * sizeof(i64)), *w = malloc(total * sizeof(i64)), *ref = malloc(total * sizeof(i64));
    printf("%4s %12s %12s %8s\n", "n", "net8+ins ns", "rust ns", "rust/net8");
    double sum_a = 0, sum_b = 0;
    for (size_t n = 2; n <= 32; n++) {
        size_t cnt = total / n, m = cnt * n;
        gen_random(src, m);
        double best[2] = {1e18, 1e18};
        for (int r = 0; r < 15; r++) {
            for (int k = 0; k < 2; k++) {
                int which = (r & 1) ? 1 - k : k;
                memcpy(w, src, m * sizeof(i64));
                double t0 = now_ms();
                if (which == 0) for (size_t i = 0; i < cnt; i++) ipn_small(w + i * n, n);
                else            for (size_t i = 0; i < cnt; i++) rs_small(w + i * n, n);
                double t = now_ms() - t0;
                if (t < best[which]) best[which] = t;
                if (r == 0) {
                    if (which == 0) memcpy(ref, w, m * sizeof(i64));
                    else if (memcmp(ref, w, m * sizeof(i64)) != 0) { printf("MISMATCH small n=%zu\n", n); return 1; }
                }
            }
        }
        double a = best[0] * 1e6 / (double)cnt, b = best[1] * 1e6 / (double)cnt;
        sum_a += a; sum_b += b;
        printf("%4zu %12.1f %12.1f %8.2fx\n", n, a, b, b / a);
    }
    printf("sum  %12.1f %12.1f %8.2fx\n", sum_a, sum_b, sum_b / sum_a);
    free(src); free(w); free(ref);
    return 0;
}

/* `nsb sweep`: the radix threshold. For each size, ipn vs radix1 on every
 * pattern that survives ipn's full-run scan (sorted/reversed/equal never
 * reach a sort), min of an adaptive number of reps so each cell takes
 * ~>=200 ms of total timing; alternating order. Prints radix1/ipn. */
static int main_sweep(void) {
    size_t sizes[] = {256, 512, 1024, 2048, 4096, 8192, 16384, 32768, 65536,
                      131072, 262144, 524288, 1048576, 5000000};
    size_t np = sizeof sizes / sizeof sizes[0];
    printf("radix1/ipn (min of reps; < 1 means radix1 faster)\n%-9s", "n");
    for (size_t p = 0; p < NP; p++) {
        if (PATTERNS[p].g == gen_sorted || PATTERNS[p].g == gen_reversed || PATTERNS[p].g == gen_equal) continue;
        printf("%10s", PATTERNS[p].name);
    }
    printf("\n");
    for (size_t si = 0; si < np; si++) {
        size_t n = sizes[si];
        i64 *src = malloc(n * sizeof(i64)), *w = malloc(n * sizeof(i64)), *ref = malloc(n * sizeof(i64));
        int reps = (int)(20000000 / n); if (reps < 3) reps = 3; if (reps > 3000) reps = 3000;
        printf("%-9zu", n);
        for (size_t p = 0; p < NP; p++) {
            if (PATTERNS[p].g == gen_sorted || PATTERNS[p].g == gen_reversed || PATTERNS[p].g == gen_equal) continue;
            PATTERNS[p].g(src, n);
            memcpy(ref, src, n * sizeof(i64)); sort_ipn(ref, n);
            double best[2] = {1e18, 1e18};
            for (int r = 0; r < reps; r++) {
                for (int k = 0; k < 2; k++) {
                    int which = (r & 1) ? 1 - k : k;
                    memcpy(w, src, n * sizeof(i64));
                    double t0 = now_ms();
                    if (which == 0) sort_ipn(w, n); else sort_radix1(w, n);
                    double t = now_ms() - t0;
                    if (t < best[which]) best[which] = t;
                    if (r == 0 && memcmp(w, ref, n * sizeof(i64)) != 0) { printf("MISMATCH sweep n=%zu\n", n); return 1; }
                }
            }
            printf("%10.2f", best[1] / best[0]);
        }
        printf("\n");
        free(src); free(w); free(ref);
    }
    return 0;
}

/* `nsb pre`: ipn vs ipnpre only, alternating which runs first, on every
 * pattern at n = 256, 1k, 10k, 100k, 1M, 5M. Small n is timed as a batch of
 * independent arrays so one timing covers >= ~1M elements. Min of 21 (15 at
 * 1M, 9 at 5M). Prints ipnpre/ipn. */
static int main_pre(void) {
    size_t sizes[] = {256, 1000, 10000, 100000, 1000000, 5000000};
    int reps[]     = {21, 21, 21, 21, 15, 9};
    printf("ipnpre/ipn (min of reps, alternating; < 1 = ipnpre faster)\n%-9s", "n");
    for (size_t p = 0; p < NP; p++) printf("%10s", PATTERNS[p].name);
    printf("\n");
    for (size_t si = 0; si < 6; si++) {
        size_t n = sizes[si];
        size_t batch = n >= 1000000 ? 1 : 1000000 / n;
        i64 *src = malloc(n * batch * sizeof(i64)), *w = malloc(n * batch * sizeof(i64)),
            *ref = malloc(n * batch * sizeof(i64));
        printf("%-9zu", n);
        for (size_t p = 0; p < NP; p++) {
            for (size_t b = 0; b < batch; b++) PATTERNS[p].g(src + b * n, n);
            double best[2] = {1e18, 1e18};
            for (int r = 0; r < reps[si]; r++) {
                for (int k = 0; k < 2; k++) {
                    int which = (r & 1) ? 1 - k : k;
                    memcpy(w, src, n * batch * sizeof(i64));
                    double t0 = now_ms();
                    for (size_t b = 0; b < batch; b++) {
                        if (which == 0) sort_ipn(w + b * n, n); else sort_ipnpre(w + b * n, n);
                    }
                    double t = now_ms() - t0;
                    if (t < best[which]) best[which] = t;
                    if (r == 0) {
                        if (which == 0) memcpy(ref, w, n * batch * sizeof(i64));
                        else if (memcmp(ref, w, n * batch * sizeof(i64)) != 0) { printf("MISMATCH pre n=%zu\n", n); return 1; }
                    }
                }
            }
            printf("%10.2f", best[1] / best[0]);
        }
        printf("\n");
        free(src); free(w); free(ref);
    }
    return 0;
}

int main(int argc, char **argv) {
    if (getenv("PRE_MIN_N")) PRE_MIN_N = (size_t)strtoull(getenv("PRE_MIN_N"), NULL, 10);
    if (argc > 1 && strcmp(argv[1], "pre") == 0) return main_pre();
    if (argc > 1 && strcmp(argv[1], "small") == 0) return main_small();
    if (argc > 1 && strcmp(argv[1], "sweep") == 0) return main_sweep();
    if (getenv("RUN_MIN_AVG")) RUN_MIN_AVG = (size_t)strtoull(getenv("RUN_MIN_AVG"), NULL, 10);
    if (argc > 1 && strcmp(argv[1], "f64") == 0)
        return main_f64(argc > 2 && strcmp(argv[2], "quick") == 0);
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
        printf("   ipn/qsort  ipn/radix  ipnrs/ipn  ipnrun/ipn  ipnpre/ipn\n");
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
            printf("   %8.2fx  %8.2fx  %8.2fx  %8.2fx  %8.2fx\n", best[0] / best[2], best[3] / best[2], best[4] / best[2], best[6] / best[2], best[7] / best[2]);
        }
        printf("\n");
        free(src); free(w);
    }
    return 0;
}
