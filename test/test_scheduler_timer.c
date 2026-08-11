/* Timed-park tests. Compiled standalone with march_scheduler.c only. */
#include "march_scheduler.h"
#include <assert.h>
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

    printf("test_scheduler_timer: all passed\n");
    return 0;
}
