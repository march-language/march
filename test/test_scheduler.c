/* test_scheduler.c — Tests for the Phase 1+2 green-thread scheduler.
 *
 * Tests
 * ─────
 *  Phase 1
 *  1. test_spawn_1000      — Spawn 1000 processes, each increments a counter.
 *                            Verify counter == 1000 after march_sched_run().
 *  2. test_yield_interleaving — Two processes log 'A'/'B' around explicit
 *                            yield calls; verify round-robin ordering.
 *  3. test_reduction_preemption — Processes burn their reduction budget via
 *                            march_sched_tick(); verify automatic preemption
 *                            interleaves them correctly.
 *  4. test_nested_spawn    — A process spawns child processes from inside its
 *                            own function body; verify all children run.
 *
 *  Phase 2 (message passing)
 *  5. test_send_recv_basic    — Sender sends one message; receiver gets it.
 *  6. test_send_recv_multiple — Sender sends 100 messages; receiver loops recv.
 *  7. test_waiting_wakeup     — Receiver blocks on recv; sender wakes it up.
 *  8. test_try_recv           — try_recv returns NULL when empty, msg when ready.
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

/* ── Test 5: send_recv_basic ──────────────────────────────────────────── */
/*
 * Two processes: sender sends a message to receiver.  Receiver calls
 * march_sched_recv(), gets the message, increments a counter.
 */

static _Atomic int g_recv_count = 0;
static march_proc *g_receiver = NULL;

static void recv_worker(void *arg) {
    (void)arg;
    void *msg = march_sched_recv();
    if (msg != NULL) {
        atomic_fetch_add_explicit(&g_recv_count, 1, memory_order_relaxed);
    }
}

static void send_worker(void *arg) {
    (void)arg;
    march_sched_yield();
    int payload = 42;
    march_sched_send(g_receiver, (void *)(intptr_t)payload);
}

static void test_send_recv_basic(void) {
    g_recv_count = 0;
    march_sched_init();
    g_receiver = march_sched_spawn(recv_worker, NULL);
    march_sched_spawn(send_worker, NULL);
    march_sched_run();

    TEST_ASSERT(g_recv_count == 1, "receiver should have gotten exactly 1 message");
    TEST_PASS();
}

/* ── Test 6: send_recv_multiple ──────────────────────────────────────── */
/*
 * One sender sends 100 messages to one receiver.
 * Receiver loops recv() 100 times.
 */

static _Atomic int g_multi_recv = 0;
static march_proc *g_multi_receiver = NULL;

static void multi_recv_worker(void *arg) {
    int expected = (int)(intptr_t)arg;
    for (int i = 0; i < expected; i++) {
        void *msg = march_sched_recv();
        if (msg) atomic_fetch_add_explicit(&g_multi_recv, 1, memory_order_relaxed);
    }
}

static void multi_send_worker(void *arg) {
    int count = (int)(intptr_t)arg;
    for (int i = 0; i < count; i++) {
        march_sched_send(g_multi_receiver, (void *)(intptr_t)(i + 1));
        march_sched_yield();
    }
}

static void test_send_recv_multiple(void) {
    g_multi_recv = 0;
    march_sched_init();
    g_multi_receiver = march_sched_spawn(multi_recv_worker, (void *)(intptr_t)100);
    march_sched_spawn(multi_send_worker, (void *)(intptr_t)100);
    march_sched_run();

    TEST_ASSERT(g_multi_recv == 100, "receiver should have gotten 100 messages");
    TEST_PASS();
}

/* ── Test 7: waiting_wakeup ───────────────────────────────────────────── */
/*
 * Process A blocks on recv().  Process B yields a few times, then sends.
 * Verify A resumes after the send.
 */

static char  g_wlog[16];
static int   g_wpos = 0;

static void waiting_a(void *arg) {
    (void)arg;
    g_wlog[g_wpos++] = 'A';
    march_sched_recv();
    g_wlog[g_wpos++] = 'A';
}

static void waiting_b(void *arg) {
    march_proc *target = (march_proc *)arg;
    g_wlog[g_wpos++] = 'B';
    march_sched_yield();
    g_wlog[g_wpos++] = 'B';
    march_sched_send(target, (void *)(intptr_t)1);
}

