/* test_scheduler_mt.c — Phase 3 multi-threaded scheduler tests.
 *
 * These tests run with the default MARCH_NUM_SCHEDULERS=4 (multi-threaded)
 * to exercise work-stealing and cross-scheduler message passing.
 *
 * Tests
 * ─────
 *  Phase 3 (multi-threaded)
 *  1. test_multithread_spawn_10000 — Spawn 10,000 processes across multiple
 *                                    schedulers, each increments an atomic
 *                                    counter. Verify all complete.
 *  2. test_multithread_send_recv   — 50 sender processes send 10 messages each
 *                                    to one receiver; verify all 500 arrive.
 *  3. test_work_stealing           — Spawn 200 busy processes; all should
 *                                    complete even when distributed across
 *                                    schedulers via work-stealing.
 */

#ifndef _XOPEN_SOURCE
#  define _XOPEN_SOURCE 700
#endif
#include "../runtime/march_scheduler.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdatomic.h>
#include <stdint.h>

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

/* ── Test 1: test_multithread_spawn_10000 ─────────────────────────────── */
/*
 * Spawn 10,000 processes across multiple schedulers, each increments an
 * atomic counter. Verify all complete.
 */

static _Atomic int g_mt_counter = 0;

static void mt_worker(void *arg) {
    (void)arg;
    atomic_fetch_add_explicit(&g_mt_counter, 1, memory_order_relaxed);
}

static void test_multithread_spawn_10000(void) {
    g_mt_counter = 0;
    march_sched_init();
    for (int i = 0; i < 10000; i++) {
        march_proc *p = march_sched_spawn(mt_worker, NULL);
        TEST_ASSERT(p != NULL, "spawn should succeed");
    }
    march_sched_run();
    TEST_ASSERT(g_mt_counter == 10000, "all 10000 processes should complete");
    TEST_PASS();
}

/* ── Test 2: test_multithread_send_recv ───────────────────────────────── */
/*
 * Multiple sender processes send to one receiver across threads.
 * 50 senders × 10 messages each = 500 total messages.
 */

static _Atomic int g_mt_recv_count = 0;
static march_proc *g_mt_receiver = NULL;

static void mt_recv_loop(void *arg) {
    int expected = (int)(intptr_t)arg;
    for (int i = 0; i < expected; i++) {
        void *msg = march_sched_recv();
        if (msg) atomic_fetch_add_explicit(&g_mt_recv_count, 1, memory_order_relaxed);
    }
}

static void mt_sender(void *arg) {
    (void)arg;
    for (int i = 0; i < 10; i++) {
        march_sched_send(g_mt_receiver, (void *)(intptr_t)(i + 1));
        march_sched_yield();
    }
}

static void test_multithread_send_recv(void) {
    g_mt_recv_count = 0;
    march_sched_init();
    g_mt_receiver = march_sched_spawn(mt_recv_loop, (void *)(intptr_t)500);
    for (int i = 0; i < 50; i++) {
        march_sched_spawn(mt_sender, NULL);
    }
    march_sched_run();
    TEST_ASSERT(g_mt_recv_count == 500, "receiver should get all 500 messages");
    TEST_PASS();
}

/* ── Test 3: test_work_stealing ───────────────────────────────────────── */
/*
 * Spawn 200 processes that do busy work (ticking reductions). All should
 * complete even though they're distributed across schedulers via stealing.
 */

static _Atomic int g_steal_counter = 0;

static void steal_worker(void *arg) {
    (void)arg;
    for (int i = 0; i < 1000; i++) {
        march_sched_tick();
    }
    atomic_fetch_add_explicit(&g_steal_counter, 1, memory_order_relaxed);
}

static void test_work_stealing(void) {
    g_steal_counter = 0;
    march_sched_init();
    for (int i = 0; i < 200; i++) {
        march_sched_spawn(steal_worker, NULL);
    }
    march_sched_run();
    TEST_ASSERT(g_steal_counter == 200, "all 200 processes should complete via stealing");
    TEST_PASS();
}

/* ── Entry point ──────────────────────────────────────────────────────── */

int main(void) {
    printf("=== March Green Thread Scheduler — Phase 3 Multi-Thread Tests ===\n");
    test_multithread_spawn_10000();
    test_multithread_send_recv();
    test_work_stealing();
    printf("\nResults: %d passed, %d failed\n",
           g_tests_passed, g_tests_failed);
    return g_tests_failed > 0 ? 1 : 0;
}
