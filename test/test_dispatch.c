/* test_dispatch.c — HCR versioned dispatch table (runtime/march_dispatch.c).
 *
 * Tests
 * ─────
 *  1. first publish becomes current; enter pins it and returns its fn_ptr
 *  2. leave drops the refcount back to zero
 *  3. a second publish advances current; enter sees the new version
 *  4. a caller pinned to the old version stays pinned across a publish, and
 *     leave targets that old version (not current)
 *  5. publish fails (-1) when no non-current ring slot is reclaimable, and
 *     succeeds again once the blocking caller leaves
 *  6. impl_hash is stored per version and retrievable
 *  7. out-of-range name_id is handled safely
 *  8. reclaim never dlcloses a version a reader can still pin (deterministic:
 *     a reader runs INSIDE the close hook, i.e. while "dlclose" is in flight)
 *  9. the same property under real threads: readers pin the version about to
 *     be reclaimed while a publisher cycles; no pin may overlap its close
 * 10. the per-slot reclaim condition (II.4.2): a unit pinned to epoch 5 that
 *     calls a function last changed at epoch 2 keeps the epoch-2 version
 *     alive although epoch 2 itself has no pins
 * 11. equal epochs (epoch-less publishes): enter_gen prefers current
 * 12. a staged version is invisible to every reader until it is committed
 * 13. the epoch pin table: pin/unpin/reserve/advance and a full table
 */
#include "../runtime/march_dispatch.h"
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <sched.h>
#include <unistd.h>
#include <time.h>
#include <stdatomic.h>

static int g_failed = 0;

#define CHECK(cond, msg) do {                                               \
    if (!(cond)) {                                                          \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_failed++;                                                         \
    }                                                                       \
} while (0)

/* distinct fake code pointers — never called, just compared */
static void *FN1 = (void *)0x1111;
static void *FN2 = (void *)0x2222;
static void *FN3 = (void *)0x3333;

static const char *H1 = "1111111111111111111111111111111111111111111111111111111111111111";
static const char *H2 = "2222222222222222222222222222222222222222222222222222222222222222";
static const char *S1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
static const char *S2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

static void test_first_publish_and_enter(void) {
    march_dispatch_init(4);
    int idx = march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);
    CHECK(idx == 0, "first publish uses ring index 0");
    CHECK(march_dispatch_current(0) == 0, "current is 0 after first publish");

    uint32_t v = 99;
    void *fn = march_dispatch_enter(0, &v);
    CHECK(fn == FN1, "enter returns the published fn_ptr");
    CHECK(v == 0, "enter reports the pinned version index");
    CHECK(march_dispatch_refs(0, 0) == 1, "refs incremented to 1 after enter");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

static void test_leave_drops_refs(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);
    uint32_t v;
    march_dispatch_enter(0, &v);
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_refs(0, 0) == 0, "refs back to 0 after leave");
    march_dispatch_shutdown();
}

static void test_second_publish_advances_current(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);
    int idx2 = march_dispatch_publish(0, FN2, H2, NULL, MARCH_NATIVE);
    CHECK(idx2 == 1, "second publish uses the other ring slot");
    CHECK(march_dispatch_current(0) == 1, "current advanced to 1");
    uint32_t v;
    void *fn = march_dispatch_enter(0, &v);
    CHECK(fn == FN2, "enter now returns the new version");
    CHECK(v == 1, "pinned version is the new one");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

static void test_old_version_stays_pinned(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);
    uint32_t vold;
    void *fnold = march_dispatch_enter(0, &vold);   /* pin v0 */
    CHECK(fnold == FN1, "old caller entered v0");

    march_dispatch_publish(0, FN2, H2, NULL, MARCH_NATIVE); /* current -> 1 */
    uint32_t vnew;
    void *fnnew = march_dispatch_enter(0, &vnew);    /* pin v1 */
    CHECK(fnnew == FN2, "new caller entered v1");
    CHECK(vnew == 1, "new caller pinned v1");
    CHECK(march_dispatch_refs(0, 0) == 1, "old version still pinned (refs 1)");
    CHECK(march_dispatch_refs(0, 1) == 1, "new version pinned (refs 1)");

    march_dispatch_leave(0, vold);                   /* unpin the OLD version */
    CHECK(march_dispatch_refs(0, 0) == 0, "old version unpinned");
    CHECK(march_dispatch_refs(0, 1) == 1, "new version untouched by old leave");
    march_dispatch_leave(0, vnew);
    march_dispatch_shutdown();
}

