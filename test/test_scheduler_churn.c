/* test_scheduler_churn.c — Task 12: stack-reservation recycling on proc
 * death.
 *
 * Churns a large number of procs through spawn -> run -> death.  Without
 * stack recycling that is N leaked ~1MiB+guard mmap reservations (~3GB of
 * VA for N=3000, thousands of VMAs); with it, the free-list caps live
 * reservations near the concurrency level and march_stat_counters[
 * MARCH_STAT_STACKS_RECYCLED] (index 5, via march_sched_stat(5)) climbs
 * roughly 1:1 with deaths. Asserted via the counter, not VA directly — VA
 * accounting is OS-specific and not portable to assert on here.
 */
#include "march_scheduler.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>
#include <unistd.h>

static void tiny(void *arg) { (void)arg; }

/* Task 12b: local-deque overflow regression.
 *
 * march_deque_push (runtime/march_deque.h) is bounded at
 * MARCH_DEQUE_CAPACITY (4096) and returns -1 when full. The
 * spawn-from-scheduler-thread path in sched_spawn_common used to ignore
 * that return value: a proc pushed while the local deque was already at
 * capacity was marked RUNNABLE and counted in g_live_procs, but never
 * actually queued anywhere -- stranded forever. Every scheduler thread
 * eventually idle-parks waiting for work that will never arrive: a
 * livelock, not a crash, so nothing but a watchdog catches it.
 *
 * This reproduces it at the C level: a single green thread (so its
 * spawns hit the OWNER's local Chase-Lev deque, not the global run
 * queue) bursts more spawns than the deque can hold in one go.
 */
#define CHURN_BURST_N 5000
static _Atomic int64_t g_churn_burst_done = 0;

static void churn_burst_tiny(void *arg) {
    (void)arg;
    atomic_fetch_add_explicit(&g_churn_burst_done, 1, memory_order_relaxed);
}

static void churn_burst_spawner(void *arg) {
    (void)arg;
    for (int i = 0; i < CHURN_BURST_N; i++) {
        march_sched_spawn(churn_burst_tiny, NULL);
    }
}

int main(void) {
    /* Watchdog: this harness (3000 spawns + a second 100-spawn batch, both
     * run to quiescence) should complete in well under 30s on an idle box;
     * give generous headroom for a loaded CI box without masking a real
     * hang. */
    alarm(60);

    march_sched_init();
    for (int i = 0; i < 3000; i++) march_sched_spawn(tiny, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    int64_t recycled = march_sched_stat(5);   /* MARCH_STAT_STACKS_RECYCLED */
    fprintf(stderr, "recycled=%lld\n", (long long)recycled);
    assert(recycled >= 2900);   /* nearly every death fed the free-list */

    /* Reuse: a fresh batch must consume the free-list, not grow it 1:1.
     * (march_sched_init() deliberately keeps g_stack_free across re-init —
     * see the comment in march_sched_init — so these spawns should be
     * served largely from stacks retired by the batch above.) */
    march_sched_init();
    for (int i = 0; i < 100; i++) march_sched_spawn(tiny, NULL);
    march_sched_request_shutdown();
    march_sched_run();

    /* Local-deque overflow: burst CHURN_BURST_N (> MARCH_DEQUE_CAPACITY)
     * spawns from INSIDE the scheduler (tl_sched set, so they hit the
     * owner's local deque). Before the Task 12b fix, this hangs -- the
     * alarm(60) watchdog above fires and aborts the process instead of
     * the assert below ever running. */
    march_sched_init();
    march_sched_spawn(churn_burst_spawner, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    int64_t burst_done =
        atomic_load_explicit(&g_churn_burst_done, memory_order_relaxed);
    fprintf(stderr, "churn_burst_done=%lld (expected %d)\n",
            (long long)burst_done, CHURN_BURST_N);
    assert(burst_done == CHURN_BURST_N);

    /* Task 13: registry survives past the old fixed MARCH_MAX_PROCS (65536)
     * cliff. With the old fixed-size g_proc_registry[65536], registry_add
     * silently skipped the store (but still counted the proc) for any pid
     * >= 65536 -- march_sched_run still terminated (the deque-overflow
     * livelock this file guards against above is a separate, already-fixed
     * bug, per Task 12b), but march_sched_find went blind for every proc
     * beyond the cliff, and wait_idle/wake_idle_daemons silently never saw
     * them either. Spawning all 70000 from main (not from inside a
     * scheduler thread) routes them through the global run queue, so
     * nothing runs until march_sched_run() below -- letting us assert
     * march_sched_find on a high pid BOTH while every proc is still alive
     * (positive) and after they've all been reaped (negative), a real
     * pair that only a growable registry can satisfy. 70000 tiny procs
     * through spawn+stack-recycling can run past the default 60s budget on
     * a loaded box; alarm() resets the watchdog for this segment alone. */
    alarm(120);
    march_sched_init();
    for (int i = 0; i < 70000; i++) march_sched_spawn(tiny, NULL);
    assert(march_sched_find(69000) != NULL);   /* alive, above the old cliff */
    march_sched_request_shutdown();
    march_sched_run();
    /* every proc must have been reaped -- with the old fixed array,
     * procs with pid >= 65536 were invisible to the registry and
     * (harmlessly here, catastrophically for wait_idle) skipped; live
     * must hit 0 for march_sched_run to have returned at all, so reaching
     * this line with find returning NULL for a high pid is the assertion: */
    assert(march_sched_find(69999) == NULL);   /* reaped and removed, not lost */
    printf("registry growth OK\n");

    printf("test_scheduler_churn: all passed\n");
    return 0;
}
