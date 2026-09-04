/* test_scheduler_pin.c — pinned green threads (march_sched_spawn_pinned).
 *
 * A pinned proc must only ever execute on the OS thread that called
 * march_sched_run (scheduler 0), across every re-enqueue path:
 *   - the initial spawn (from the non-scheduler main thread AND from inside
 *     a scheduler thread),
 *   - cooperative yield re-push (march_sched_yield),
 *   - wake after park (march_sched_park_self / march_sched_wake from a
 *     worker thread),
 * while unpinned siblings still run on the other workers (the point of the
 * feature: main on the main thread, pmap still parallel).
 *
 * Built with -DMARCH_NUM_SCHEDULERS=4 (see test/dune) so the pin queue is
 * actually exercised; with one scheduler pinning is a documented no-op. */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#include "../runtime/march_scheduler.h"
#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <stdint.h>

static int g_tests_passed = 0, g_tests_failed = 0;
#define TEST_ASSERT(cond, msg) do { if (!(cond)) { \
    fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
    g_tests_failed++; return; } } while (0)
#define TEST_PASS() do { printf("  PASS: %s\n", __func__); g_tests_passed++; } while (0)

static pthread_t g_main_thread;

/* ── Test 1: yield storm — pinned proc yields 2000 times amid busy siblings ── */

static _Atomic int64_t g_pin_off_thread = 0;   /* times pinned ran off-main */
static _Atomic int64_t g_pin_runs       = 0;
static _Atomic int64_t g_sib_done       = 0;
static _Atomic int64_t g_sib_off_main   = 0;   /* sibling dispatches NOT on main */

static void burn(volatile int64_t iters) { volatile int64_t x = 0; while (iters-- > 0) x += iters; }

static void sibling_fn(void *arg) {
    (void)arg;
    for (int i = 0; i < 20; i++) {
        if (!pthread_equal(pthread_self(), g_main_thread))
            atomic_fetch_add(&g_sib_off_main, 1);
        burn(20000);
        march_sched_yield();
    }
    atomic_fetch_add(&g_sib_done, 1);
}

static void pinned_yielder(void *arg) {
    (void)arg;
    /* Spawn siblings from INSIDE a scheduler thread (local-deque push path). */
    for (int i = 0; i < 64; i++) march_sched_spawn(sibling_fn, NULL);
    for (int i = 0; i < 2000; i++) {
        atomic_fetch_add(&g_pin_runs, 1);
        if (!pthread_equal(pthread_self(), g_main_thread))
            atomic_fetch_add(&g_pin_off_thread, 1);
        march_sched_yield();
    }
}