static void *FN4 = (void *)0x4444;

static void test_publish_blocked_then_unblocked(void) {
    march_dispatch_init(4);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE); /* v0, current 0 */
    uint32_t v0, v1;
    march_dispatch_enter(0, &v0);                     /* pin v0 */
    march_dispatch_publish(0, FN2, H2, NULL, MARCH_NATIVE); /* v1, current 1 */
    march_dispatch_enter(0, &v1);                     /* pin v1 */
    CHECK(march_dispatch_publish(0, FN3, H1, NULL, MARCH_NATIVE) == 2,
          "third publish takes the free third ring slot");

    /* Cap is 3 (D32); every ring slot is occupied: slot 2 is current, slots 0
       and 1 have calls in flight.  A fourth publish has no reclaimable slot. */
    CHECK(!march_dispatch_can_stage(0), "can_stage reports no slot");
    int idx4 = march_dispatch_publish(0, FN4, H1, NULL, MARCH_NATIVE);
    CHECK(idx4 == -1, "publish blocked while old versions are pinned");
    CHECK(march_dispatch_current(0) == 2, "current unchanged after blocked publish");

    march_dispatch_leave(0, v0);                      /* free slot 0 */
    CHECK(march_dispatch_can_stage(0), "can_stage sees the freed slot");
    int idx4b = march_dispatch_publish(0, FN4, H1, NULL, MARCH_NATIVE);
    CHECK(idx4b == 0, "publish reclaims the freed slot");
    CHECK(march_dispatch_current(0) == 0, "current advanced to reclaimed slot");
    march_dispatch_leave(0, v1);
    march_dispatch_shutdown();
}

static void test_impl_hash_stored(void) {
    march_dispatch_init(4);
    march_dispatch_publish(2, FN1, H1, NULL, MARCH_NATIVE);
    CHECK(strcmp(march_dispatch_impl_hash(2, 0), H1) == 0, "impl_hash stored per version");
    march_dispatch_shutdown();
}

static void test_out_of_range_is_safe(void) {
    march_dispatch_init(2);
    CHECK(march_dispatch_publish(5, FN1, H1, NULL, MARCH_NATIVE) == -1, "publish out of range -> -1");
    uint32_t v;
    CHECK(march_dispatch_enter(5, &v) == NULL, "enter out of range -> NULL");
    march_dispatch_leave(5, 0); /* must not crash */
    march_dispatch_shutdown();
}

static void test_name_registry(void) {
    march_dispatch_init(4);
    march_dispatch_register_name(0, "App.foo");
    march_dispatch_register_name(1, "App.bar");
    march_dispatch_register_name(2, "App.baz");

    uint32_t id = 99;
    CHECK(march_dispatch_name_to_id("App.foo", &id) == 1 && id == 0, "lookup App.foo -> 0");
    CHECK(march_dispatch_name_to_id("App.bar", &id) == 1 && id == 1, "lookup App.bar -> 1");
    CHECK(march_dispatch_name_to_id("App.baz", &id) == 1 && id == 2, "lookup App.baz -> 2");
    CHECK(march_dispatch_name_to_id("App.missing", &id) == 0, "lookup unknown -> 0");
    march_dispatch_shutdown();
    /* After shutdown, registry is cleared. */
    CHECK(march_dispatch_name_to_id("App.foo", &id) == 0, "after shutdown, registry cleared");
    march_dispatch_init(0);   /* leave in clean state for subsequent tests */
    march_dispatch_shutdown();
    printf("PASS: test_name_registry\n");
}

/* ── Concurrency regression: startup-window publish/enter race ──────────────
 *
 * Reproduces the HCR startup crash: HTTP worker threads call
 * march_dispatch_enter on boundary slots while the main thread is still running
 * the initial publish loop (the "serve a request during warmup" window).
 *
 * Before the live-gate fix, enter() could observe a calloc-zeroed slot
 * (current=0, ring[0].fn_ptr=NULL) or a half-written slot and return a NULL /
 * torn fn_ptr, which the generated call site jumps to (crash / OOM from a
 * corrupted value).  The fix makes enter() return a slot's fn_ptr ONLY after
 * acquire-observing the release store of `live`, so the ONLY outcomes are:
 *   (a) a fully-published pointer we actually published, or
 *   (b) NULL, meaning "not published yet" (the call site falls back to a direct
 *       static call — safe).
 * A non-NULL pointer that was never published would be a torn read: must be 0.
 */
