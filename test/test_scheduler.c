/* test_scheduler.c — Tests for the Phase 1 green-thread scheduler.
 *
 * Tests
 * ─────
 *  1. test_spawn_1000      — Spawn 1000 processes, each increments a counter.
 *                            Verify counter == 1000 after march_sched_run().
 *  2. test_yield_interleaving — Two processes log 'A'/'B' around explicit
 *                            yield calls; verify round-robin ordering.
 *  3. test_reduction_preemption — Processes burn their reduction budget via
 *                            march_sched_tick(); verify automatic preemption
 *                            interleaves them correctly.
 *  4. test_nested_spawn    — A process spawns child processes from inside its
 *                            own function body; verify all children run.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#include "../runtime/march_scheduler.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

/* ── Lightweight test harness ─────────────────────────────────────────── */

static int g_tests_passed = 0;
static int g_tests_failed = 0;

#define TEST_ASSERT(cond, msg) do {                                          \
    if (!(cond)) {                                                           \
        fprintf(stderr, "  FAIL [%s:%d]: %s\n", __func__, __LINE__, (msg)); \
        g_tests_failed++;                                                    \
        return;                                                              \
    }                                                                        \
} while (0)

#define TEST_PASS() do {                    \
    printf("  PASS: %s\n", __func__);       \
    g_tests_passed++;                       \
} while (0)

/* ── Test 1: spawn_1000 ───────────────────────────────────────────────── */
/*
 * Spawn 1000 processes, each of which atomically increments a counter.
 * After march_sched_run() returns, the counter must equal 1000.
 */

static _Atomic int g_counter_1000 = 0;

static void worker_inc(void *arg) {
    (void)arg;
    atomic_fetch_add_explicit(&g_counter_1000, 1, memory_order_relaxed);
}

static void test_spawn_1000(void) {
    g_counter_1000 = 0;
    march_sched_init();

    for (int i = 0; i < 1000; i++) {
        march_proc *p = march_sched_spawn(worker_inc, NULL);
        TEST_ASSERT(p != NULL, "march_sched_spawn should not return NULL");
    }

    march_sched_run();

    TEST_ASSERT(g_counter_1000 == 1000,
                "counter should equal the number of spawned processes");
    TEST_ASSERT(march_sched_total_spawned() == 1000,
                "total_spawned should equal 1000");
    TEST_PASS();
}

/* ── Test 2: yield_interleaving ───────────────────────────────────────── */
/*
 * Spawn process A and process B in that order.  Each logs its letter,
 * calls march_sched_yield(), then logs its letter again.  The expected
 * execution order under round-robin is: A B A B.
 */

static char  g_ilog[8];
static int   g_ipos = 0;

static void ilog_a(void *arg) {
    (void)arg;
    g_ilog[g_ipos++] = 'A';
    march_sched_yield();
    g_ilog[g_ipos++] = 'A';
}

static void ilog_b(void *arg) {
    (void)arg;
    g_ilog[g_ipos++] = 'B';
    march_sched_yield();
    g_ilog[g_ipos++] = 'B';
}

static void test_yield_interleaving(void) {
    g_ipos = 0;
    memset(g_ilog, 0, sizeof(g_ilog));
    march_sched_init();
    march_sched_spawn(ilog_a, NULL);
    march_sched_spawn(ilog_b, NULL);
    march_sched_run();

    TEST_ASSERT(g_ipos == 4, "should have exactly 4 log entries");
    TEST_ASSERT(g_ilog[0] == 'A', "entry 0 should be A (A runs first)");
    TEST_ASSERT(g_ilog[1] == 'B', "entry 1 should be B (B runs after A yields)");
    TEST_ASSERT(g_ilog[2] == 'A', "entry 2 should be A (A resumes)");
    TEST_ASSERT(g_ilog[3] == 'B', "entry 3 should be B (B resumes)");
    TEST_PASS();
}