static void test_pinned_yield_storm(void) {
    march_sched_init();
    g_main_thread = pthread_self();
    march_proc *p = march_sched_spawn_pinned(pinned_yielder, NULL);   /* external spawn path */
    TEST_ASSERT(p && p->pinned == 1, "spawn_pinned sets the flag");
    /* Also spawn siblings from the non-scheduler thread (global runq path). */
    for (int i = 0; i < 64; i++) march_sched_spawn(sibling_fn, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    TEST_ASSERT(atomic_load(&g_pin_runs) == 2000, "pinned proc ran all 2000 turns");
    TEST_ASSERT(atomic_load(&g_pin_off_thread) == 0, "pinned proc never ran off the main thread");
    TEST_ASSERT(atomic_load(&g_sib_done) == 128, "all siblings finished");
    TEST_ASSERT(atomic_load(&g_sib_off_main) > 0, "unpinned siblings did run on worker threads");
    TEST_PASS();
}

/* ── Test 2: park/wake — pinned proc parked, woken from worker threads ── */

static march_proc *g_sleeper = NULL;
static _Atomic int g_wakes = 0, g_wake_off_main = 0, g_wakers_done = 0;
static _Atomic int g_sleeper_done = 0;
#define N_WAKERS 8
#define WAKES_PER 200

/* How many times the pinned sleeper must park and resume before the run may
 * finish.  This is a REQUIREMENT the wakers cooperate to meet, not a count of
 * whatever the interleaving happened to produce.
 *
 * It used to be the latter, and that flaked: march_sched_wake is a no-op when
 * the target is not parked, so a sleeper that is slow to be scheduled -- it is
 * pinned to scheduler 0, which on a 3-core CI runner is also busy running the
 * wakers -- could park once, be woken once, and find g_wakers_done already at
 * N_WAKERS.  One resume, assertion wants eight, red run.  Observed three times
 * on main's macOS leg within two days of this test landing, and reproduced
 * here 19/20 by shrinking the wakers' own work (WAKES_PER=1, burn(0)) so they
 * finish before the sleeper gets going.
 *
 * Making the count deterministic strengthens the test rather than weakening
 * it: the assertion that carries the feature -- every resume happened on the
 * main thread -- is now backed by at least this many cross-thread wakes on
 * every run, instead of by however many the scheduler felt like delivering. */
#define REQUIRED_WAKES  N_WAKERS

/* Bound on the post-quota wake spin, so a genuinely broken march_sched_wake
 * ends the spin instead of burning a CI worker forever.  (It still cannot turn
 * that breakage into a clean failure: a sleeper that never resumes stays a
 * live parked proc and march_sched_run waits for it -- true of this test
 * before this change too.) */
#define WAKE_SPIN_LIMIT 2000000L

static void pinned_sleeper(void *arg) {
    (void)arg;
    /* Park until every waker has finished AND the quota is met; each resume
     * must be on main. */
    while (atomic_load(&g_wakers_done) < N_WAKERS
           || atomic_load(&g_wakes) < REQUIRED_WAKES) {
        march_sched_park_self();
        atomic_fetch_add(&g_wakes, 1);
        if (!pthread_equal(pthread_self(), g_main_thread))
            atomic_fetch_add(&g_wake_off_main, 1);
    }
    atomic_store(&g_sleeper_done, 1);
}

static void waker_fn(void *arg) {
    (void)arg;
    for (int i = 0; i < WAKES_PER; i++) {
        march_sched_wake(g_sleeper);   /* idempotent when the target isn't waiting */
        burn(2000);
        march_sched_yield();
    }
    atomic_fetch_add(&g_wakers_done, 1);
    /* Keep waking until the sleeper actually finishes, rather than firing one
     * final wake and hoping it lands.  This is what makes REQUIRED_WAKES a
     * property of the test instead of of the interleaving, and it also closes
     * the lost-wakeup window where the sleeper parks just after the last
     * waker's single parting wake. */
    for (long spins = 0;
         !atomic_load(&g_sleeper_done) && spins < WAKE_SPIN_LIMIT;
         spins++) {
        march_sched_wake(g_sleeper);
        march_sched_yield();
    }
}

static void test_pinned_park_wake(void) {
    march_sched_init();
    g_main_thread = pthread_self();
    atomic_store(&g_wakes, 0);
    atomic_store(&g_wake_off_main, 0);
    atomic_store(&g_wakers_done, 0);
    atomic_store(&g_sleeper_done, 0);
    g_sleeper = march_sched_spawn_pinned(pinned_sleeper, NULL);
    for (int i = 0; i < N_WAKERS; i++) march_sched_spawn(waker_fn, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    TEST_ASSERT(atomic_load(&g_wakers_done) == N_WAKERS, "all wakers finished");
    TEST_ASSERT(atomic_load(&g_sleeper_done) == 1, "sleeper finished (was not left parked)");
    TEST_ASSERT(atomic_load(&g_wakes) >= REQUIRED_WAKES,
                "sleeper was woken at least REQUIRED_WAKES times");
    TEST_ASSERT(atomic_load(&g_wake_off_main) == 0, "pinned proc resumed on main thread after every wake");
    TEST_PASS();
}

int main(void) {
    setvbuf(stdout, NULL, _IONBF, 0);
    printf("=== March scheduler — pinned procs (MARCH_NUM_SCHEDULERS=%d) ===\n", MARCH_NUM_SCHEDULERS);
    test_pinned_yield_storm();
    test_pinned_park_wake();
    printf("\nResults: %d passed, %d failed\n", g_tests_passed, g_tests_failed);
    return g_tests_failed > 0 ? 1 : 0;
}
