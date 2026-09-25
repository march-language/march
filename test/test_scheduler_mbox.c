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
#include <stdlib.h>
#include <unistd.h>

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

/* ── MARCH_MBOX_BLOCK: spurious-wake-while-linked regime ─────────────────
 *
 * Task 8 code review (Critical 1) caught a deterministic corruption: a
 * sender parked and genuinely linked in target->mbox_send_waiters, if
 * woken for ANY reason other than that target's own drain -- e.g. another
 * sender targeting IT directly -- and then found the target still full on
 * retry, would re-register on top of its own still-present entry,
 * corrupting the waiter chain (self-loop or an orphaned tail) on the very
 * first such spurious wake. mbox_block_register_and_park now
 * unconditionally deregisters self after every park_self return, before
 * any retry. This segment exercises exactly that regime: two senders
 * (txA, txB) block repeatedly on a tightly-limited receiver (rxC) while a
 * third proc (prodder) independently and continuously sends directly to
 * txA's own (unbounded, default-policy) mailbox -- each such send wakes
 * txA if it is currently PARKED/WAITING, regardless of what it's parked
 * for, which is precisely a wake "for a reason other than the drain it's
 * actually waiting on" while it may still be linked in rxC's waiter list.
 * txA never has to actually receive the prodded messages for this to
 * matter -- the wake is what exercises the regime, not the payload. */
#define N_MSGS2 400
static _Atomic int64_t g_received2 = 0, g_send_ok2 = 0;
static march_proc *g_bounded_rxC = NULL;

static void rx_loop2(void *arg) {
    (void)arg;
    for (int i = 0; i < N_MSGS2; i++) {
        void *m = march_sched_recv();
        if (m == MARCH_RECV_NO_MSG) return;
        atomic_fetch_add(&g_received2, 1);
    }
}

static void tx_loop2(void *arg) {
    (void)arg;
    for (int i = 0; i < N_MSGS2 / 2; i++) {
        if (march_sched_send(g_bounded_rxC, (void *)0x1) == MARCH_SEND_OK)
            atomic_fetch_add(&g_send_ok2, 1);
    }
}

/* Bounded iteration count (not an external stop flag): a proc that loops
 * forever waiting on a flag set AFTER march_sched_run() returns would
 * itself prevent the scheduler from ever reaching quiescence (it is a
 * non-daemon proc; shutdown waits for every non-daemon proc to finish) --
 * a self-deadlock in the TEST, not the runtime under test. Looping a
 * fixed number of times instead lets this proc finish on its own,
 * alongside txA/txB/rxC, once its work is done. */
#define PRODDER_ITERS 3000
/* txA finishes its sends and DIES while the prodder is still prodding it, and
 * a dead proc is retired to march_reclaim and FREED after a grace period.  So
 * the prodder must not hold txA's `march_proc *` across its yields: it keeps
 * the pid and resolves it afresh each turn (a green thread is inside a
 * critical section between two dispatches, so the pointer is good until the
 * yield).  It used to send through the raw g_txA pointer, which after txA's
 * reclaim was a use-after-free (Guard Malloc faults on it every run, in
 * march_sched_send reading target->pid) that goes on to WRITE the freed
 * block: mbox_lock, mailbox links, counters.  On macOS a calloc that reuses
 * such a block returns it with those writes still in it (it relies on the
 * zeroing done at free), so the garbage resurfaced as the "fresh" state of a
 * LATER proc: locally, test_spurious_wake_does_not_end_recv's receiver
 * getting NO_MSG, and sched_loop's reap walking a mbox_send_waiters list whose
 * head was 0x2 (this prodder's payload) and faulting at 0xa2; on macOS CI,
 * most likely, test_drop_new's brand-new daemon failing its first send.  See
 * specs/progress/2026-09-25-flake-scheduler-mbox-drop-new-daemon-exits.md. */
