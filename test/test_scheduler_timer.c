/* Timed-park tests. Compiled standalone with march_scheduler.c only. */
#include "march_scheduler.h"
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdatomic.h>
#include <unistd.h>

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

/* Task 16 fix-up (Important 1, ghost-timer regression): a proc that parks
 * with march_sched_recv_until(deadline) and then wakes EARLY (message
 * arrives well before the deadline) used to leave a stale timer-heap entry
 * behind for its full original deadline — the heap has no cancellation by
 * design. march_sched_wait_idle()'s old busy-check was a bare
 * `g_timer_len > 0`, so it would block for the ENTIRE remaining ~5000ms of
 * that already-satisfied wait even though nothing else in the process was
 * doing anything. The park_gen fix makes such an entry recognizably a
 * ghost (its `gen` no longer matches the proc's current park_gen) the
 * instant the park call returns, for ANY reason.
 *
 * This reproduces exactly that shape: ghost_receiver_fn parks on a 5000ms
 * recv_until, is woken almost immediately by ghost_sender_fn, and exits —
 * leaving its now-stale entry in the heap. ghost_waiter_fn then calls
 * march_sched_wait_idle() directly and times it. Pre-fix this would take
 * ~5000ms (bounded below by the remaining time to the ghost's original
 * deadline); post-fix it returns in low single-digit ms once the receiver
 * and sender have both exited. */
static _Atomic int64_t g_ghost_wait_ms = -1;
static march_proc     *g_ghost_receiver = NULL;

static void ghost_receiver_fn(void *arg) {
    (void)arg;
    int64_t deadline = march_now_ms() + 5000;
    for (;;) {
        void *msg = march_sched_recv_until(deadline);
        if (msg != MARCH_RECV_NO_MSG) return;      /* got it — exit, leaving a ghost */
        if (march_now_ms() >= deadline) return;    /* genuinely timed out */
    }
}

static void ghost_sender_fn(void *arg) {
    (void)arg;
    /* Yield a handful of times so the receiver is definitely parked before
     * the message lands, then wake it almost immediately relative to its
     * 5000ms deadline. */
    for (int i = 0; i < 20; i++) march_sched_yield();
    march_sched_send(g_ghost_receiver, (void *)(intptr_t)1);
}

static void ghost_waiter_fn(void *arg) {
    (void)arg;
    /* Give the receiver+sender a chance to run to completion (both exit)
     * before measuring wait_idle, so the only thing left in the process is
     * the receiver's stale timer-heap entry. */
    for (int i = 0; i < 40; i++) march_sched_yield();
    int64_t start = march_now_ms();
    march_sched_wait_idle();
    atomic_store(&g_ghost_wait_ms, march_now_ms() - start);
}

int main(void) {
    /* Watchdog: converts a reintroduced lost-wakeup hang into SIGALRM ->
     * nonzero exit (a normal test FAILURE) instead of wedging the caller
     * forever. See test_scheduler_mbox.c's identical guard for the full
     * rationale; 30s is generous headroom over this file's actual
     * sub-second runtime. */
    alarm(30);

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

    /* 4: mbox_count is accurate without running the scheduler (deterministic:
     * the proc is spawned but never dispatched, so nothing drains). */
    march_sched_init();
    march_proc *idle = march_sched_spawn_daemon(sleeper_times_out, NULL);
    for (int i = 0; i < 5; i++) march_sched_send(idle, (void *)0x1);
    assert(march_sched_mbox_count(idle) == 5);

    /* 5: ghost timer entries must not block march_sched_wait_idle(). See the
     * comment above ghost_receiver_fn for the full scenario. */
    march_sched_init();
    g_ghost_receiver = march_sched_spawn(ghost_receiver_fn, NULL);
    march_sched_spawn(ghost_sender_fn, NULL);
    march_sched_spawn(ghost_waiter_fn, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    int64_t ghost_wait = atomic_load(&g_ghost_wait_ms);
    assert(ghost_wait >= 0 && ghost_wait < 1000);

    printf("test_scheduler_timer: all passed\n");
    return 0;
}