#define RACE_SLOTS   32
#define RACE_WORKERS 6

static void *g_race_expected[RACE_SLOTS];
static _Atomic int  g_race_go   = 0;
static _Atomic int  g_race_stop = 0;
static _Atomic long g_race_bad  = 0;   /* non-NULL, never-published => torn read */
static _Atomic long g_race_ok   = 0;
static _Atomic long g_race_null = 0;

static int race_is_expected(void *p) {
    for (int i = 0; i < RACE_SLOTS; i++)
        if (g_race_expected[i] == p) return 1;
    return 0;
}

static void *race_worker(void *arg) {
    (void)arg;
    while (!atomic_load_explicit(&g_race_go, memory_order_acquire)) { }
    while (!atomic_load_explicit(&g_race_stop, memory_order_acquire)) {
        for (uint32_t id = 0; id < RACE_SLOTS; id++) {
            uint32_t v = 0;
            void *fn = march_dispatch_enter(id, &v);
            if (fn == NULL) {
                atomic_fetch_add_explicit(&g_race_null, 1, memory_order_relaxed);
            } else if (!race_is_expected(fn)) {
                atomic_fetch_add_explicit(&g_race_bad, 1, memory_order_relaxed);
            } else {
                atomic_fetch_add_explicit(&g_race_ok, 1, memory_order_relaxed);
                march_dispatch_leave(id, v);
            }
        }
    }
    return NULL;
}

static void test_startup_publish_enter_race(void) {
    for (int i = 0; i < RACE_SLOTS; i++)
        g_race_expected[i] = (void *)(uintptr_t)(0x100000 + i);

    pthread_t th[RACE_WORKERS];
    const int cycles = 500;
    for (int c = 0; c < cycles; c++) {
        atomic_store_explicit(&g_race_go,   0, memory_order_release);
        atomic_store_explicit(&g_race_stop, 0, memory_order_release);
        for (int i = 0; i < RACE_WORKERS; i++)
            pthread_create(&th[i], NULL, race_worker, NULL);

        atomic_store_explicit(&g_race_go, 1, memory_order_release);
        march_dispatch_init(RACE_SLOTS);
        for (uint32_t id = 0; id < RACE_SLOTS; id++) {
            char h[65]; memset(h, '0' + (int)(id % 10), 64); h[64] = 0;
            march_dispatch_publish(id, g_race_expected[id], h, NULL, MARCH_NATIVE);
        }

        atomic_store_explicit(&g_race_stop, 1, memory_order_release);
        for (int i = 0; i < RACE_WORKERS; i++)
            pthread_join(th[i], NULL);
        march_dispatch_shutdown();
    }

    long bad  = atomic_load(&g_race_bad);
    long ok   = atomic_load(&g_race_ok);
    long nul  = atomic_load(&g_race_null);
    CHECK(bad == 0, "enter() never returns a torn / never-published pointer during warmup");
    /* Sanity: the race actually exercised both paths (some pins, some warmup
       fallbacks); otherwise the test isn't proving anything. */
    CHECK(ok > 0,  "enter() pinned at least some fully-published versions");
    if (g_failed == 0)
        printf("PASS: test_startup_publish_enter_race (ok=%ld null_fallback=%ld torn=%ld)\n",
               ok, nul, bad);
}

/* ── 8. retire-before-dlclose (deterministic) ─────────────────────────────
 * Reclaim used to do: refs==0 check -> dlclose -> ... -> live=0.  A reader that
 * passed its live check just before the refs check could pin and re-validate
 * while dlclose was running (live still 1) and get a fn_ptr into the unloading
 * .so.  enter_gen selects a NON-current version by epoch, so from inside the
 * close hook we can play that reader exactly: it must not be handed the
 * version whose handle is being closed. */
static void *H_OLD = (void *)0xA0A0;
static void *H_NEW = (void *)0xB0B0;
static int   g_hook_calls = 0;
static void *g_hook_reader_fn = NULL;
static uint64_t g_hook_refs_at_close = 0;

static void close_hook_reader(void *handle) {
    g_hook_calls++;
    if (handle != H_OLD) return;
    g_hook_refs_at_close = march_dispatch_refs(0, 0);
    uint32_t v = 99;
    g_hook_reader_fn = march_dispatch_enter_gen(0, 1, &v);  /* wants epoch 1 = v0 */
    if (g_hook_reader_fn) march_dispatch_leave(0, v);
}