static int64_t g_txA_pid = -1;
static void prodder_loop(void *arg) {
    (void)arg;
    for (int i = 0; i < PRODDER_ITERS; i++) {
        march_proc *txA = march_sched_find(g_txA_pid);  /* NULL once reaped */
        if (txA)
            march_sched_send(txA, (void *)0x2);   /* result ignored; txA never drains these */
        march_sched_yield();
    }
}

static void test_block_spurious_wake_while_linked(void) {
    march_sched_init();
    g_bounded_rxC = march_sched_spawn(rx_loop2, NULL);
    march_sched_set_mbox_limit(g_bounded_rxC, 4, MARCH_MBOX_BLOCK);  /* tight: heavy contention */
    g_txA_pid = march_sched_spawn(tx_loop2, NULL)->pid;   /* txA */
    march_sched_spawn(tx_loop2, NULL);          /* txB */
    march_sched_spawn(prodder_loop, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_send_ok2) == N_MSGS2);   /* full delivery: nothing dropped */
    assert(atomic_load(&g_received2) == N_MSGS2);  /* full delivery: everything arrived */
    /* Reaching here at all (rather than the alarm(30) watchdog firing) is
     * itself the termination assertion for the corrupted-chain lost-wakeup
     * this regression guards against. */
}

/* ── A wake with an empty mailbox must NOT end a blocking receive ────────
 *
 * march_sched_send pushes under mbox_lock but wakes AFTER releasing it, so
 * two senders racing one receiver routinely issue two wakes for messages the
 * receiver drains as a single batch. The second wake then lands after the
 * receiver has already re-parked, resuming it with a legitimately empty
 * mailbox. That is benign and must be treated as spurious: the receiver has
 * to park again, NOT report MARCH_RECV_NO_MSG.
 *
 * It used to report NO_MSG, which actor_green_thread (march_runtime.c) reads
 * as "I was killed" — it broke its dispatch loop and ran do_actor_death on an
 * actor whose $alive word was still 1, so a later Actor.call on that pid
 * failed with "actor not alive". Live-fire repro was
 * bench/actors/fanin_flood.march at ~4% of runs; this is its deterministic
 * form. NO_MSG is now reserved for a real stop request (see
 * march_proc.stop_requested / march_sched_request_stop).
 *
 * Deterministic by construction, no race needed: the prodder spins until it
 * OBSERVES the receiver in PROC_WAITING before issuing a bare wake (no
 * message pushed at all), so the wake is guaranteed to hit a genuinely parked
 * receiver with an empty mailbox — exactly the state the send/consume race
 * produces, reached without needing to win that race.
 *
 * Both spin loops also break on PROC_DEAD, so the PRE-FIX binary fails fast
 * on the assertion instead of grinding through the full bound: pre-fix the
 * receiver returns NO_MSG on the bare wake and its proc dies, so it never
 * returns to PROC_WAITING and g_sw_got_nomsg is set. */
static _Atomic int g_sw_got_nomsg = 0;
static _Atomic int g_sw_got_real  = 0;
static _Atomic int g_sw_reparked  = 0;
/* The receiver by pid, resolved afresh each time (never held across a yield):
 * if a regression kills it, it is reaped and freed, and a stale pointer would
 * turn a clean assertion failure into a use-after-free (see prodder_loop). */
static int64_t g_sw_rx_pid = -1;

static void sw_rx_loop(void *arg) {
    (void)arg;
    void *m = march_sched_recv();
    if (m == MARCH_RECV_NO_MSG) atomic_store(&g_sw_got_nomsg, 1);
    else                        atomic_store(&g_sw_got_real, 1);
}

/* Spin (yielding, so the receiver actually gets turns even if this lands on
 * its scheduler thread) until rx reaches PROC_WAITING. Returns 1 if it did. */
static int sw_wait_until_parked(void) {
    for (int i = 0; i < 200000; i++) {
        march_proc *rx = march_sched_find(g_sw_rx_pid);
        if (!rx) return 0;                  /* reaped: it died */
        march_proc_status st = atomic_load_explicit(&rx->status,
                                                    memory_order_acquire);
        if (st == PROC_WAITING) return 1;
        if (st == PROC_DEAD)    return 0;   /* pre-fix: it died on the wake */
        march_sched_yield();
    }
    return 0;
}

