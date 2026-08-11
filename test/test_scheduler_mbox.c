/* test_scheduler_mbox.c — bounded mailbox capacity + overflow policies.
 *
 * Deterministic by construction: every segment spawns daemon procs and sends
 * to them WITHOUT ever running the scheduler (march_sched_run is never
 * called), so nothing drains a mailbox out from under an assertion and
 * message ordering within a single mbox_push/mbox_pop stream is exactly the
 * FIFO the test relies on.
 *
 * Segments are split into their own functions, each independently
 * assert-clean, so a future live-scheduler segment (Task 8: MARCH_MBOX_BLOCK
 * parks the sender until the scheduler drains the mailbox) can be PREPENDED
 * to main() without disturbing these deterministic ones. */

#include "march_scheduler.h"
#include <assert.h>
#include <stdio.h>

static void nop(void *arg) { (void)arg; }

/* Default mailbox (mbox_limit == 0, MARCH_MBOX_UNBOUNDED) never rejects. */
static void test_unbounded_default(void) {
    march_proc *u = march_sched_spawn_daemon(nop, NULL);
    for (int i = 0; i < 100; i++)
        assert(march_sched_send(u, (void *)0x1) == MARCH_SEND_OK);
    assert(march_sched_mbox_count(u) == 100);
}

/* MARCH_MBOX_DROP_NEW: once the mailbox is at capacity, further sends are
 * rejected outright (MARCH_SEND_DROPPED) and the mailbox depth never grows
 * past the limit. */
static void test_drop_new(void) {
    march_proc *dn = march_sched_spawn_daemon(nop, NULL);
    march_sched_set_mbox_limit(dn, 3, MARCH_MBOX_DROP_NEW);
    assert(march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK);
    assert(march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK);
    assert(march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK);
    assert(march_sched_send(dn, (void *)0x1) == MARCH_SEND_DROPPED);
    assert(march_sched_mbox_count(dn) == 3);
}

/* MARCH_MBOX_DROP_OLD: once the mailbox is at capacity, a new send evicts
 * the oldest queued message (FIFO head) instead of being rejected, so the
 * send itself still reports MARCH_SEND_OK and the mailbox depth stays
 * pinned at the limit.
 *
 * mbox_pop is `static` to march_scheduler.c, so the test has no way to pop
 * under its own control and inspect which payload survived — the only
 * externally observable facts are the mailbox depth (stays at the limit)
 * and the MSGS_DROPPED stat counter (bumped once per eviction). We read the
 * counter BEFORE this segment and assert the DELTA, not an absolute value,
 * because earlier segments/tests in the same process may already have
 * bumped it (and, run standalone, it starts at 0 only by convention of test
 * order — the delta is the only assertion immune to that). */
static void test_drop_old(void) {
    int64_t dropped_before = march_sched_stat(MARCH_STAT_MSGS_DROPPED);

    march_proc *dold = march_sched_spawn_daemon(nop, NULL);
    march_sched_set_mbox_limit(dold, 2, MARCH_MBOX_DROP_OLD);
    assert(march_sched_send(dold, (void *)0x3) == MARCH_SEND_OK);  /* tagged imm 1 */
    assert(march_sched_send(dold, (void *)0x5) == MARCH_SEND_OK);  /* tagged imm 2 */
    assert(march_sched_send(dold, (void *)0x7) == MARCH_SEND_OK);  /* evicts 0x3 */
    assert(march_sched_mbox_count(dold) == 2);

    int64_t dropped_after = march_sched_stat(MARCH_STAT_MSGS_DROPPED);
    assert(dropped_after - dropped_before == 1);
}

/* march_sched_send on a NULL/DEAD target is unaffected by any of the above:
 * still MARCH_SEND_DEAD, checked before the mbox_limit path is ever reached. */
static void test_dead_target_unaffected(void) {
    assert(march_sched_send(NULL, (void *)0x1) == MARCH_SEND_DEAD);
}

int main(void) {
    march_sched_init();

    test_unbounded_default();
    test_drop_new();
    test_drop_old();
    test_dead_target_unaffected();

    printf("test_scheduler_mbox: all passed\n");
    return 0;
}