/* Make [e] the current epoch the way an activation does (reserve its entry,
 * then advance), so older epochs lose the current-role pin. */
static void advance_to(uint32_t e) {
    CHECK(march_epoch_reserve(e) == 0, "epoch entry reserved");
    march_epoch_advance(e);
}

static void test_reclaim_retires_before_dlclose(void) {
    march_epoch_reset_for_test();
    march_dispatch_init(1);
    march_dispatch_set_close_hook(close_hook_reader);
    g_hook_calls = 0; g_hook_reader_fn = NULL;

    CHECK(march_dispatch_publish_epoch(0, FN1, H1, NULL, MARCH_NATIVE, 1) == 0, "v0 at slot 0");
    march_dispatch_set_handle(0, 0, H_OLD);
    CHECK(march_dispatch_publish_epoch(0, FN2, H2, NULL, MARCH_NATIVE, 2) == 1, "v1 at slot 1");
    march_dispatch_set_handle(0, 1, H_NEW);
    CHECK(march_dispatch_publish_epoch(0, FN3, H2, NULL, MARCH_NATIVE, 3) == 2, "v2 at slot 2");
    march_dispatch_set_handle(0, 2, H_NEW);
    advance_to(3);   /* nothing is pinned to epochs 1 or 2 any more */

    /* Before the reclaim, an epoch-1 caller legitimately reaches v0. */
    uint32_t v = 99;
    CHECK(march_dispatch_enter_gen(0, 1, &v) == FN1 && v == 0, "epoch-1 caller reaches v0");
    march_dispatch_leave(0, v);

    /* Fourth publish reclaims slot 0 (the lowest reclaimable epoch) and
       closes H_OLD. */
    int idx = march_dispatch_publish_epoch(0, FN4, H1, NULL, MARCH_NATIVE, 4);
    CHECK(idx == 0, "fourth publish reclaims slot 0");
    CHECK(g_hook_calls == 1, "reclaim closed exactly one handle");
    CHECK(g_hook_refs_at_close == 0, "no pin on v0 when its handle is closed");
    CHECK(g_hook_reader_fn != FN1,
          "a reader racing the close is NOT handed the closing version's fn_ptr");
    CHECK(march_dispatch_refs(0, 0) == 0 && march_dispatch_refs(0, 1) == 0,
          "hook reader's pins balanced");

    march_dispatch_set_close_hook(NULL);
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++)
        march_dispatch_set_handle(0, i, NULL);  /* fake handles: keep shutdown off dlclose */
    march_dispatch_shutdown();
    march_epoch_reset_for_test();
    if (g_failed == 0) printf("PASS: test_reclaim_retires_before_dlclose\n");
}

/* ── 9. retire-before-dlclose under real threads ──────────────────────────
 * Publish k installs fn k / handle k with epoch k.  Readers aim enter_gen at
 * epoch k-1: the non-current version, i.e. the NEXT one to be reclaimed.  The
 * close hook marks handle k closed; a reader that is still pinned to fn k when
 * it re-checks that flag has held a pin across the close = the bug. */
/* Not a fixed publish count: on CI's macos-15 runner a fixed 50k publishes
 * finished before any reader was scheduled (pins=0, blocked=0; the vacuity
 * guards below caught it).  Readers now signal they are running before the
 * publisher starts, and the publisher runs until the race has demonstrably
 * been exercised (MIN_PUBS publishes and MIN_PINS pins), capped by MAX_PUBS
 * and a wall-clock deadline.  The deterministic publish-blocked test above
 * proves the full-ring condition; demanding a scheduler-dependent blocked
 * publish here made this safety stress test flaky on macOS. */
#define RECL_READERS   4
#define RECL_MIN_PUBS  20000
#define RECL_MAX_PUBS  1000000
#define RECL_MIN_PINS  10000
#define RECL_DEADLINE_S 10
static _Atomic uint32_t g_recl_k       = 0;
static _Atomic int      g_recl_stop    = 0;
static _Atomic int      g_recl_started = 0;
static _Atomic long     g_recl_bad     = 0;
static _Atomic long     g_recl_pins    = 0;
static _Atomic uint8_t  g_recl_closed[RECL_MAX_PUBS + 2];