/* ── Test 3: reduction_preemption ────────────────────────────────────── */
/*
 * Two processes (X, Y) each tick MARCH_REDUCTION_BUDGET + 10 times total.
 * Expected: X starts, hits its budget after ~MARCH_REDUCTION_BUDGET ticks
 * and is preempted, then Y runs, hits its budget, then X and Y finish.
 * We verify that Y runs *before* X finishes its work (true interleaving).
 */

static char  g_rlog[8];
static int   g_rpos = 0;

static void reduce_x(void *arg) {
    (void)arg;
    g_rlog[g_rpos++] = 'X'; /* logged when X first gets CPU */
    for (int i = 0; i < MARCH_REDUCTION_BUDGET + 10; i++) {
        march_sched_tick();
    }
    g_rlog[g_rpos++] = 'X'; /* logged when X finishes */
}

static void reduce_y(void *arg) {
    (void)arg;
    g_rlog[g_rpos++] = 'Y';
    for (int i = 0; i < MARCH_REDUCTION_BUDGET + 10; i++) {
        march_sched_tick();
    }
    g_rlog[g_rpos++] = 'Y';
}

static void test_reduction_preemption(void) {
    g_rpos = 0;
    memset(g_rlog, 0, sizeof(g_rlog));
    march_sched_init();
    march_sched_spawn(reduce_x, NULL);
    march_sched_spawn(reduce_y, NULL);
    march_sched_run();

    TEST_ASSERT(g_rpos == 4, "should have exactly 4 log entries");

    /* X is spawned first so it gets the CPU first. */
    TEST_ASSERT(g_rlog[0] == 'X', "X should start first");

    /* After X exhausts its budget, Y should run before X finishes. */
    TEST_ASSERT(g_rlog[1] == 'Y', "Y should run after X is preempted");

    /* Both processes must complete. */
    int x_count = 0, y_count = 0;
    for (int i = 0; i < 4; i++) {
        if (g_rlog[i] == 'X') x_count++;
        if (g_rlog[i] == 'Y') y_count++;
    }
    TEST_ASSERT(x_count == 2, "X should appear exactly twice (start + finish)");
    TEST_ASSERT(y_count == 2, "Y should appear exactly twice (start + finish)");
    TEST_PASS();
}

/* ── Test 4: nested_spawn ─────────────────────────────────────────────── */
/*
 * A "spawner" process spawns N child processes from inside its own body.
 * Verify all children and spawners run to completion.
 * 5 spawners × 10 leaves + 5 spawner increments = 55 total increments.
 */

static _Atomic int g_nested_count = 0;

static void nested_leaf(void *arg) {
    (void)arg;
    atomic_fetch_add_explicit(&g_nested_count, 1, memory_order_relaxed);
}

static void nested_spawner(void *arg) {
    int n = (int)(intptr_t)arg;
    for (int i = 0; i < n; i++) {
        march_sched_spawn(nested_leaf, NULL);
    }
    atomic_fetch_add_explicit(&g_nested_count, 1, memory_order_relaxed);
}

static void test_nested_spawn(void) {
    g_nested_count = 0;
    march_sched_init();
    for (int i = 0; i < 5; i++) {
        march_sched_spawn(nested_spawner, (void *)(intptr_t)10);
    }
    march_sched_run();

    /* 5 spawners × (1 self + 10 children) = 55 */
    TEST_ASSERT(g_nested_count == 55,
                "5 spawners × 10 children + 5 spawner self-increments = 55");
    /* total_spawned: 5 initial + 5*10 leaf = 55 */
    TEST_ASSERT(march_sched_total_spawned() == 55,
                "total_spawned should be 55 (5 spawners + 50 leaves)");
    TEST_PASS();
}

/* ── Entry point ──────────────────────────────────────────────────────── */

int main(void) {
    printf("=== March Green Thread Scheduler — Phase 1 Tests ===\n");
    test_spawn_1000();
    test_yield_interleaving();
    test_reduction_preemption();
    test_nested_spawn();
    printf("\nResults: %d passed, %d failed\n",
           g_tests_passed, g_tests_failed);
    return g_tests_failed > 0 ? 1 : 0;
}