static void sw_prodder_loop(void *arg) {
    (void)arg;
    if (!sw_wait_until_parked()) return;
    /* The bare spurious wake: deliberately NO march_sched_send, so the
     * mailbox is empty when the receiver resumes. */
    march_proc *rx = march_sched_find(g_sw_rx_pid);
    if (!rx) return;
    march_sched_wake(rx);
    /* It must come back to WAITING under its own steam (i.e. it re-parked
     * rather than reporting NO_MSG and exiting). */
    if (sw_wait_until_parked()) atomic_store(&g_sw_reparked, 1);
    /* Now a real delivery, to prove the receiver is still functional and the
     * re-park did not cost us the message. */
    rx = march_sched_find(g_sw_rx_pid);
    if (rx) march_sched_send(rx, (void *)0x2);
}

static void test_spurious_wake_does_not_end_recv(void) {
    march_sched_init();
    g_sw_rx_pid = march_sched_spawn(sw_rx_loop, NULL)->pid;
    march_sched_spawn(sw_prodder_loop, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_sw_got_nomsg) == 0);  /* the wake was not fatal   */
    assert(atomic_load(&g_sw_reparked)  == 1);  /* it genuinely re-parked   */
    assert(atomic_load(&g_sw_got_real)  == 1);  /* and still got the message*/
}

/* ── Reserved control FIFO: policy isolation + dispatch isolation ──────
 *
 * A control value must survive DROP_OLD user traffic and actor dispatch's
 * user-only receive must leave it queued for an explicit general receive.
 * Queue all three values before the scheduler starts so ordering is exact:
 * the second user send evicts only the first user value, then recv_user gets
 * the survivor while recv gets the untouched control value. */
static void *g_control_first = NULL, *g_user_first = NULL;

static void control_rx(void *arg) {
    (void)arg;
    g_user_first = march_sched_recv_user();
    g_control_first = march_sched_recv();
}

static void test_control_fifo_bypasses_user_policy(void) {
    march_sched_init();
    march_proc *rx = march_sched_spawn(control_rx, NULL);
    march_sched_set_mbox_limit(rx, 1, MARCH_MBOX_DROP_OLD);

    assert(march_sched_send_control(rx, (void *)0x11) == MARCH_SEND_OK);
    assert(march_sched_send(rx, (void *)0x21) == MARCH_SEND_OK);
    assert(march_sched_send(rx, (void *)0x31) == MARCH_SEND_OK);
    assert(march_sched_mbox_count(rx) == 2);

    march_sched_request_shutdown();
    march_sched_run();
    assert(g_user_first == (void *)0x31);
    assert(g_control_first == (void *)0x11);
}

/* Generic receive must preserve the single enqueue order across user and
 * control planes.  Actor dispatch remains user-only; only general receive
 * merges the two FIFO heads by their enqueue sequence. */
static void *g_cross_plane[3] = {NULL, NULL, NULL};

static void cross_plane_rx(void *arg) {
    (void)arg;
    for (int i = 0; i < 3; i++) g_cross_plane[i] = march_sched_recv();
}

static void test_cross_plane_global_fifo(void) {
    march_sched_init();
    march_proc *rx = march_sched_spawn(cross_plane_rx, NULL);
    assert(march_sched_send(rx, (void *)0x21) == MARCH_SEND_OK);
    assert(march_sched_send_control(rx, (void *)0x11) == MARCH_SEND_OK);
    assert(march_sched_send(rx, (void *)0x31) == MARCH_SEND_OK);

    march_sched_request_shutdown();
    march_sched_run();
    assert(g_cross_plane[0] == (void *)0x21);
    assert(g_cross_plane[1] == (void *)0x11);
    assert(g_cross_plane[2] == (void *)0x31);
}

