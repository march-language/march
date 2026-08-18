/* test_broadcast_migrate_leak.c — regression test for the
 * march_actor_broadcast_migrate dead-target message leak
 * (specs/progress/2026-08-12-broadcast-migrate-dead-target-message-leak.md).
 *
 * The bug: march_actor_broadcast_migrate (runtime/march_runtime.c) snapshots
 * matching actors under g_tbl_mu, releases the lock, then for each
 * snapshotted actor malloc's a march_migrate_msg_t and calls
 * march_sched_send(snaps[i]->green_thread, mm) WITHOUT checking the return
 * value. If the target's green thread has already fully died by the time
 * that send runs (a real race: g_tbl_mu is released before Phase 2, and an
 * actor's green_thread field is cleared to NULL / its march_proc transitions
 * to PROC_DEAD asynchronously, on its own green thread, after
 * do_actor_death has already made it "not there" for Phase 1's purposes),
 * march_sched_send returns MARCH_SEND_DEAD without ever taking ownership of
 * mm (see its contract in runtime/march_scheduler.h and its DEAD branches in
 * runtime/march_scheduler.c) -- so nobody ever frees it. The fix wraps the
 * send in `if (march_sched_send(...) == MARCH_SEND_DEAD) free(mm);`.
 *
 * Why this test does NOT drive march_actor_broadcast_migrate itself end to
 * end: reaching MARCH_SEND_DEAD via the real g_actor_tbl snapshot path
 * requires a live actor's green thread to actually finish running its exit
 * sequence (clearing meta->green_thread / reaching PROC_DEAD) in the narrow
 * window between Phase 1's unlock and Phase 2's send -- which only happens
 * on a background scheduler thread that march_spawn starts automatically,
 * racing the calling thread's own progress through the loop. There is no
 * public hook to pause Phase 2 to force that interleaving deterministically,
 * and adding one would mean instrumenting production code for the sake of
 * a test, which is out of scope for this fix. A loop-many-times-and-hope
 * stress test would only be *probabilistically* likely to hit the window,
 * which is exactly the kind of flaky timing-based repro this test is meant
 * to avoid.
 *
 * What IS fully deterministic, single-threaded, and requires no timing
 * assumptions at all: driving a plain (non-actor) proc to PROC_DEAD via the
 * raw scheduler API with no background thread involved (march_sched_run()
 * runs the whole thing to completion on the calling thread, exactly like
 * test_scheduler_mbox.c's test_dead_reap_drain), and then calling
 * march_sched_send on it afterwards. march_proc structs are deliberately
 * never freed on death (see march_scheduler.c's "Deliberately NOT munmap
 * ... / free(p)" comment next to the PROC_DEAD reap branch), so the proc
 * pointer is still valid to pass to march_sched_send here -- this is
 * exactly the shape Phase 2 sees when the race fires: a still-valid
 * march_proc pointer whose status is PROC_DEAD. This test exercises that
 * scenario against march_sched_send directly, using the *exact* malloc +
 * send + conditional-free pattern now in march_actor_broadcast_migrate's
 * Phase 2, and (as a red/green control) shows the pre-fix pattern -- malloc
 * + send, return value ignored -- really does leak under the identical
 * scenario.
 */
#include "march_scheduler.h"
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>

static int g_pass = 0;
static int g_fail = 0;

#define CHECK(cond, name) \
    do { \
        if (cond) { printf("  PASS  %s\n", name); g_pass++; } \
        else      { printf("  FAIL  %s  (line %d)\n", name, __LINE__); g_fail++; } \
    } while (0)

/* Mirrors runtime/march_runtime.h's march_migrate_msg_t / MARCH_MIGRATE_TAG.
 * Duplicated here (rather than #include "march_runtime.h") so this test
 * links only against march_scheduler.c -- the same minimal, decoupled
 * dependency set test_scheduler_mbox.c and friends use -- with zero
 * dependency on march_runtime.c, which this test never calls into. */
#define TEST_MIGRATE_TAG ((int64_t)0x4D494752L)   /* "MIGR" */
typedef struct {
    int64_t  _rc;
    int64_t  _tag;
    void    *(*migrate_fn)(void *);
} test_migrate_msg_t;