static void test_waiting_wakeup(void) {
    g_wpos = 0;
    memset(g_wlog, 0, sizeof(g_wlog));
    march_sched_init();
    march_proc *a = march_sched_spawn(waiting_a, NULL);
    march_sched_spawn(waiting_b, (void *)a);
    march_sched_run();

    TEST_ASSERT(g_wpos == 4, "should have 4 log entries");
    TEST_ASSERT(g_wlog[0] == 'A', "A starts first");
    TEST_ASSERT(g_wlog[1] == 'B', "B runs after A blocks");
    int a_count = 0, b_count = 0;
    for (int i = 0; i < 4; i++) {
        if (g_wlog[i] == 'A') a_count++;
        if (g_wlog[i] == 'B') b_count++;
    }
    TEST_ASSERT(a_count == 2, "A appears twice (start + resume)");
    TEST_ASSERT(b_count == 2, "B appears twice");
    TEST_PASS();
}

/* ── Test 8: try_recv ─────────────────────────────────────────────────── */
/*
 * Verify try_recv returns NULL when the mailbox is empty, and returns
 * the message once one has been sent.
 */

static int g_try_recv_null = 0;
static int g_try_recv_got  = 0;

static void try_recv_worker(void *arg) {
    (void)arg;
    void *msg = march_sched_try_recv();
    if (msg == NULL) g_try_recv_null = 1;
    march_sched_yield();
    msg = march_sched_try_recv();
    if (msg != NULL) g_try_recv_got = 1;
}

static void try_recv_sender(void *arg) {
    march_proc *target = (march_proc *)arg;
    march_sched_send(target, (void *)(intptr_t)99);
}

static void test_try_recv(void) {
    g_try_recv_null = 0;
    g_try_recv_got  = 0;
    march_sched_init();
    march_proc *r = march_sched_spawn(try_recv_worker, NULL);
    march_sched_spawn(try_recv_sender, (void *)r);
    march_sched_run();

    TEST_ASSERT(g_try_recv_null == 1, "try_recv should return NULL when empty");
    TEST_ASSERT(g_try_recv_got == 1,  "try_recv should return msg when available");
    TEST_PASS();
}

/* ── Phase 4: Stack growth tests ─────────────────────────────────────── */
/*
 * 9.  test_stack_growth_deep   — One process recurses deeply enough to
 *                                exhaust the initial 4 KiB stack.  Growth
 *                                via guard-page fault keeps it alive.
 * 10. test_stack_growth_many   — 50 processes each do deep recursion
 *                                concurrently; all must complete.
 */

static _Atomic int g_growth_done = 0;

/* Each call allocates ~512 bytes of stack (volatile prevents elision). */
static void deep_recurse(int depth) {
    volatile char buf[512];
    buf[0]   = (char)depth;
    buf[511] = (char)(depth ^ 0xAA);
    if (depth > 0) deep_recurse(depth - 1);
    /* Use the values to prevent the compiler from optimising away the frame. */
    (void)(buf[0] + buf[511]);
}

static void growth_worker(void *arg) {
    int depth = (int)(intptr_t)arg;
    deep_recurse(depth);   /* triggers lazy stack growth */
    atomic_fetch_add_explicit(&g_growth_done, 1, memory_order_relaxed);
}

static void test_stack_growth_deep(void) {
    g_growth_done = 0;
    march_sched_init();
    /* ~512 bytes × 20 frames ≈ 10 KiB > MARCH_STACK_INITIAL (4 KiB).
     * Forces at least two guard-page faults and growths. */
    march_sched_spawn(growth_worker, (void *)(intptr_t)20);
    march_sched_run();

    TEST_ASSERT(g_growth_done == 1,
                "deep-recursion process should complete after stack growth");
    TEST_PASS();
}

static void test_stack_growth_many(void) {
    g_growth_done = 0;
    march_sched_init();
    /* Spawn 50 processes each using ~10 KiB of stack depth. */
    for (int i = 0; i < 50; i++) {
        march_sched_spawn(growth_worker, (void *)(intptr_t)20);
    }
    march_sched_run();

    TEST_ASSERT(g_growth_done == 50,
                "all 50 deep-recursion processes should complete");
    TEST_PASS();
}

/* ── Entry point ──────────────────────────────────────────────────────── */

int main(void) {
    printf("=== March Green Thread Scheduler — Phase 1+2+4 Tests ===\n");
    test_spawn_1000();
    test_yield_interleaving();
    test_reduction_preemption();
    test_nested_spawn();
    test_send_recv_basic();
    test_send_recv_multiple();
    test_waiting_wakeup();
    test_try_recv();
    printf("\n--- Phase 4: stack growth ---\n");
    test_stack_growth_deep();
    test_stack_growth_many();
    printf("\nResults: %d passed, %d failed\n",
           g_tests_passed, g_tests_failed);
    return g_tests_failed > 0 ? 1 : 0;
}