/* ── Task 14: dead-actor mailbox drain ────────────────────────────────
 *
 * Runs march_sched_run() to actual completion (its own init/run pair, like
 * the live-scheduler segments above), because it needs sched_loop itself to
 * observe and reap this proc's death -- unlike the deterministic
 * never-run segments below, which never call march_sched_run() at all.
 *
 * Determinism argument (verified against the actual PROC_DEAD reap branch
 * in march_scheduler.c's sched_loop): all 7 sends happen BEFORE
 * march_sched_run() is ever called, while `victim` is
 * RUNNABLE-but-never-dispatched -- so every send lands in the mailbox via
 * the ordinary mbox_push_node path (target is neither DEAD nor at its
 * (unbounded, default) mbox_limit), with no race against the proc's death.
 * Once march_sched_run() starts, sched_loop dispatches `victim` for the
 * first time; die_immediately() returns immediately without ever calling
 * march_sched_recv(), so the actor itself never drains any of the 7
 * messages -- the proc transitions straight from RUNNING to PROC_DEAD with
 * all 7 still queued. sched_loop's PROC_DEAD branch then reaps it
 * synchronously on the same scheduler-thread call that dispatched it: wake
 * any mbox_send_waiters (none registered here -- nothing blocked on this
 * mailbox), collect every queued message under the lock, release the lock,
 * and dispose each one via the registered dtor (this test's
 * counting_dtor) -- see march_scheduler.c's PROC_DEAD branch. That reap
 * happens before march_sched_run() can return (shutdown was requested and
 * `victim` was the only non-daemon proc), so g_disposed is fully counted
 * by the time we get past march_sched_run() here. */
static _Atomic int g_disposed = 0;
static void counting_dtor(void *msg) { (void)msg; atomic_fetch_add(&g_disposed, 1); }
static void die_immediately(void *arg) { (void)arg; }

static void test_dead_reap_drain(void) {
    march_sched_init();
    march_sched_set_msg_dtor(counting_dtor);
    march_proc *victim = march_sched_spawn(die_immediately, NULL);
    for (int i = 0; i < 7; i++) march_sched_send(victim, (void *)0x1);
    march_sched_request_shutdown();
    march_sched_run();
    assert(atomic_load(&g_disposed) >= 7);
    march_sched_set_msg_dtor(NULL);  /* don't leak into the segments below */
}

/* ── Deterministic segments: checks that say WHY ─────────────────────────
 *
 * CI once failed test_drop_new's FIRST send (macos-15, run 36041334583):
 * `Assertion failed: (march_sched_send(dn, (void *)0x1) == MARCH_SEND_OK)`.
 * The daemon had not run and exited first: these segments run after the last
 * march_sched_run() has joined every scheduler thread and the preemption
 * daemon, so the process has ONE OS thread here (task_threads() == 1) and
 * nothing ever dispatches these daemons.  The brand-new proc was, in all
 * likelihood, not fresh: its calloc'd struct reused a block that prodder_loop
 * (above) had written after free.  prodder_loop no longer does that; these
 * checks make a recurrence of the class say which field of which proc was
 * dirty and what the send returned (DEAD vs DROPPED), instead of a bare
 * assert's line number.
 * See specs/progress/2026-09-25-flake-scheduler-mbox-drop-new-daemon-exits.md. */
static void dump_proc(const char *what, int line, march_proc *p) {
    if (!p) {
        fprintf(stderr, "test_scheduler_mbox:%d: %s: proc is NULL\n", line, what);
        return;
    }
    fprintf(stderr,
            "test_scheduler_mbox:%d: %s: proc=%p pid=%lld daemon=%d status=%d "
            "mbox_count=%lld user_mbox_count=%lld mbox_markers=%lld "
            "mbox_limit=%lld mbox_policy=%d stop_requested=%d\n",
            line, what, (void *)p, (long long)p->pid, (int)p->is_daemon,
            (int)atomic_load(&p->status),
            (long long)atomic_load(&p->mbox_count),
            (long long)atomic_load(&p->user_mbox_count),
            (long long)p->mbox_markers, (long long)p->mbox_limit,
            (int)p->mbox_policy, (int)atomic_load(&p->stop_requested));
}