/* A proc whose entry function returns immediately: the scheduler marks it
 * PROC_DEAD as soon as march_sched_run() dispatches and retires it. */
static void die_immediately(void *arg) { (void)arg; }

/* Every "Phase 2"-shaped allocation in this test goes through these two
 * wrappers, so the leak check is a plain counter -- no malloc/free
 * interposition needed. */
static int g_outstanding = 0;

static test_migrate_msg_t *alloc_migrate_msg(void) {
    test_migrate_msg_t *mm = (test_migrate_msg_t *)malloc(sizeof(*mm));
    assert(mm);
    mm->_rc        = 1;
    mm->_tag       = TEST_MIGRATE_TAG;
    mm->migrate_fn = NULL;
    g_outstanding++;
    return mm;
}

static void free_migrate_msg(test_migrate_msg_t *mm) {
    free(mm);
    g_outstanding--;
}

/* march_actor_broadcast_migrate's Phase 2 body, FIXED version. */
static void phase2_fixed(march_proc *target) {
    test_migrate_msg_t *mm = alloc_migrate_msg();
    if (march_sched_send(target, mm) == MARCH_SEND_DEAD) {
        free_migrate_msg(mm);
    }
}

/* march_actor_broadcast_migrate's Phase 2 body, PRE-FIX version: the send's
 * return value is ignored, exactly as the bug report describes. Used only
 * as a red control to prove this scenario really did leak before the fix. */
static void phase2_prefix_buggy(march_proc *target) {
    test_migrate_msg_t *mm = alloc_migrate_msg();
    march_sched_send(target, mm);   /* BUG: return value ignored */
}

int main(void) {
    printf("=== march_actor_broadcast_migrate dead-target leak regression ===\n\n");

    /* Deterministically, single-threadedly, drive `victim` to PROC_DEAD.
     * No background scheduler thread is ever started here (that is a
     * march_spawn/march_ensure_sched_started thing, from march_runtime.c,
     * which this test never calls) -- march_sched_run() runs to completion
     * on THIS thread and returns only once every proc (victim included) is
     * fully retired, so there is no window to race here at all. */
    march_sched_init();
    march_proc *victim = march_sched_spawn_daemon(die_immediately, NULL);
    march_sched_request_shutdown();
    march_sched_run();
    CHECK(atomic_load(&victim->status) == PROC_DEAD,
          "victim proc reached PROC_DEAD deterministically");

    /* Precondition the whole bug (and fix) rests on: sending to a target
     * whose green thread has already fully died returns MARCH_SEND_DEAD,
     * not MARCH_SEND_OK -- and does so safely (march_proc is never freed on
     * death, so `victim` is still a valid pointer to dereference). */
    void *probe = (void *)0x1;
    CHECK(march_sched_send(victim, probe) == MARCH_SEND_DEAD,
          "send to an already-PROC_DEAD target returns MARCH_SEND_DEAD");

    /* Red: the pre-fix pattern (malloc + send, ignore the result) leaks
     * exactly one allocation per call against a dead target. */
    g_outstanding = 0;
    phase2_prefix_buggy(victim);
    CHECK(g_outstanding == 1,
          "pre-fix pattern leaks the migrate message (red control)");

    /* Green: the fixed pattern (malloc + send + free-on-DEAD) leaks
     * nothing under the identical scenario. */
    g_outstanding = 0;
    phase2_fixed(victim);
    CHECK(g_outstanding == 0,
          "fixed pattern frees the migrate message on the DEAD path");

    /* Repeat at a scale closer to a real broadcast (MARCH_MIGRATE_SNAPSHOT
     * = 2048 matched actors max in march_runtime.c) against the same dead
     * target -- still fully deterministic, no timing dependency. */
    g_outstanding = 0;
    for (int i = 0; i < 256; i++) phase2_fixed(victim);
    CHECK(g_outstanding == 0,
          "256 repeats of the fixed pattern against a dead target: no leak");

    printf("\n=== Results: %d passed, %d failed ===\n", g_pass, g_fail);
    return g_fail ? 1 : 0;
}
