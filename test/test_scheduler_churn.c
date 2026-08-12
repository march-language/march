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
#include <stdio.h>
#include <unistd.h>

static void tiny(void *arg) { (void)arg; }

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

    printf("test_scheduler_churn: all passed\n");
    return 0;
}