/* Spawn a never-run daemon and check it starts out alive with an empty
 * mailbox and no leftover limit state. */
static march_proc *spawn_fresh_daemon(int line) {
    march_proc *p = march_sched_spawn_daemon(nop, NULL);
    if (!p || atomic_load(&p->status) != PROC_RUNNABLE
            || atomic_load(&p->mbox_count) != 0
            || atomic_load(&p->user_mbox_count) != 0
            || p->mbox_markers != 0 || p->mbox_limit != 0) {
        dump_proc("freshly spawned daemon is not fresh", line, p);
        abort();
    }
    return p;
}

static void expect_send(march_proc *p, void *msg, int want, int line) {
    int got = march_sched_send(p, msg);
    if (got != want) {
        fprintf(stderr, "test_scheduler_mbox:%d: march_sched_send returned %d, "
                        "expected %d (OK=%d DEAD=%d DROPPED=%d)\n",
                line, got, want, MARCH_SEND_OK, MARCH_SEND_DEAD,
                MARCH_SEND_DROPPED);
        dump_proc("send target", line, p);
        abort();
    }
}

/* Default mailbox (mbox_limit == 0, MARCH_MBOX_UNBOUNDED) never rejects. */
static void test_unbounded_default(void) {
    march_proc *u = spawn_fresh_daemon(__LINE__);
    for (int i = 0; i < 100; i++)
        expect_send(u, (void *)0x1, MARCH_SEND_OK, __LINE__);
    assert(march_sched_mbox_count(u) == 100);
}

/* MARCH_MBOX_DROP_NEW: once the mailbox is at capacity, further sends are
 * rejected outright (MARCH_SEND_DROPPED) and the mailbox depth never grows
 * past the limit. */
static void test_drop_new(void) {
    march_proc *dn = spawn_fresh_daemon(__LINE__);
    march_sched_set_mbox_limit(dn, 3, MARCH_MBOX_DROP_NEW);
    expect_send(dn, (void *)0x1, MARCH_SEND_OK, __LINE__);
    expect_send(dn, (void *)0x1, MARCH_SEND_OK, __LINE__);
    expect_send(dn, (void *)0x1, MARCH_SEND_OK, __LINE__);
    expect_send(dn, (void *)0x1, MARCH_SEND_DROPPED, __LINE__);
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

    march_proc *dold = spawn_fresh_daemon(__LINE__);
    march_sched_set_mbox_limit(dold, 2, MARCH_MBOX_DROP_OLD);
    expect_send(dold, (void *)0x3, MARCH_SEND_OK, __LINE__);  /* tagged imm 1 */
    expect_send(dold, (void *)0x5, MARCH_SEND_OK, __LINE__);  /* tagged imm 2 */
    expect_send(dold, (void *)0x7, MARCH_SEND_OK, __LINE__);  /* evicts 0x3 */
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
    /* Watchdog: a reintroduced lost wakeup in the MARCH_MBOX_BLOCK path
     * hangs this process forever, which (run under CI or a plain shell
     * loop with no external timeout) wedges the caller indefinitely
     * instead of failing. alarm(30) converts that hang into SIGALRM ->
     * default action -> nonzero exit, i.e. a normal test FAILURE, well
     * before any CI job-level timeout would otherwise eat the whole
     * remaining budget silently. 30s is generous headroom over this
     * file's actual runtime (well under 1s on an idle host; the
     * live-scheduler segments below are the only ones that can hang at
     * all, since every other segment never calls march_sched_run()). */
    alarm(30);

    test_block_live_scheduler();
    test_block_spurious_wake_while_linked();
    test_spurious_wake_does_not_end_recv();
    test_control_fifo_bypasses_user_policy();
    test_cross_plane_global_fifo();
    test_dead_reap_drain();

    march_sched_init();

    test_unbounded_default();
    test_drop_new();
    test_drop_old();
    test_dead_target_unaffected();

    printf("test_scheduler_mbox: all passed\n");
    return 0;
}
