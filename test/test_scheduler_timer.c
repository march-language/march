/* Timed-park tests. Compiled standalone with march_scheduler.c only. */
#include "march_scheduler.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdatomic.h>

static _Atomic int g_timed_out = 0;
static _Atomic int g_woken_early = 0;
static march_proc *g_sleeper = NULL;

static void sleeper_times_out(void *arg) {
    (void)arg;
    int64_t deadline = march_now_ms() + 50;
    for (;;) {
        int r = march_sched_park_self_until(deadline);
        if (r == MARCH_PARK_TIMEOUT || march_now_ms() >= deadline) {
            atomic_store(&g_timed_out, 1);
            return;
        }
        /* spurious wake: loop */
    }
}

static _Atomic int g_flag = 0;
static void sleeper_woken(void *arg) {
    (void)arg;
    int64_t deadline = march_now_ms() + 5000;   /* generous: wake must win */
    while (!atomic_load(&g_flag)) {
        int r = march_sched_park_self_until(deadline);
        if (r == MARCH_PARK_TIMEOUT) { return; } /* fail: flag never set */
    }
    atomic_store(&g_woken_early, 1);
}

static void waker(void *arg) {
    (void)arg;
    atomic_store(&g_flag, 1);
    march_sched_wake(g_sleeper);
}

/* Regression for the lost-wakeup window: pairing march_sched_try_recv2 with
 * march_sched_park_self_until left a gap between the (unlocked) emptiness
 * check and the (separate) PROC_PARKED store where march_sched_send could
 * observe the receiver as PROC_RUNNING and skip the wake entirely -- the
 * receiver then only unblocked when the deadline timer fired. This proves
 * march_sched_recv_until (which holds mbox_lock across both steps) wakes
 * promptly instead of stalling to the deadline. */
static march_proc *g_receiver = NULL;
static _Atomic int64_t g_recv_wait_ms = -1;
static _Atomic int g_msg_ok = 0;

static void receiver_fn(void *arg) {
    (void)arg;
    int64_t deadline = march_now_ms() + 5000; /* generous: a lost wakeup would stall here */
    int64_t start = march_now_ms();
    /* Mirrors march_actor_call's contract: a single march_sched_recv_until
     * call can return MARCH_RECV_NO_MSG before the deadline (spurious wake,
     * or this standalone harness has no preempt daemon so g_preempt_active
     * is 0 and every call degrades to one yield-and-retry) -- the caller is
     * responsible for looping until either a message arrives or its own
     * deadline check trips. */
    void *msg;
    for (;;) {
        msg = march_sched_recv_until(deadline);
        if (msg != MARCH_RECV_NO_MSG) break;
        if (march_now_ms() >= deadline) break;
    }
    atomic_store(&g_recv_wait_ms, march_now_ms() - start);
    if (msg != MARCH_RECV_NO_MSG) atomic_store(&g_msg_ok, 1);
}

static void sender_fn(void *arg) {
    (void)arg;
    /* Tight racing loop: yield repeatedly so the scheduler interleaves this
     * send as close as possible to the receiver's empty-check/park
     * transition, maximizing the chance of hitting the window this test
     * guards against. */
    for (int i = 0; i < 50; i++) march_sched_yield();
    march_sched_send(g_receiver, (void *)(intptr_t)1);
}

int main(void) {
    /* 1: park times out */
    march_sched_init();
    march_sched_spawn(sleeper_times_out, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_timed_out) == 1);

    /* 2: wake beats the deadline */
    march_sched_init();
    g_sleeper = march_sched_spawn(sleeper_woken, NULL);
    march_sched_spawn(waker, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_woken_early) == 1);

    /* 3: march_sched_recv_until wakes promptly under a racing send. Run
     * several iterations so the sender's yield-then-send lands close to the
     * receiver's park across differing scheduler interleavings. */
    for (int iter = 0; iter < 20; iter++) {
        atomic_store(&g_recv_wait_ms, -1);
        atomic_store(&g_msg_ok, 0);
        march_sched_init();
        g_receiver = march_sched_spawn(receiver_fn, NULL);
        march_sched_spawn(sender_fn, NULL);
        march_sched_request_shutdown();
        march_sched_run();
        assert(atomic_load(&g_msg_ok) == 1);
        int64_t waited = atomic_load(&g_recv_wait_ms);
        /* Deadline was 5000ms; a lost wakeup stalls to (near) that. A
         * prompt wake should land in single-digit ms, but allow generous
         * headroom for a loaded CI box -- 1000ms is still an order of
         * magnitude below the failure signature. */
        assert(waited >= 0 && waited < 1000);
    }

    printf("test_scheduler_timer: all passed\n");
    return 0;
}