static void *recl_fn(uint32_t k)     { return (void *)(uintptr_t)(0x100000u + 16u * k); }
static void *recl_handle(uint32_t k) { return (void *)(uintptr_t)(0x900000u + 16u * k); }

static void recl_close_hook(void *handle) {
    uint32_t k = (uint32_t)(((uintptr_t)handle - 0x900000u) / 16u);
    atomic_store_explicit(&g_recl_closed[k], 1, memory_order_seq_cst);
}

static void *recl_reader(void *arg) {
    (void)arg;
    atomic_fetch_add_explicit(&g_recl_started, 1, memory_order_release);
    unsigned iter = 0;
    while (!atomic_load_explicit(&g_recl_stop, memory_order_acquire)) {
        if ((++iter & 63) == 0) sched_yield();   /* don't starve the publisher */
        uint32_t k = atomic_load_explicit(&g_recl_k, memory_order_acquire);
        if (k < 2) continue;
        uint32_t v;
        void *fn = march_dispatch_enter_gen(0, k - 1, &v);
        if (!fn) continue;
        uint32_t got = (uint32_t)(((uintptr_t)fn - 0x100000u) / 16u);
        atomic_fetch_add_explicit(&g_recl_pins, 1, memory_order_relaxed);
        for (volatile int i = 0; i < 50; i++) { }       /* "call" into the .so */
        /* Now and then give the CPU away WHILE PINNED.  Without this the pin
         * window is so short that on CI's ubuntu runner 1M publishes never
         * once met a pinned candidate (blocked=0, pins=249860): the readers and
         * the publisher simply never overlapped.  Yielding inside the window
         * makes the overlap happen by construction on a busy or small box. */
        if ((iter & 7) == 0) sched_yield();
        if (atomic_load_explicit(&g_recl_closed[got], memory_order_seq_cst))
            atomic_fetch_add_explicit(&g_recl_bad, 1, memory_order_relaxed);
        march_dispatch_leave(0, v);
    }
    return NULL;
}

static void test_reclaim_race_threads(void) {
    march_epoch_reset_for_test();
    march_dispatch_init(1);
    march_dispatch_set_close_hook(recl_close_hook);
    pthread_t th[RECL_READERS];
    for (int i = 0; i < RECL_READERS; i++) pthread_create(&th[i], NULL, recl_reader, NULL);

    while (atomic_load_explicit(&g_recl_started, memory_order_acquire) < RECL_READERS)
        sched_yield();

    struct timespec t0, now;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    long blocked = 0;
    uint32_t k = 1;
    for (;;) {
        if (k > RECL_MAX_PUBS) break;
        if (k > RECL_MIN_PUBS
            && atomic_load_explicit(&g_recl_pins, memory_order_relaxed) >= RECL_MIN_PINS)
            break;
        if ((k & 1023) == 0) {
            clock_gettime(CLOCK_MONOTONIC, &now);
            if (now.tv_sec - t0.tv_sec >= RECL_DEADLINE_S) break;
            sched_yield();                  /* let readers in on a small runner */
        }
        int idx = march_dispatch_publish_epoch(0, recl_fn(k), H1, NULL, MARCH_NATIVE, k);
        if (idx < 0) { blocked++; sched_yield(); continue; }  /* a reader holds the old version */
        march_dispatch_set_handle(0, (uint32_t)idx, recl_handle(k));
        /* Epoch k is now current, as an activation would leave it; the
           previous epochs keep no role pin, so only the readers' per-call
           refs stand between a version and its reclaim. */
        if (k > 1 && march_epoch_reserve(k) == 0) march_epoch_advance(k);
        atomic_store_explicit(&g_recl_k, k, memory_order_release);
        k++;
    }
    atomic_store_explicit(&g_recl_stop, 1, memory_order_release);
    for (int i = 0; i < RECL_READERS; i++) pthread_join(th[i], NULL);

    long bad = atomic_load(&g_recl_bad), pins = atomic_load(&g_recl_pins);
    CHECK(bad == 0, "no reader held a pin across its version's dlclose");
    /* The vacuity guards need parallelism: on one CPU a reader is almost never
       preempted while pinned.  Skip them there, loudly; the deterministic
       case above covers the full-ring blocking condition. */
    if (sysconf(_SC_NPROCESSORS_ONLN) >= 2) {
        CHECK(pins >= RECL_MIN_PINS, "readers actually pinned reclaim candidates (else vacuous)");
    } else {
        printf("SKIP: test_reclaim_race_threads vacuity guards (single CPU online)\n");
    }
    march_dispatch_set_close_hook(NULL);
    for (uint32_t i = 0; i < MARCH_MAX_LIVE_VERSIONS; i++) march_dispatch_set_handle(0, i, NULL);
    march_dispatch_shutdown();
    march_epoch_reset_for_test();
    printf("%s: test_reclaim_race_threads (publishes=%u pins=%ld blocked_publishes=%ld overlap=%ld)\n",
           bad == 0 ? "PASS" : "FAIL", k - 1, pins, blocked, bad);
}

