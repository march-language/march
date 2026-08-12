/* test_scheduler_mbox.c — bounded mailbox capacity + overflow policies.
 *
 * test_block_live_scheduler() (Task 8: MARCH_MBOX_BLOCK) runs FIRST, in its
 * own march_sched_init()/march_sched_run() pair, because it needs a real
 * scheduler actually draining the mailbox to unpark blocked senders.
 *
 * Every segment AFTER it is deterministic by construction: each spawns
 * daemon procs and sends to them WITHOUT ever running the scheduler
 * (march_sched_run is never called again), so nothing drains a mailbox out
 * from under an assertion and message ordering within a single
 * mbox_push/mbox_pop stream is exactly the FIFO the test relies on. They
 * start from a FRESH march_sched_init() so the live-scheduler segment above
 * cannot leave any state behind that would affect them. */

#include "march_scheduler.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>

static void nop(void *arg) { (void)arg; }

/* ── MARCH_MBOX_BLOCK: live-scheduler blocking scenario ─────────────────
 *
 * Unlike the deterministic segments below (never-run scheduler), this one
 * actually spins up the scheduler and drives it to quiescence, since the
 * whole point of MARCH_MBOX_BLOCK is senders parking on a real green
 * thread and being woken by a real receiver drain. Runs FIRST, in its own
 * march_sched_init()/march_sched_run() pair, so the deterministic segments
 * that follow can each start from a fresh scheduler exactly as before. */
#define N_MSGS 2000
static _Atomic int64_t g_received = 0, g_send_ok = 0;
static _Atomic int64_t g_peak_depth = 0;
static march_proc *g_bounded_rx = NULL;

static void rx_loop(void *arg) {
    (void)arg;
    for (int i = 0; i < N_MSGS; i++) {
        void *m = march_sched_recv();
        if (m == MARCH_RECV_NO_MSG) return;
        atomic_fetch_add(&g_received, 1);
    }
}

static void tx_loop(void *arg) {
    (void)arg;
    for (int i = 0; i < N_MSGS / 2; i++) {
        int64_t d = march_sched_mbox_count(g_bounded_rx);
        int64_t pk = atomic_load(&g_peak_depth);
        while (d > pk && !atomic_compare_exchange_weak(&g_peak_depth, &pk, d)) {}
        if (march_sched_send(g_bounded_rx, (void *)0x1) == MARCH_SEND_OK)
            atomic_fetch_add(&g_send_ok, 1);
    }
}

static void test_block_live_scheduler(void) {
    march_sched_init();
    g_bounded_rx = march_sched_spawn(rx_loop, NULL);
    march_sched_set_mbox_limit(g_bounded_rx, 16, MARCH_MBOX_BLOCK);
    march_sched_spawn(tx_loop, NULL);
    march_sched_spawn(tx_loop, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_send_ok) == N_MSGS);       /* nothing dropped */
    assert(atomic_load(&g_received) == N_MSGS);       /* everything arrived */
    assert(atomic_load(&g_peak_depth) <= 16 + 2);     /* bound held (small racy slack) */
}

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
    test_block_live_scheduler();

    march_sched_init();

    test_unbounded_default();
    test_drop_new();
    test_drop_old();
    test_dead_target_unaffected();

    printf("test_scheduler_mbox: all passed\n");
    return 0;
}