/* ── 10. the per-slot reclaim condition (II.4.2) ──────────────────────────
 * Slot history: v0 baseline (epoch 0), v1 changed at epoch 2, v2 changed at
 * epoch 6 (current).  A unit pinned to epoch 5 resolves to v1 ("newest at or
 * before 5").  Epoch 2 itself has NO pins.  The wrong rule ("a version is free
 * when its own epoch is retired") would reclaim v1 and unmap the code the
 * epoch-5 unit is running; the right one keeps it: 5 lies in [2, 6).  v0 is
 * kept by a call in flight (refs), which blocks both rules, so v1 is the only
 * candidate the wrong rule could take.  Checked RED under the wrong rule. */
static void test_reclaim_respects_newer_pinned_epoch(void) {
    march_epoch_reset_for_test();
    march_dispatch_init(1);
    CHECK(march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE) == 0, "baseline at epoch 0");
    advance_to(2);
    CHECK(march_dispatch_publish_epoch(0, FN2, H2, NULL, MARCH_NATIVE, 2) == 1, "v1 at epoch 2");
    CHECK(march_epoch_pin(1) == -1, "epoch 1 lost its holder when 2 became current");
    advance_to(5);
    CHECK(march_epoch_pin(5) == 0, "a unit pins epoch 5");
    advance_to(6);
    CHECK(march_dispatch_publish_epoch(0, FN3, H1, NULL, MARCH_NATIVE, 6) == 2, "v2 at epoch 6");
    CHECK(march_epoch_pins(2) == 0, "epoch 2 itself has no pins");
    CHECK(march_epoch_pins(5) == 1, "epoch 5 has one unit");

    /* Keep v0 alive with a call in flight. */
    uint32_t v0 = 99;
    CHECK(march_dispatch_enter_gen(0, 1, &v0) == FN1 && v0 == 0, "a call holds v0");

    uint32_t v = 99;
    CHECK(march_dispatch_enter_gen(0, 5, &v) == FN2 && v == 1,
          "the epoch-5 unit resolves to the epoch-2 version");
    march_dispatch_leave(0, v);

    CHECK(!march_dispatch_can_stage(0),
          "no version reclaimable: v1 is in use by epoch 5, v0 by a call");
    CHECK(march_dispatch_publish_epoch(0, FN4, H2, NULL, MARCH_NATIVE, 7) == -1,
          "the publish waits instead of reclaiming the epoch-2 version");
    CHECK(march_dispatch_live(0, 1), "the epoch-2 version is still live");
    CHECK(march_dispatch_enter_gen(0, 5, &v) == FN2 && v == 1,
          "the epoch-5 unit still reaches it");
    march_dispatch_leave(0, v);

    march_epoch_unpin(5);   /* the unit exits */
    CHECK(march_dispatch_can_stage(0), "with epoch 5 retired, v1 is reclaimable");
    CHECK(march_dispatch_publish_epoch(0, FN4, H2, NULL, MARCH_NATIVE, 7) == 1,
          "the waiting publish reclaims v1, not v0");
    CHECK(march_dispatch_live(0, 0), "v0 (its call still in flight) survives");
    march_dispatch_leave(0, v0);
    march_dispatch_shutdown();
    march_epoch_reset_for_test();
    if (g_failed == 0) printf("PASS: test_reclaim_respects_newer_pinned_epoch\n");
}

/* ── 11. equal epochs prefer current ─────────────────────────────────────── */
static void test_equal_epochs_prefer_current(void) {
    march_epoch_reset_for_test();
    march_dispatch_init(1);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);   /* epoch 0 */
    march_dispatch_publish(0, FN2, H2, NULL, MARCH_NATIVE);   /* epoch 0, current */
    uint32_t v;
    CHECK(march_dispatch_enter_gen(0, 1, &v) == FN2 && v == 1,
          "an epoch-less redeploy is what every unit sees");
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_enter_unit(0, &v) == FN2,
          "enter_unit with no proc follows current");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

/* ── 12. staged versions are invisible ───────────────────────────────────── */
static void test_staged_version_invisible(void) {
    march_epoch_reset_for_test();
    march_dispatch_init(1);
    march_dispatch_publish(0, FN1, H1, NULL, MARCH_NATIVE);
    int idx = march_dispatch_stage(0, FN2, H2, NULL, MARCH_NATIVE, 3);
    CHECK(idx == 1, "stage takes the free slot");
    uint32_t v;
    CHECK(march_dispatch_enter(0, &v) == FN1, "enter does not see the staged version");
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_enter_gen(0, 9, &v) == FN1,
          "enter_gen at a later epoch does not see it either");
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_can_stage(0), "a staged slot is not counted as free, one left");
    CHECK(march_dispatch_stage(0, FN3, H1, NULL, MARCH_NATIVE, 3) == 2, "second stage");
    march_dispatch_unstage(0, 2);
    march_dispatch_commit(0, (uint32_t)idx);
    CHECK(march_dispatch_current(0) == 1, "commit makes it current");
    CHECK(march_dispatch_enter_gen(0, 3, &v) == FN2, "and selectable at its epoch");
    march_dispatch_leave(0, v);
    CHECK(march_dispatch_enter_gen(0, 2, &v) == FN1, "older units keep the old version");
    march_dispatch_leave(0, v);
    march_dispatch_shutdown();
}

/* ── 13. the pin table ────────────────────────────────────────────────────── */
static void test_epoch_pin_table(void) {
    march_epoch_reset_for_test();
    CHECK(march_epoch_current() == MARCH_EPOCH_BASE, "fresh process starts at the base epoch");
    CHECK(march_epoch_pins(MARCH_EPOCH_BASE) == 1, "the current role holds one pin");
    CHECK(march_epoch_next(0) == MARCH_EPOCH_BASE + 1, "next is above current");
    CHECK(march_epoch_next(40) == 40, "a larger client epoch is kept");
    CHECK(march_epoch_pin(7) == -1, "an epoch with no holder cannot be pinned");
    CHECK(march_epoch_pin(MARCH_EPOCH_BASE) == 0, "the current epoch can");
    advance_to(2);
    CHECK(march_epoch_pins(MARCH_EPOCH_BASE) == 1, "advance dropped only the role pin");
    march_epoch_unpin(MARCH_EPOCH_BASE);
    CHECK(march_epoch_pins(MARCH_EPOCH_BASE) == 0, "epoch 1 retired");
    CHECK(march_epoch_pin(MARCH_EPOCH_BASE) == -1, "and cannot be revived by a pin");
    /* Fill the table: 8 entries, 2 is current; pin 3..9 so none can recycle. */
    for (uint32_t e = 3; e <= 9; e++) CHECK(march_epoch_reserve(e) == 0, "reserve");
    CHECK(march_epoch_reserve(10) == -1, "a full table refuses a new epoch");
    uint32_t eps[MARCH_EPOCH_PIN_SLOTS]; int64_t cnt[MARCH_EPOCH_PIN_SLOTS];
    CHECK(march_epoch_pin_table(eps, cnt, MARCH_EPOCH_PIN_SLOTS) == MARCH_EPOCH_PIN_SLOTS,
          "the snapshot lists every pinned epoch");
    march_epoch_unpin(3);
    CHECK(march_epoch_reserve(10) == 0, "a retired entry is reused");
    march_epoch_reset_for_test();
    if (g_failed == 0) printf("PASS: test_epoch_pin_table\n");
}

int main(void) {
    test_first_publish_and_enter();
    test_leave_drops_refs();
    test_second_publish_advances_current();
    test_old_version_stays_pinned();
    test_publish_blocked_then_unblocked();
    test_impl_hash_stored();
    test_out_of_range_is_safe();
    test_name_registry();
    test_startup_publish_enter_race();
    test_reclaim_retires_before_dlclose();
    test_reclaim_race_threads();
    test_reclaim_respects_newer_pinned_epoch();
    test_equal_epochs_prefer_current();
    test_staged_version_invisible();
    test_epoch_pin_table();
    if (g_failed == 0) { printf("test_dispatch: all checks passed\n"); return 0; }
    fprintf(stderr, "test_dispatch: %d check(s) failed\n", g_failed);
    return 1;
}
